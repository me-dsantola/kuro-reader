import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';

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
  bool _useDataSaver = false;
  bool _showHud = true;
  int _currentPage = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _currentPage = StorageService.getSavedPageIndex(widget.chapter.id);
    _pageController = PageController(initialPage: _currentPage);
    _initReaderSource();
  }

  @override
  void dispose() {
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

  void _goToChapter(Chapter target) {
    StorageService.markChapterAsRead(widget.manga.id, target, read: true);
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
    if (StorageService.isChapterDownloaded(widget.chapter.id)) {
      final localPaths = StorageService.getDownloadedChapterPaths(
        widget.chapter.id,
      );
      if (localPaths.isNotEmpty && await File(localPaths.first).exists()) {
        setState(() {
          _localFilePaths = localPaths;
          _isOfflineMode = true;
          _isLoading = false;
        });
        return;
      }
    }

    try {
      final data = await MangaDexService.fetchChapterPages(widget.chapter.id);
      if (mounted) {
        setState(() {
          _onlinePagesData = data;
          _isOfflineMode = false;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineUrls =
        _onlinePagesData?.getUrls(useDataSaver: _useDataSaver) ?? [];
    final totalPages = _isOfflineMode
        ? _localFilePaths.length
        : onlineUrls.length;
    final nextCh = _nextChapter;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : totalPages == 0
          ? const Center(
              child: Text('Sem conexão e capítulo não salvo offline.'),
            )
          : GestureDetector(
              onTap: () => setState(() => _showHud = !_showHud),
              child: Stack(
                children: [
                  if (_isWebtoonMode)
                    ListView.builder(
                      padding: EdgeInsets.zero,
                      cacheExtent: 2500,
                      itemCount: totalPages + 1,
                      itemBuilder: (context, index) {
                        // Rodapé no final do capítulo para ir direto ao próximo
                        if (index == totalPages) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 48,
                              horizontal: 24,
                            ),
                            color: const Color(0xFF09090E),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 44,
                                  color: Color(0xFFC084FC),
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
                                      label: Text(
                                        'Ler Próximo: Cap. ${nextCh.chapterNumber}',
                                      ),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  const Text(
                                    'Você chegou ao capítulo mais recente!',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                              ],
                            ),
                          );
                        }

                        StorageService.saveLastPageIndex(
                          widget.chapter.id,
                          index,
                        );

                        if (_isOfflineMode) {
                          return Image.file(
                            File(_localFilePaths[index]),
                            fit: BoxFit.fitWidth,
                          );
                        }
                        return CachedNetworkImage(
                          imageUrl: onlineUrls[index],
                          httpHeaders: MangaDexService.headers,
                          fit: BoxFit.fitWidth,
                          placeholder: (context, url) => SizedBox(
                            height: 420,
                            child: Center(
                              child: Text(
                                'Carregando pág. ${index + 1}...',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ),
                          ),
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
                            : CachedNetworkImageProvider(
                                    onlineUrls[index],
                                    headers: MangaDexService.headers,
                                  )
                                  as ImageProvider;

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
                    top: _showHud ? 0 : -110,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 42, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
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
                                  'Cap. ${widget.chapter.chapterNumber} • $totalPages págs ${_isOfflineMode ? "(OFFLINE)" : ""}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFC084FC),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (nextCh != null)
                            IconButton(
                              tooltip: 'Próximo: Cap. ${nextCh.chapterNumber}',
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: () => _goToChapter(nextCh),
                            ),
                          IconButton(
                            tooltip: 'Alternar Webtoon / Paginado',
                            icon: Icon(
                              _isWebtoonMode
                                  ? Icons.view_day_rounded
                                  : Icons.view_carousel_rounded,
                              color: const Color(0xFF8B5CF6),
                            ),
                            onPressed: () {
                              setState(() => _isWebtoonMode = !_isWebtoonMode);
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
}
