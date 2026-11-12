import '../services/device_state_service.dart';
import '../widgets/app_feedback.dart';
import '../services/appearance_controller.dart';
import '../services/scroll_chrome_controller.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/reader_cache_directory.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';
import '../services/download_manager.dart';
import '../services/local_page_dimensions.dart';
import '../models/reader_page_geometry.dart';
import '../widgets/reader_page_image.dart';
import '../widgets/reader_toolbar.dart';
import '../widgets/webtoon_view.dart';
import '../widgets/reader_scroll_controller.dart';
import '../services/reader_image_session.dart';
import '../widgets/reader_page_provider.dart';
import '../widgets/reader_paged_view.dart';
import '../widgets/yomi_blobatar_studio.dart';
import '../services/profile_palette_service.dart';
import '../models/reader_anchor.dart';
import 'home_tabs.dart';
import 'manga_detail_screen.dart';

class ReaderScreen extends StatefulWidget {
  final Manga manga;
  final Chapter chapter;
  final List<Chapter> allChapters;

  const ReaderScreen({
    super.key,
    required this.manga,
    required this.chapter,
    required this.allChapters,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  List<String> _localFilePaths = [];
  ChapterPagesData? _onlinePagesData;
  late List<Chapter> _chapters;
  bool _isOfflineMode = false;
  ProfileAdaptivePalette? _readerPalette;
  late InternetState _lastInternet;

  void _onDeviceChanged() {
    final internet = DeviceStateService.instance.value.internet;
    if (internet == _lastInternet || !mounted) return;
    _lastInternet = internet;
    setState(() {});
    if (internet == InternetState.online &&
        !_isOfflineMode &&
        !_isLoading &&
        _onlinePagesData == null) {
      setState(() => _isLoading = true);
      _initReaderSource();
    } else if (internet == InternetState.offline && !_isOfflineMode) {
      AppFeedback.message(
        context,
        'Modo offline: apenas páginas já carregadas ou capítulos baixados estão disponíveis.',
      );
    }
  }

  bool _isLoading = true;
  String? _sourceError;
  bool _isWebtoonMode = true;
  bool _showHud = true;
  final _chrome = ScrollChromeController();

  void _syncChrome() {
    if (mounted && _showHud != _chrome.visible) {
      setState(() => _showHud = _chrome.visible);
    }
  }

  void _onAppearanceChanged() {
    if (!AppearanceController.instance.value.autoHideMenus) _chrome.show();
  }

  void _toggleHud() => _chrome.setVisible(!_showHud);

  int _currentPage = 0;
  int _lastSavedPage = -1;
  final _visiblePage = ValueNotifier<int>(0);
  ReaderPageGeometry? _geometry;
  double _pageWidth = 0;
  bool _replacingChapter = false;
  ReaderImageSession? _images;
  final Map<int, int> _imageAttempts = {};
  final Set<int> _retryingImages = {};

  List<Chapter> _mergeAndSortChapters(Iterable<Chapter> extra) {
    final cached = StorageService.getCachedMangaChapters(widget.manga.id);
    final byNumber = <String, Chapter>{};

    void consider(Chapter c) {
      final key = c.chapterNumber.trim();
      final existing = byNumber[key];
      if (existing == null) {
        byNumber[key] = c;
      } else if (c.id == widget.chapter.id) {
        byNumber[key] = c;
      } else if (existing.id != widget.chapter.id) {
        if (c.language == widget.chapter.language &&
            existing.language != widget.chapter.language) {
          byNumber[key] = c;
        } else if (c.language == 'PT-BR' && existing.language != 'PT-BR') {
          byNumber[key] = c;
        }
      }
    }

    for (final c in cached) {
      consider(c);
    }
    for (final c in widget.allChapters) {
      consider(c);
    }
    for (final c in extra) {
      consider(c);
    }
    consider(widget.chapter);

    final sorted = byNumber.values.toList()
      ..sort((a, b) => a.numericChapter.compareTo(b.numericChapter));
    return sorted;
  }

  Future<void> _ensureChapterListLoaded() async {
    if (_chapters.length > 1 && _nextChapter != null) return;
    try {
      final fetched = await MangaDexService.fetchChapters(widget.manga);
      if (fetched.isNotEmpty) {
        await StorageService.cacheMangaChapters(widget.manga.id, fetched);
        if (mounted) {
          setState(() {
            _chapters = _mergeAndSortChapters(fetched);
          });
        }
      }
    } catch (_) {}
  }

  void _openMangaPage() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaDetailScreen(
          manga: widget.manga,
          heroTag: 'reader_manga_${widget.manga.compositeId}',
        ),
      ),
    ).then((_) {
      if (mounted) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  void _recordPage(int index) {
    if (index == _lastSavedPage) return;
    _currentPage = index;
    _visiblePage.value = index;
    _lastSavedPage = index;
    StorageService.saveLastPageIndex(widget.chapter.id, index);
    if (!_isWebtoonMode) {
      StorageService.saveWebtoonAnchor(
        widget.chapter.id,
        ReaderAnchor(index, 0),
      );
    }
    // Warm the next page as reading advances, not just at chapter open.
    if (!_isOfflineMode && _onlinePagesData != null) {
      final urls = _onlinePagesData!.getUrls(
        useDataSaver: StorageService.dataSaverEnabled,
      );
      _warmNextPage(urls);
    }
  }

  late PageController _pageController;
  late ReaderScrollController _webtoonScrollController;
  Timer? _webtoonProgressTimer;

  void _onWebtoonScroll() {
    _webtoonProgressTimer?.cancel();
    _webtoonProgressTimer = Timer(
      const Duration(milliseconds: 250),
      _saveWebtoonPosition,
    );
  }

  void _saveWebtoonPosition() {
    if (!mounted || !_webtoonScrollController.hasClients) return;
    final position = _webtoonScrollController.position;
    final offset = position.pixels
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    StorageService.saveWebtoonOffset(widget.chapter.id, offset);

    final geometry = _geometry;
    if (geometry != null && geometry.pageCount > 0 && _pageWidth > 0) {
      StorageService.saveWebtoonAnchor(
        widget.chapter.id,
        geometry.anchorAt(offset, _pageWidth),
      );
      _recordPage(
        geometry.pageAt(offset, _pageWidth).clamp(0, geometry.pageCount - 1),
      );
    }
  }

  void _prepareGeometry(int count, [Map<int, double> ratios = const {}]) {
    _geometry = ReaderPageGeometry(count)..updateRatios(ratios, 1, 0);
    if (count > 0) {
      final restored = _currentPage.clamp(0, count - 1);
      if (restored != _currentPage) {
        _lastSavedPage = restored;
        StorageService.saveLastPageIndex(widget.chapter.id, restored);
      }
      _currentPage = restored;
    }
    _visiblePage.value = _currentPage;
    final saved = StorageService.getWebtoonAnchor(widget.chapter.id);
    final legacyOffset = StorageService.getSavedWebtoonOffset(
      widget.chapter.id,
    );
    final anchor =
        saved ??
        (legacyOffset == 0 && _currentPage > 0
            ? ReaderAnchor(_currentPage, 0)
            : null);
    final initialOffset = anchor == null
        ? legacyOffset
        : _geometry!.offsetFor(anchor, MediaQuery.sizeOf(context).width);
    _webtoonScrollController.dispose();
    _webtoonScrollController = ReaderScrollController(
      initialScrollOffset: initialOffset,
    )..addListener(_onWebtoonScroll);
    _pageController.dispose();
    _pageController = PageController(
      initialPage: _currentPage,
      keepPage: false,
    );
  }

  void _toggleMode() {
    if (_isWebtoonMode) {
      _saveWebtoonPosition();
      _pageController.dispose();
      _pageController = PageController(
        initialPage: _currentPage,
        keepPage: false,
      );
    }
    if (!_isWebtoonMode && _geometry != null) {
      final saved = StorageService.getWebtoonAnchor(widget.chapter.id);
      final anchor = saved?.page == _currentPage
          ? saved!
          : ReaderAnchor(_currentPage, 0);
      _webtoonScrollController.correctLayoutOffset(
        _geometry!.offsetFor(anchor, MediaQuery.sizeOf(context).width),
      );
    }
    setState(() => _isWebtoonMode = !_isWebtoonMode);
  }

  @override
  void initState() {
    super.initState();
    _lastInternet = DeviceStateService.instance.value.internet;
    DeviceStateService.instance.addListener(_onDeviceChanged);
    _readerPalette = ProfilePaletteService.synchronousFallbackForManga(
      widget.manga,
    );
    _chapters = _mergeAndSortChapters(const []);
    _chrome.addListener(_syncChrome);
    AppearanceController.instance.addListener(_onAppearanceChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Limita o cache de imagens decodificadas para evitar pressão de memória.
    // Páginas fora da janela visível poderão ser descartadas pelo Flutter.
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 80;

    _currentPage = StorageService.getSavedPageIndex(widget.chapter.id);
    _lastSavedPage = _currentPage;
    _visiblePage.value = _currentPage;
    _pageController = PageController(initialPage: _currentPage);
    _webtoonScrollController = ReaderScrollController(
      initialScrollOffset: StorageService.getSavedWebtoonOffset(
        widget.chapter.id,
      ),
    )..addListener(_onWebtoonScroll);
    StorageService.recordChapterOpened(widget.manga, widget.chapter);
    ProfilePaletteService.resolveForManga(widget.manga).then((palette) {
      if (mounted) setState(() => _readerPalette = palette);
    });
    _initReaderSource();
    _ensureChapterListLoaded();
  }

  @override
  void dispose() {
    DeviceStateService.instance.removeListener(_onDeviceChanged);
    _webtoonProgressTimer?.cancel();
    AppearanceController.instance.removeListener(_onAppearanceChanged);
    _chrome.dispose();
    if (_isWebtoonMode && _webtoonScrollController.hasClients) {
      final position = _webtoonScrollController.position;
      if (_geometry != null && _pageWidth > 0) {
        final anchor = _geometry!.anchorAt(position.pixels, _pageWidth);
        StorageService.saveWebtoonAnchor(widget.chapter.id, anchor);
        StorageService.saveLastPageIndex(widget.chapter.id, anchor.page);
      }
      StorageService.saveWebtoonOffset(
        widget.chapter.id,
        position.pixels.clamp(0.0, position.maxScrollExtent).toDouble(),
      );
    }
    _webtoonScrollController.dispose();
    _pageController.dispose();
    _visiblePage.dispose();
    _images?.close();
    if (!_replacingChapter) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  int get _currentChapterIndex {
    final byId = _chapters.indexWhere((c) => c.id == widget.chapter.id);
    if (byId != -1) return byId;
    return _chapters.indexWhere(
      (c) => c.chapterNumber.trim() == widget.chapter.chapterNumber.trim(),
    );
  }

  Chapter? get _nextChapter {
    final idx = _currentChapterIndex;
    if (idx != -1 && idx + 1 < _chapters.length) {
      return _chapters[idx + 1];
    }
    return null;
  }

  Chapter? get _prevChapter {
    final idx = _currentChapterIndex;
    if (idx > 0 && idx < _chapters.length) {
      return _chapters[idx - 1];
    }
    return null;
  }

  void _goToChapter(Chapter target) {
    // The next reader records the newly opened chapter as in progress.
    _replacingChapter = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          manga: widget.manga,
          chapter: target,
          allChapters: _chapters,
        ),
      ),
    );
  }

  Future<void> _markCurrentChapterFinished() async {
    await StorageService.markChapterAsRead(widget.manga, widget.chapter);
    if (!mounted) return;
    AppFeedback.show(
      context,
      const SnackBar(content: Text('Capítulo marcado como concluído')),
    );
  }

  int _lastPrefetchedPage = -1;

  void _warmNextPage(List<String> urls) {
    if (urls.isEmpty || !mounted) return;
    final next = _currentPage + 1;
    if (next >= urls.length || next == _lastPrefetchedPage) return;
    _lastPrefetchedPage = next;
    // Only one upcoming page; do not eagerly decode the entire chapter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = _providerFor(next);
      precacheImage(provider, context).catchError((Object _) {});
    });
  }

  Future<void> _initReaderSource() async {
    _sourceError = null;
    if (!kIsWeb && StorageService.isChapterDownloaded(widget.chapter.id)) {
      if (await DownloadManager.hasCompleteDownload(widget.chapter.id)) {
        final localPaths = StorageService.getDownloadedChapterPaths(
          widget.chapter.id,
        );
        final ratios = await LocalPageDimensions.read(localPaths);
        if (mounted) {
          _images = ReaderImageSession(localPaths: localPaths);
          _prepareGeometry(localPaths.length, ratios);
          setState(() {
            _localFilePaths = localPaths;
            _isOfflineMode = true;
            _isLoading = false;
          });
        }
        return;
      }
      // Preserve existing partial files for resuming, but stop advertising
      // a broken offline chapter as successfully downloaded.
      await StorageService.downloadsBox.delete(widget.chapter.id);
    }

    if (DeviceStateService.instance.isOffline) {
      if (mounted) {
        setState(() {
          _sourceError =
              'Este capítulo não foi baixado por completo. Reconecte para baixá-lo em Biblioteca → Baixados.';
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) AppFeedback.message(context, _sourceError!);
        });
      }
      return;
    }
    try {
      final data = await MangaDexService.fetchChapterPages(widget.chapter);
      if (mounted) {
        _images = ReaderImageSession(
          createCacheDirectory: kIsWeb ? null : ReaderCacheDirectory.create,
          urls: data.getUrls(useDataSaver: StorageService.dataSaverEnabled),
          headers: widget.manga.customHeaders,
          reloadUrls: () async => (await MangaDexService.fetchChapterPages(
            widget.chapter,
          )).getUrls(useDataSaver: StorageService.dataSaverEnabled),
        );
        _prepareGeometry(
          data.getUrls(useDataSaver: StorageService.dataSaverEnabled).length,
        );
        setState(() {
          _onlinePagesData = data;
          _isOfflineMode = false;
          _isLoading = false;
        });
        // Warm just one nearby page to reduce the first swipe delay.
        _warmNextPage(
          data.getUrls(useDataSaver: StorageService.dataSaverEnabled),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _sourceError = error is UnsupportedError
              ? error.message?.toString()
              : 'Não foi possível carregar o capítulo. Verifique sua conexão e tente novamente.';
        });
        AppFeedback.message(
          context,
          _sourceError ?? 'Não foi possível abrir este capítulo.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineUrls =
        _onlinePagesData?.getUrls(
          useDataSaver: StorageService.dataSaverEnabled,
        ) ??
        [];
    final totalPages = _isOfflineMode
        ? _localFilePaths.length
        : onlineUrls.length;
    // Chapter files can change between sessions. Never restore a page
    // beyond the number of pages actually available.
    if (totalPages > 0 && _currentPage >= totalPages) {
      _currentPage = totalPages - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(_currentPage);
        StorageService.saveLastPageIndex(widget.chapter.id, _currentPage);
      });
    }
    final nextCh = _nextChapter;
    final prevCh = _prevChapter;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: YomiPalette.ensoRed),
            )
          : totalPages == 0
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: YomiPalette.ensoRed,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _sourceError ??
                          'Não foi possível carregar as páginas deste capítulo ou você está sem conexão.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openMangaPage,
                          icon: const Icon(Icons.menu_book_rounded),
                          label: const Text('Página do Mangá'),
                        ),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Voltar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                if (_isWebtoonMode)
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) =>
                        AppearanceController.instance.value.autoHideMenus
                        ? _chrome.onScroll(notification)
                        : false,
                    child: WebtoonView(
                      geometry: _geometry!,
                      controller: _webtoonScrollController,
                      onWidth: (width) => _pageWidth = width,
                      localDimensionsKnown: _isOfflineMode,
                      onTap: _toggleHud,
                      footer: _buildEndOfChapterFooter(nextCh, prevCh),
                      pageBuilder: (context, index, onRatio) => ReaderPageImage(
                        key: ValueKey('$index-${_imageAttempts[index] ?? 0}'),
                        image: _providerFor(index),
                        pageNumber: index + 1,
                        onRatio: onRatio,
                        onRetry: () => _retryImage(index),
                      ),
                    ),
                  )
                else
                  ReaderPagedView(
                    controller: _pageController,
                    pageCount: totalPages,
                    imageForPage: _providerFor,
                    onPageChanged: (index) => _recordPage(index),
                    onRetry: _retryImage,
                    onToggleHud: _toggleHud,
                  ),

                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !_showHud,
                    child: ExcludeSemantics(
                      excluding: !_showHud,
                      child: AnimatedSlide(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        offset: Offset(0, _showHud ? 0 : -1),
                        curve: Curves.easeOutCubic,
                        child: ValueListenableBuilder<int>(
                          valueListenable: _visiblePage,
                          builder: (context, page, _) => ReaderToolbar(
                            palette: _readerPalette,
                            title: widget.manga.title,
                            chapter: widget.chapter.chapterNumber,
                            page: page,
                            total: totalPages,
                            visible: _showHud,
                            offline:
                                _isOfflineMode ||
                                DeviceStateService.instance.isOffline,
                            webtoon: _isWebtoonMode,
                            onBack: () => Navigator.pop(context),
                            onMode: _toggleMode,
                            onComplete: _markCurrentChapterFinished,
                            onOpenManga: _openMangaPage,
                            onPrevious: prevCh == null
                                ? null
                                : () => _goToChapter(prevCh),
                            onNext: nextCh == null
                                ? null
                                : () => _goToChapter(nextCh),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  ImageProvider _providerFor(int index) {
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(480, 1440)
            .toInt();
    return ResizeImage(
      ReaderPageProvider(_images!, index, attempt: _imageAttempts[index] ?? 0),
      width: width,
    );
  }

  Future<void> _retryImage(int index) async {
    if (_images == null || !_retryingImages.add(index)) return;
    try {
      await _providerFor(index).evict();
      await _images!.retry(index);
      if (mounted) {
        setState(
          () => _imageAttempts[index] = (_imageAttempts[index] ?? 0) + 1,
        );
      }
    } finally {
      _retryingImages.remove(index);
    }
  }

  void _returnToLibrary() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _buildEndOfChapterFooter(Chapter? nextCh, Chapter? prevCh) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        StorageService.profileNotifier,
        ProfilePaletteService.paletteNotifier,
      ]),
      builder: (context, _) {
        final profile = StorageService.profileNotifier.value;
        final palette = AppearanceController.instance.value.reactiveReader
            ? _readerPalette ?? ProfilePaletteService.paletteNotifier.value
            : ProfilePaletteService.paletteNotifier.value;
        final mascotName = profile.effectiveBlobatarName;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          color: YomiPalette.pitchBlack,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: palette.surfaceTint,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.38),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: TickerMode(
                        enabled: !reduceMotion,
                        child: YomiProfileBlobatar(
                          profile: profile,
                          size: 74,
                          adaptiveHue: palette.hue,
                          overrideExpressionId: 'love',
                          interactiveCycleOnTap: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Fim do Capítulo ${widget.chapter.chapterNumber}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      nextCh != null
                          ? '$mascotName adorou ler com você! O próximo capítulo já está disponível.'
                          : '$mascotName comemorou: você alcançou o capítulo mais recente desta fonte!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: palette.soft),
                    ),
                    const SizedBox(height: 20),
                    if (nextCh != null) ...[
                      FilledButton.icon(
                        onPressed: () async {
                          await StorageService.markChapterAsRead(
                            widget.manga,
                            widget.chapter,
                          );
                          if (mounted) _goToChapter(nextCh);
                        },
                        icon: const Icon(Icons.skip_next_rounded),
                        label: Text(
                          'Continuar: Cap. ${nextCh.chapterNumber}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(14) / 14;
                        final vertical =
                            constraints.maxWidth < 340 || textScale > 1.25;
                        final backToMangaBtn = OutlinedButton.icon(
                          onPressed: _openMangaPage,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: palette.secondary.withValues(alpha: 0.45),
                            ),
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.menu_book_rounded, size: 18),
                          label: const Text('Ver página do mangá'),
                        );
                        final returnLibraryBtn = OutlinedButton.icon(
                          onPressed: _returnToLibrary,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.soft,
                            side: const BorderSide(color: Colors.white24),
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(
                            Icons.collections_bookmark_rounded,
                            size: 18,
                          ),
                          label: const Text('Retornar à biblioteca'),
                        );
                        if (vertical) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              backToMangaBtn,
                              const SizedBox(height: 8),
                              returnLibraryBtn,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: backToMangaBtn),
                            const SizedBox(width: 10),
                            Expanded(child: returnLibraryBtn),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _markCurrentChapterFinished,
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Marcar como concluído'),
                        ),
                        if (prevCh != null)
                          TextButton.icon(
                            onPressed: () => _goToChapter(prevCh),
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              size: 18,
                            ),
                            label: Text('Cap. anterior (${prevCh.chapterNumber})'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
