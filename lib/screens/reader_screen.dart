import 'package:flutter/foundation.dart';
import 'dart:io';
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

  late PageController _pageController;
  final ScrollController _webtoonScrollController = ScrollController();

  // Cache em memória da proporção real (altura/largura) de cada página já carregada.
  // Isso garante que se qualquer página precisar de layout ao rolar para cima, a altura seja 100% idêntica, sem pulos!
  final Map<int, double> _pageAspectRatios = {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Expande o cache de imagens na RAM do Flutter (250 MB / 300 páginas)
    // para impedir que páginas anteriores sejam descartadas ao rolar!
    PaintingBinding.instance.imageCache.maximumSizeBytes = 250 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 300;

    _currentPage = StorageService.getSavedPageIndex(widget.chapter.id);
    _pageController = PageController(initialPage: _currentPage);
    _initReaderSource();
  }

  @override
  void dispose() {
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
    StorageService.markChapterAsRead(widget.manga, target, read: true);
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
        _precacheInitialPages();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _precacheInitialPages() {
    final urls = _onlinePagesData?.getUrls(
          useDataSaver: StorageService.dataSaverEnabled,
        ) ??
        [];
    final count = urls.length < 6 ? urls.length : 6;
    for (int i = 0; i < count; i++) {
      if (!mounted) break;
      precacheImage(
        NetworkImage(
          urls[i],
          headers: kIsWeb ? null : widget.manga.customHeaders,
        ),
        context,
      );
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
                          // Mantém 12.000 pixels acima e abaixo vivos na árvore de renderização
                          cacheExtent: 12000,
                          addAutomaticKeepAlives: true,
                          addRepaintBoundaries: true,
                          itemCount: totalPages + 1,
                          itemBuilder: (context, index) {
                            if (index == totalPages) {
                              return _buildEndOfChapterFooter(nextCh, prevCh);
                            }

                            // Pré-carrega as próximas 3 páginas silenciosamente
                            if (!_isOfflineMode && index + 3 < onlineUrls.length) {
                              precacheImage(
                                NetworkImage(
                                  onlineUrls[index + 3],
                                  headers: kIsWeb ? null : widget.manga.customHeaders,
                                ),
                                context,
                              );
                            }

                            return _KeepAlivePageTile(
                              key: ValueKey('page_${widget.chapter.id}_$index'),
                              pageIndex: index,
                              isOffline: _isOfflineMode,
                              localPath: _isOfflineMode ? _localFilePaths[index] : null,
                              imageUrl: !_isOfflineMode ? onlineUrls[index] : null,
                              headers: widget.manga.customHeaders,
                              cachedAspectRatio: _pageAspectRatios[index],
                              onAspectRatioResolved: (ratio) {
                                _pageAspectRatios[index] = ratio;
                              },
                              onPageVisible: () {
                                _currentPage = index;
                                StorageService.saveLastPageIndex(
                                  widget.chapter.id,
                                  index,
                                );
                              },
                            );
                          },
                        )
                      else
                        PhotoViewGallery.builder(
                          pageController: _pageController,
                          itemCount: totalPages,
                          onPageChanged: (index) {
                            setState(() => _currentPage = index);
                            StorageService.saveLastPageIndex(
                              widget.chapter.id,
                              index,
                            );
                          },
                          builder: (context, index) {
                            final ImageProvider provider = _isOfflineMode
                                ? FileImage(File(_localFilePaths[index]))
                                : NetworkImage(
                                    onlineUrls[index],
                                    headers: kIsWeb ? null : widget.manga.customHeaders,
                                  ) as ImageProvider;

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
                                      'Cap. ${widget.chapter.chapterNumber} • $totalPages págs • Keep-Alive Ativo ${_isOfflineMode ? "(OFFLINE)" : ""}',
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

/// Widget de página blindado com [AutomaticKeepAliveClientMixin]:
/// Uma vez que a página é carregada, ela NUNCA é destruída nem recarregada quando você volta 2, 5 ou 30 páginas para trás!
class _KeepAlivePageTile extends StatefulWidget {
  final int pageIndex;
  final bool isOffline;
  final String? localPath;
  final String? imageUrl;
  final Map<String, String> headers;
  final double? cachedAspectRatio;
  final ValueChanged<double> onAspectRatioResolved;
  final VoidCallback onPageVisible;

  const _KeepAlivePageTile({
    super.key,
    required this.pageIndex,
    required this.isOffline,
    this.localPath,
    this.imageUrl,
    required this.headers,
    this.cachedAspectRatio,
    required this.onAspectRatioResolved,
    required this.onPageVisible,
  });

  @override
  State<_KeepAlivePageTile> createState() => _KeepAlivePageTileState();
}

class _KeepAlivePageTileState extends State<_KeepAlivePageTile>
    with AutomaticKeepAliveClientMixin {
  late List<String> _candidates;
  int _mirrorIdx = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _candidates = yomiCandidateImageUrls(widget.imageUrl ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onPageVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
      filterQuality: FilterQuality.medium,
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
              const Icon(Icons.refresh_rounded, color: YomiPalette.ensoRed),
              const SizedBox(height: 6),
              Text(
                'Pág. ${widget.pageIndex + 1}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        );
      },
    );
  }
}
