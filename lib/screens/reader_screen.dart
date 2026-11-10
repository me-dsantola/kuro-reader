import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';
import '../services/download_manager.dart';
import '../services/local_page_dimensions.dart';
import '../models/reader_page_geometry.dart';
import '../widgets/reader_page_image.dart';
import '../widgets/reader_toolbar.dart';
import '../widgets/webtoon_view.dart';
import 'home_tabs.dart';

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
  bool _isOfflineMode = false;
  bool _isLoading = true;
  bool _isWebtoonMode = true;
  bool _showHud = true;
  int _currentPage = 0;
  int _lastSavedPage = -1;
  final _visiblePage = ValueNotifier<int>(0);
  ReaderPageGeometry? _geometry;
  double _pageWidth = 0;
  bool _replacingChapter = false;

  void _recordPage(int index) {
    if (index == _lastSavedPage) return;
    _currentPage = index;
    _visiblePage.value = index;
    _lastSavedPage = index;
    StorageService.saveLastPageIndex(widget.chapter.id, index);
    // Warm the next page as reading advances, not just at chapter open.
    if (!_isOfflineMode && _onlinePagesData != null) {
      final urls = _onlinePagesData!.getUrls(
        useDataSaver: StorageService.dataSaverEnabled,
      );
      _warmNextPage(urls);
    }
  }

  late PageController _pageController;
  late final ScrollController _webtoonScrollController;
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
    setState(() => _isWebtoonMode = !_isWebtoonMode);
    if (_isWebtoonMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_webtoonScrollController.hasClients ||
            _geometry == null) {
          return;
        }
        final target = _geometry!.offsetOf(_currentPage, _pageWidth);
        _webtoonScrollController.jumpTo(
          target
              .clamp(0.0, _webtoonScrollController.position.maxScrollExtent)
              .toDouble(),
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Limita o cache de imagens decodificadas para evitar pressão de memória.
    // Páginas fora da janela visível poderão ser descartadas pelo Flutter.
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 80;

    _currentPage = StorageService.getSavedPageIndex(widget.chapter.id);
    _lastSavedPage = _currentPage;
    _visiblePage.value = _currentPage;
    _pageController = PageController(initialPage: _currentPage);
    _webtoonScrollController = ScrollController(
      initialScrollOffset: StorageService.getSavedWebtoonOffset(
        widget.chapter.id,
      ),
    )..addListener(_onWebtoonScroll);
    StorageService.recordChapterOpened(widget.manga, widget.chapter);
    _initReaderSource();
  }

  @override
  void dispose() {
    _webtoonProgressTimer?.cancel();
    if (_isWebtoonMode && _webtoonScrollController.hasClients) {
      final position = _webtoonScrollController.position;
      StorageService.saveWebtoonOffset(
        widget.chapter.id,
        position.pixels.clamp(0.0, position.maxScrollExtent).toDouble(),
      );
    }
    _webtoonScrollController.dispose();
    _pageController.dispose();
    _visiblePage.dispose();
    if (!_replacingChapter) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Chapter? get _nextChapter {
    final idx = widget.allChapters.indexWhere((c) => c.id == widget.chapter.id);
    if (idx != -1 && idx + 1 < widget.allChapters.length) {
      return widget.allChapters[idx + 1];
    }
    return null;
  }

  Chapter? get _prevChapter {
    final idx = widget.allChapters.indexWhere((c) => c.id == widget.chapter.id);
    if (idx > 0 && idx < widget.allChapters.length) {
      return widget.allChapters[idx - 1];
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
          allChapters: widget.allChapters,
        ),
      ),
    );
  }

  Future<void> _markCurrentChapterFinished() async {
    await StorageService.markChapterAsRead(widget.manga, widget.chapter);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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
      final provider = ResizeImage(
        NetworkImage(
          urls[next],
          headers: kIsWeb ? null : widget.manga.customHeaders,
        ),
        width:
            (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .ceil()
                .clamp(480, 1440)
                .toInt(),
      );
      precacheImage(provider, context).catchError((Object _) {});
    });
  }

  Future<void> _initReaderSource() async {
    if (!kIsWeb && StorageService.isChapterDownloaded(widget.chapter.id)) {
      if (await DownloadManager.hasCompleteDownload(widget.chapter.id)) {
        final localPaths = StorageService.getDownloadedChapterPaths(
          widget.chapter.id,
        );
        final ratios = await LocalPageDimensions.read(localPaths);
        if (mounted) {
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

    try {
      final data = await MangaDexService.fetchChapterPages(widget.chapter);
      if (mounted) {
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
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
                    const Text(
                      'Não foi possível carregar as páginas deste capítulo ou você está sem conexão.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Voltar para a Obra'),
                    ),
                  ],
                ),
              ),
            )
          : GestureDetector(
              onTap: () => setState(() => _showHud = !_showHud),
              child: Stack(
                children: [
                  if (_isWebtoonMode)
                    WebtoonView(
                      geometry: _geometry!,
                      controller: _webtoonScrollController,
                      onWidth: (width) => _pageWidth = width,
                      localDimensionsKnown: _isOfflineMode,
                      footer: _buildEndOfChapterFooter(nextCh, prevCh),
                      pageBuilder: (context, index, onRatio) =>
                          _WebtoonPageTile(
                            key: ValueKey('page-$index'),
                            pageIndex: index,
                            localPath: _isOfflineMode
                                ? _localFilePaths[index]
                                : null,
                            imageUrl: _isOfflineMode ? null : onlineUrls[index],
                            headers: widget.manga.customHeaders,
                            onRatio: onRatio,
                          ),
                    )
                  else
                    PhotoViewGallery.builder(
                      pageController: _pageController,
                      itemCount: totalPages,
                      onPageChanged: (index) {
                        _recordPage(index);
                        setState(() {});
                      },
                      builder: (context, index) {
                        final ImageProvider provider = _isOfflineMode
                            ? FileImage(File(_localFilePaths[index]))
                            : ResizeImage(
                                NetworkImage(
                                  onlineUrls[index],
                                  headers: kIsWeb
                                      ? null
                                      : widget.manga.customHeaders,
                                ),
                                width:
                                    (MediaQuery.sizeOf(context).width *
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ))
                                        .ceil()
                                        .clamp(480, 1440)
                                        .toInt(),
                              );

                        return PhotoViewGalleryPageOptions(
                          imageProvider: provider,
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 3.0,
                        );
                      },
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
                              title: widget.manga.title,
                              chapter: widget.chapter.chapterNumber,
                              page: page,
                              total: totalPages,
                              offline: _isOfflineMode,
                              webtoon: _isWebtoonMode,
                              onBack: () => Navigator.pop(context),
                              onMode: _toggleMode,
                              onComplete: _markCurrentChapterFinished,
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
            ),
    );
  }

  Widget _buildEndOfChapterFooter(Chapter? nextCh, Chapter? prevCh) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      color: YomiPalette.pitchBlack,
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 44,
            color: YomiPalette.ensoRed,
          ),
          const SizedBox(height: 12),
          Text(
            'Fim do Capítulo ${widget.chapter.chapterNumber}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _markCurrentChapterFinished,
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Marcar como concluído'),
          ),
          const SizedBox(height: 12),
          if (nextCh != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  StorageService.markChapterAsRead(
                    widget.manga,
                    widget.chapter,
                  );
                  _goToChapter(nextCh);
                },
                icon: const Icon(Icons.skip_next_rounded),
                label: Text('Ler Próximo: Cap. ${nextCh.chapterNumber}'),
                style: FilledButton.styleFrom(
                  backgroundColor: YomiPalette.ensoRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            )
          else
            const Text(
              'Você chegou ao capítulo mais recente desta fonte!',
              style: TextStyle(color: Colors.white54),
            ),
          if (prevCh != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _goToChapter(prevCh),
              icon: const Icon(Icons.skip_previous_rounded),
              label: Text('Voltar para Cap. ${prevCh.chapterNumber}'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Recycled page content. Its extent is always supplied by chapter geometry.
class _WebtoonPageTile extends StatefulWidget {
  final int pageIndex;
  final String? localPath;
  final String? imageUrl;
  final Map<String, String> headers;
  final ValueChanged<double> onRatio;

  const _WebtoonPageTile({
    super.key,
    required this.pageIndex,
    this.localPath,
    this.imageUrl,
    required this.headers,
    required this.onRatio,
  });

  @override
  State<_WebtoonPageTile> createState() => _WebtoonPageTileState();
}

class _WebtoonPageTileState extends State<_WebtoonPageTile> {
  int _mirror = 0;
  int _retry = 0;

  @override
  void didUpdateWidget(covariant _WebtoonPageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.localPath != widget.localPath) {
      _mirror = 0;
      _retry++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = yomiCandidateImageUrls(widget.imageUrl ?? '');
    final url = urls.isEmpty
        ? (widget.imageUrl ?? '')
        : urls[_mirror.clamp(0, urls.length - 1)];
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(480, 1440)
            .toInt();
    final ImageProvider source = widget.localPath != null
        ? FileImage(File(widget.localPath!))
        : NetworkImage(url, headers: kIsWeb ? null : widget.headers);
    final provider = ResizeImage(source, width: width);
    return ReaderPageImage(
      key: ValueKey('${widget.localPath ?? url}_$_retry'),
      image: provider,
      pageNumber: widget.pageIndex + 1,
      onRatio: widget.onRatio,
      onError: () {
        if (widget.localPath == null && _mirror + 1 < urls.length) {
          setState(() => _mirror++);
        }
      },
      onRetry: () async {
        await provider.evict();
        if (mounted) setState(() => _retry++);
      },
    );
  }
}
