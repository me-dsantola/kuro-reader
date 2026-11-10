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

  void _recordPage(int index) {
    if (index == _lastSavedPage) return;
    _currentPage = index;
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
  final Map<int, GlobalKey> _webtoonItemKeys = {};
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
    final offset = position.pixels.clamp(0.0, position.maxScrollExtent).toDouble();
    StorageService.saveWebtoonOffset(widget.chapter.id, offset);

    // ListView builds tiles beyond the visible area. Only the viewport,
    // measured after scrolling settles, can determine the current page.
    final viewportHeight = MediaQuery.sizeOf(context).height;
    int? visiblePage;
    double closestBottom = double.infinity;
    for (final entry in _webtoonItemKeys.entries) {
      final render = entry.value.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) continue;
      final top = render.localToGlobal(Offset.zero).dy;
      final bottom = top + render.size.height;
      if (bottom <= 0 || top >= viewportHeight) continue;
      if (bottom < closestBottom) {
        closestBottom = bottom;
        visiblePage = entry.key;
      }
    }
    if (visiblePage != null) _recordPage(visiblePage);
  }

  // Cache em memória da proporção real (altura/largura) de cada página já carregada.
  // Isso garante que se qualquer página precisar de layout ao rolar para cima, a altura seja 100% idêntica, sem pulos!
  final Map<int, double> _pageAspectRatios = {};

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
    _pageController = PageController(initialPage: _currentPage);
    _webtoonScrollController = ScrollController(
      initialScrollOffset: StorageService.getSavedWebtoonOffset(widget.chapter.id),
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
        width: (MediaQuery.sizeOf(context).width *
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
      final localPaths = StorageService.getDownloadedChapterPaths(
        widget.chapter.id,
      );
      if (localPaths.isNotEmpty && await File(localPaths.first).exists()) {
        if (mounted) {
          setState(() {
            _localFilePaths = localPaths;
            _isOfflineMode = true;
            _isLoading = false;
          });
        }
        return;
      }
    }

    try {
      final data = await MangaDexService.fetchChapterPages(widget.chapter);
      if (mounted) {
        setState(() {
          _onlinePagesData = data;
          _isOfflineMode = false;
          _isLoading = false;
        });
        // Warm just one nearby page to reduce the first swipe delay.
        _warmNextPage(data.getUrls(
          useDataSaver: StorageService.dataSaverEnabled,
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineUrls = _onlinePagesData?.getUrls(
          useDataSaver: StorageService.dataSaverEnabled,
        ) ??
        [];
    final totalPages =
        _isOfflineMode ? _localFilePaths.length : onlineUrls.length;
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
                        ListView.builder(
                          controller: _webtoonScrollController,
                          padding: EdgeInsets.zero,
                          // Mantém apenas uma pequena janela ao redor da área visível.
                          cacheExtent: 800,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          itemCount: totalPages + 1,
                          itemBuilder: (context, index) {
                            if (index == totalPages) {
                              return _buildEndOfChapterFooter(nextCh, prevCh);
                            }

                            return _KeepAlivePageTile(
                              key: _webtoonItemKeys.putIfAbsent(
                                index,
                                () => GlobalKey(),
                              ),
                              pageIndex: index,
                              isOffline: _isOfflineMode,
                              localPath: _isOfflineMode ? _localFilePaths[index] : null,
                              imageUrl: !_isOfflineMode ? onlineUrls[index] : null,
                              headers: widget.manga.customHeaders,
                              cachedAspectRatio: _pageAspectRatios[index],
                              onAspectRatioResolved: (ratio) {
                                _pageAspectRatios[index] = ratio;
                              },
                            );
                          },
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
                                    width: (MediaQuery.sizeOf(context).width *
                                            MediaQuery.devicePixelRatioOf(context))
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

                      // BARRA SUPERIOR (HUD)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 220),
                        top: _showHud ? 0 : -115,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 42, 12, 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.88),
                            border: const Border(
                              bottom: BorderSide(color: Colors.white10),
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.manga.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Cap. ${widget.chapter.chapterNumber} • $totalPages págs ${_isOfflineMode ? "• OFFLINE" : ""}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: YomiPalette.sakuraPink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (prevCh != null)
                                IconButton(
                                  tooltip: 'Anterior: Cap. ${prevCh.chapterNumber}',
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  onPressed: () => _goToChapter(prevCh),
                                ),
                              if (nextCh != null)
                                IconButton(
                                  tooltip: 'Próximo: Cap. ${nextCh.chapterNumber}',
                                  icon: const Icon(Icons.skip_next_rounded),
                                  onPressed: () => _goToChapter(nextCh),
                                ),
                              IconButton(
                                tooltip: 'Alternar Rolagem Contínua / Paginado',
                                icon: Icon(
                                  _isWebtoonMode
                                      ? Icons.view_day_rounded
                                      : Icons.view_carousel_rounded,
                                  color: YomiPalette.ensoRed,
                                ),
                                onPressed: () {
                                  setState(
                                      () => _isWebtoonMode = !_isWebtoonMode);
                                },
                              ),
                            ],
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          if (nextCh != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _goToChapter(nextCh),
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

/// Página descartável: o Flutter recicla widgets distantes da área visível.
class _KeepAlivePageTile extends StatefulWidget {
  final int pageIndex;
  final bool isOffline;
  final String? localPath;
  final String? imageUrl;
  final Map<String, String> headers;
  final double? cachedAspectRatio;
  final ValueChanged<double> onAspectRatioResolved;

  const _KeepAlivePageTile({
    super.key,
    required this.pageIndex,
    required this.isOffline,
    this.localPath,
    this.imageUrl,
    required this.headers,
    this.cachedAspectRatio,
    required this.onAspectRatioResolved,
  });

  @override
  State<_KeepAlivePageTile> createState() => _KeepAlivePageTileState();
}

class _KeepAlivePageTileState extends State<_KeepAlivePageTile> {
  late List<String> _candidates;
  int _mirrorIdx = 0;

  @override
  void initState() {
    super.initState();
    _candidates = yomiCandidateImageUrls(widget.imageUrl ?? '');
  }

  @override
  void didUpdateWidget(covariant _KeepAlivePageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.localPath != widget.localPath) {
      _candidates = yomiCandidateImageUrls(widget.imageUrl ?? '');
      _mirrorIdx = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isOffline && widget.localPath != null) {
      return Image.file(
        File(widget.localPath!),
        fit: BoxFit.fitWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    final activeUrl = _candidates.isNotEmpty && _mirrorIdx < _candidates.length
        ? _candidates[_mirrorIdx]
        : (widget.imageUrl ?? '');

    return Image.network(
      activeUrl,
      headers: kIsWeb ? null : widget.headers,
      fit: BoxFit.fitWidth,
      gaplessPlayback: true,
      // Keep decoded webtoon pages bounded on high-DPI phones.
      cacheWidth: (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(480, 1440)
          .toInt(),
      filterQuality: FilterQuality.low,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        final screenWidth = MediaQuery.of(context).size.width;
        final estimatedHeight = widget.cachedAspectRatio != null
            ? screenWidth / widget.cachedAspectRatio!
            : screenWidth * 1.42;
        final expected = loadingProgress.expectedTotalBytes;
        final loaded = loadingProgress.cumulativeBytesLoaded;
        final progress =
            (expected != null && expected > 0) ? loaded / expected : null;
        return SizedBox(
          height: estimatedHeight,
          width: double.infinity,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.5,
                    color: YomiPalette.ensoRed,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pág. ${widget.pageIndex + 1}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        if (_mirrorIdx + 1 < _candidates.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _mirrorIdx++);
          });
        }
        return Container(
          height: 320,
          color: YomiPalette.surface,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Tentar carregar esta página novamente',
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: YomiPalette.ensoRed,
                ),
                onPressed: () {
                  final url = activeUrl;
                  final decodeWidth = (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(480, 1440)
                      .toInt();
                  ResizeImage(
                    NetworkImage(
                      url,
                      headers: kIsWeb ? null : widget.headers,
                    ),
                    width: decodeWidth,
                  ).evict();
                  setState(() => _mirrorIdx = 0);
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Pág. ${widget.pageIndex + 1} • Tentar novamente',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        );
      },
    );
  }
}
