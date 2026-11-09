import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';
import '../services/download_manager.dart';
import 'home_tabs.dart';
import 'reader_screen.dart';

class MangaDetailScreen extends StatefulWidget {
  final Manga manga;
  final String heroTag;

  const MangaDetailScreen({
    super.key,
    required this.manga,
    required this.heroTag,
  });

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  List<Chapter> _chapters = [];
  bool _loadingChapters = true;
  String _selectedLang = 'TODOS';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    try {
      final ch = await MangaDexService.fetchChapters(widget.manga);
      if (mounted) {
        setState(() {
          _chapters = ch;
          _loadingChapters = false;
        });
      }
    } catch (_) {
      final cached = StorageService.getCachedMangaChapters(widget.manga.id);
      if (mounted) {
        setState(() {
          _chapters = cached;
          _loadingChapters = false;
        });
      }
    }
  }

  List<Chapter> _getFilteredAndSortedChapters() {
    final filtered = _selectedLang == 'TODOS'
        ? List<Chapter>.from(_chapters)
        : _chapters.where((c) => c.language == _selectedLang).toList();

    filtered.sort(
      (a, b) => _sortAscending
          ? a.numericChapter.compareTo(b.numericChapter)
          : b.numericChapter.compareTo(a.numericChapter),
    );
    return filtered;
  }

  void _openChapter(Chapter chapter, List<Chapter> currentList) {
    StorageService.markChapterAsRead(widget.manga.id, chapter, read: true);
    final orderedAsc = List<Chapter>.from(currentList)
      ..sort((a, b) => a.numericChapter.compareTo(b.numericChapter));

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          manga: widget.manga,
          chapter: chapter,
          allChapters: orderedAsc,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredChapters = _getFilteredAndSortedChapters();

    return Scaffold(
      body: ValueListenableBuilder(
        valueListenable: StorageService.historyBox.listenable(),
        builder: (context, Box historyBox, _) {
          final lastChapter =
              StorageService.getLastReadChapter(widget.manga.id);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                actions: [
                  ValueListenableBuilder(
                    valueListenable: StorageService.favBox
                        .listenable(keys: [widget.manga.id]),
                    builder: (context, Box favBox, _) {
                      final isFav = StorageService.isFavorite(widget.manga.id);
                      return IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withOpacity(0.45),
                        ),
                        icon: Icon(
                          isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFav ? YomiPalette.ensoRed : Colors.white,
                        ),
                        onPressed: () =>
                            StorageService.toggleFavorite(widget.manga),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: widget.manga.getCoverUrl(highRes: true),
                        httpHeaders: widget.manga.customHeaders,
                        fit: BoxFit.cover,
                      ),
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(color: Colors.black.withOpacity(0.58)),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [YomiPalette.pitchBlack, Colors.transparent],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Hero(
                              tag: widget.heroTag,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl:
                                      widget.manga.getCoverUrl(highRes: true),
                                  httpHeaders: widget.manga.customHeaders,
                                  width: 115,
                                  height: 165,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: YomiPalette.ensoRed
                                              .withOpacity(0.25),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: YomiPalette.ensoRed),
                                        ),
                                        child: Text(
                                          widget.manga.source.label,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: YomiPalette.sakuraSoft,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (widget.manga.isNsfw)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: YomiPalette.sakuraPink,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            '18+',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.manga.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (lastChapter != null) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                _openChapter(lastChapter, filteredChapters),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              'Continuar Cap. ${lastChapter.chapterNumber} (${lastChapter.language})',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: YomiPalette.ensoRed,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (widget.manga.tags.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.manga.tags
                              .map(
                                (t) => Chip(
                                  label: Text(
                                    t,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  backgroundColor: YomiPalette.surface,
                                  side: BorderSide.none,
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        widget.manga.description,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: Colors.white.withOpacity(0.75),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Capítulos (${filteredChapters.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _sortAscending
                                ? 'Ordenando: Cap. 1 → Recente'
                                : 'Ordenando: Recente → Cap. 1',
                            icon: Icon(
                              _sortAscending
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              color: YomiPalette.sakuraPink,
                            ),
                            onPressed: () {
                              setState(() => _sortAscending = !_sortAscending);
                            },
                          ),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'TODOS', label: Text('All')),
                              ButtonSegment(value: 'PT-BR', label: Text('PT')),
                              ButtonSegment(value: 'EN', label: Text('EN')),
                            ],
                            selected: {_selectedLang},
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                            onSelectionChanged: (val) {
                              setState(() => _selectedLang = val.first);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_loadingChapters)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: YomiPalette.ensoRed),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final chapter = filteredChapters[index];
                      final isRead = StorageService.isChapterRead(chapter.id);

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: Icon(
                          isRead
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isRead
                              ? YomiPalette.ensoRed
                              : Colors.white.withOpacity(0.25),
                          size: 22,
                        ),
                        title: Text(
                          'Cap. ${chapter.chapterNumber} - ${chapter.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isRead ? FontWeight.normal : FontWeight.w600,
                            fontSize: 14,
                            color: isRead ? Colors.white38 : Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          '${chapter.language} • ${chapter.scanlator} • ${chapter.pages}p',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color:
                                Colors.white.withOpacity(isRead ? 0.25 : 0.5),
                          ),
                        ),
                        trailing: ChapterDownloadButton(
                          manga: widget.manga,
                          chapter: chapter,
                        ),
                        onTap: () => _openChapter(chapter, filteredChapters),
                        onLongPress: () {
                          StorageService.markChapterAsRead(
                            widget.manga.id,
                            chapter,
                            read: !isRead,
                          );
                        },
                      );
                    },
                    childCount: filteredChapters.length,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ChapterDownloadButton extends StatelessWidget {
  final Manga manga;
  final Chapter chapter;

  const ChapterDownloadButton({
    super.key,
    required this.manga,
    required this.chapter,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable:
          StorageService.downloadsBox.listenable(keys: [chapter.id]),
      builder: (context, Box box, _) {
        final isDownloaded = StorageService.isChapterDownloaded(chapter.id);

        if (isDownloaded) {
          return IconButton(
            tooltip: 'Baixado (Toque para remover)',
            icon: const Icon(
              Icons.download_done_rounded,
              color: YomiPalette.sakuraPink,
            ),
            onPressed: () => DownloadManager.deleteChapter(chapter.id),
          );
        }

        return ValueListenableBuilder<Map<String, double>>(
          valueListenable: DownloadManager.activeDownloads,
          builder: (context, activeMap, _) {
            final progress = activeMap[chapter.id];

            if (progress != null) {
              return SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.5,
                        color: YomiPalette.ensoRed,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }

            return IconButton(
              tooltip: 'Baixar para ler offline',
              icon: const Icon(
                Icons.download_for_offline_outlined,
                color: Colors.white54,
              ),
              onPressed: () async {
                try {
                  await DownloadManager.downloadChapter(
                    manga: manga,
                    chapter: chapter,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro no download: $e')),
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
  }
}
