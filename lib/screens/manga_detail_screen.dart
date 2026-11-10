import 'package:flutter/material.dart';
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
  Map<MangaSourceType, List<Chapter>> _chaptersBySource = {};
  late MangaSourceType _selectedSource;
  MangaSourceType? _recommendedMostCompleteSource;

  bool _loadingChapters = true;
  bool _loadingOlderChapters = false;
  bool _canLoadOlderChapters = false;
  int _nextChapterOffset = 500;
  String _selectedLang = 'TODOS';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.manga.source;
    final savedOffset = StorageService.settingsBox.get(
      'chapter_feed_offset_${widget.manga.id}',
      defaultValue: 500,
    );
    if (savedOffset is int && savedOffset >= 500) {
      _nextChapterOffset = savedOffset;
    }
    final cached = StorageService.getCachedMangaChapters(widget.manga.id);
    if (cached.isNotEmpty) {
      _chaptersBySource = {widget.manga.source: cached};
      _loadingChapters = false;
    }
    // Refresh the cached list without blocking the initial chapter view.
    _discoverAndSelectBestSource();
  }

  /// Verifica todas as fontes disponíveis para este título, compara a quantidade de capítulos
  /// e seleciona DE CARA a fonte mais completa (ex: One Piece com mais capítulos),
  /// permitindo ao usuário alternar manualmente quando quiser!
  Future<void> _discoverAndSelectBestSource() async {
    try {
      final map = await MangaDexService.discoverAllSourcesForManga(widget.manga);
      if (!mounted) return;

      MangaSourceType bestSource = widget.manga.source;
      int maxChapters = -1;

      for (final entry in map.entries) {
        if (entry.value.length > maxChapters) {
          maxChapters = entry.value.length;
          bestSource = entry.key;
        }
      }

      // Network refresh returns the newest feed page. Keep older pages
      // previously fetched and cached, rather than hiding them on reopen.
      final cached = StorageService.getCachedMangaChapters(widget.manga.id);
      final mergedMap = <MangaSourceType, List<Chapter>>{};
      for (final entry in map.entries) {
        final ids = entry.value.map((ch) => ch.id).toSet();
        mergedMap[entry.key] = [
          ...entry.value,
          ...cached.where((ch) => ids.add(ch.id)),
        ];
      }
      setState(() {
        _chaptersBySource = mergedMap;
        _recommendedMostCompleteSource = bestSource;
        _selectedSource = bestSource;
        _loadingChapters = false;
        _canLoadOlderChapters =
            MangaDexService.hasOlderChapters(widget.manga.id);
      });
    } catch (_) {
      final cached = StorageService.getCachedMangaChapters(widget.manga.id);
      if (mounted) {
        setState(() {
          _chaptersBySource = {widget.manga.source: cached};
          _loadingChapters = false;
        });
      }
    }
  }

  Future<void> _loadOlderChapters() async {
    if (_loadingOlderChapters || !_canLoadOlderChapters) return;
    setState(() => _loadingOlderChapters = true);
    try {
      final older = await MangaDexService.discoverAllSourcesForManga(
        widget.manga,
        offset: _nextChapterOffset,
      );
      if (!mounted) return;
      final updated = <MangaSourceType, List<Chapter>>{};
      for (final entry in _chaptersBySource.entries) {
        final seen = entry.value.map((ch) => ch.id).toSet();
        final extra = older[entry.key] ?? older[MangaSourceType.mangadex] ??
            const <Chapter>[];
        updated[entry.key] = [
          ...entry.value,
          ...extra.where((ch) => seen.add(ch.id)),
        ];
      }
      final primary = updated[_selectedSource] ?? const <Chapter>[];
      await StorageService.cacheMangaChapters(widget.manga.id, primary);
      await StorageService.settingsBox.put(
        'chapter_feed_offset_${widget.manga.id}',
        _nextChapterOffset + 500,
      );
      if (!mounted) return;
      setState(() {
        _chaptersBySource = updated;
        _nextChapterOffset += 500;
        _canLoadOlderChapters =
            MangaDexService.hasOlderChapters(widget.manga.id);
        _loadingOlderChapters = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOlderChapters = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível buscar os capítulos antigos. Tente novamente.'),
        ),
      );
    }
  }

  List<Chapter> get _currentSourceChapters =>
      _chaptersBySource[_selectedSource] ?? [];

  List<Chapter>? _memoChapters;
  List<Chapter>? _memoSource;
  MangaSourceType? _memoSelectedSource;
  String? _memoLanguage;
  bool? _memoAscending;

  List<Chapter> _getFilteredAndSortedChapters() {
    final base = _currentSourceChapters;
    if (identical(base, _memoSource) &&
        _memoSelectedSource == _selectedSource &&
        _memoLanguage == _selectedLang &&
        _memoAscending == _sortAscending &&
        _memoChapters != null) {
      return _memoChapters!;
    }
    final filtered = _selectedLang == 'TODOS'
        ? List<Chapter>.from(base)
        : base.where((c) => c.language.contains(_selectedLang)).toList();
    filtered.sort(
      (a, b) => _sortAscending
          ? a.numericChapter.compareTo(b.numericChapter)
          : b.numericChapter.compareTo(a.numericChapter),
    );
    _memoSource = base;
    _memoSelectedSource = _selectedSource;
    _memoLanguage = _selectedLang;
    _memoAscending = _sortAscending;
    _memoChapters = filtered;
    return filtered;
  }

  void _openChapter(Chapter chapter, List<Chapter> currentList) {
    // Opening a chapter is not the same as completing it. ReaderScreen
    // records it under Continue Reading without inflating read statistics.
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
    final bool hasZeroChaptersEverywhere = !_loadingChapters &&
        _chaptersBySource.values.every((list) => list.isEmpty);

    return Scaffold(
      body: ValueListenableBuilder(
        // Rebuild the header when this manga's last chapter changes, not on
        // every page-position write from the reader (which causes scroll jank).
        valueListenable: StorageService.historyBox.listenable(
          keys: ['last_${widget.manga.id}'],
        ),
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
                          backgroundColor: Colors.black.withValues(alpha: 0.45),
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
                      YomiCoverImage(
                        manga: widget.manga,
                        highRes: true,
                      ),
                      // A full-screen backdrop blur is expensive on modest
                      // Android GPUs, especially during chapter-list scroll.
                      // Keep the dark cover overlay without an offscreen blur.
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.66),
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
                                child: ColorFiltered(
                                  colorFilter: hasZeroChaptersEverywhere
                                      ? const ColorFilter.mode(
                                          Colors.grey,
                                          BlendMode.saturation,
                                        )
                                      : const ColorFilter.mode(
                                          Colors.transparent,
                                          BlendMode.multiply,
                                        ),
                                  child: YomiCoverImage(
                                    manga: widget.manga,
                                    highRes: true,
                                    width: 115,
                                    height: 165,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _selectedSource.accentColor
                                              .withValues(alpha: 0.25),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: _selectedSource.accentColor),
                                        ),
                                        child: Text(
                                          _selectedSource.label,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: YomiPalette.pureWhite,
                                          ),
                                        ),
                                      ),
                                      if (hasZeroChaptersEverywhere)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'SÓ CAPA (0 CAPS)',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white70,
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
                      // SELETOR INTELIGENTE DE FONTE (Exibe de cara a mais completa e permite trocar!)
                      if (!_loadingChapters && _chaptersBySource.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: YomiPalette.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: YomiPalette.ensoRed.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 16,
                                    color: YomiPalette.ensoRed,
                                  ),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'Seletor Inteligente de Fonte (Auto-selecionada a mais completa)',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: YomiPalette.sakuraSoft,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _chaptersBySource.entries.map((entry) {
                                    final src = entry.key;
                                    final count = entry.value.length;
                                    final isSelected = src == _selectedSource;
                                    final isBest =
                                        src == _recommendedMostCompleteSource &&
                                            count > 0;

                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        selected: isSelected,
                                        selectedColor:
                                            YomiPalette.ensoRed.withValues(alpha: 0.28),
                                        backgroundColor: YomiPalette.pitchBlack,
                                        side: BorderSide(
                                          color: isSelected
                                              ? YomiPalette.ensoRed
                                              : Colors.white24,
                                        ),
                                        label: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${src.badge}: $count caps',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: Colors.white,
                                              ),
                                            ),
                                            if (isBest) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 1.5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: YomiPalette.ensoRed,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'MAIS COMPLETA',
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        onSelected: (_) {
                                          setState(() => _selectedSource = src);
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (lastChapter == null &&
                          filteredChapters.isNotEmpty) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _openChapter(
                              _sortAscending
                                  ? filteredChapters.first
                                  : filteredChapters.last,
                              filteredChapters,
                            ),
                            icon: const Icon(Icons.menu_book_rounded),
                            label: const Text('Começar a ler'),
                            style: FilledButton.styleFrom(
                              backgroundColor: YomiPalette.ensoRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
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
                                    style: const TextStyle(fontSize: 11, color: YomiPalette.pureWhite),
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
                          color: Colors.white.withValues(alpha: 0.75),
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
              else if (filteredChapters.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.sentiment_dissatisfied_rounded,
                          size: 48,
                          color: Colors.white38,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          hasZeroChaptersEverywhere
                              ? 'Este título possui apenas a capa registrada e nenhum capítulo disponível nas fontes consultadas.'
                              : 'Nenhum capítulo neste filtro de idioma. Toque em "All" acima para ver todos os capítulos da fonte.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
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
                              : Colors.white.withValues(alpha: 0.25),
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
                                Colors.white.withValues(alpha: isRead ? 0.25 : 0.5),
                          ),
                        ),
                        trailing: ChapterDownloadButton(
                          manga: widget.manga,
                          chapter: chapter,
                        ),
                        onTap: () => _openChapter(chapter, filteredChapters),
                        onLongPress: () async {
                          await StorageService.markChapterAsRead(
                            widget.manga,
                            chapter,
                            read: !isRead,
                          );
                          if (mounted) setState(() {});
                        },
                      );
                    },
                    childCount: filteredChapters.length,
                  ),
                ),
              if (!_loadingChapters && _canLoadOlderChapters)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: OutlinedButton.icon(
                      onPressed: _loadingOlderChapters ? null : _loadOlderChapters,
                      icon: _loadingOlderChapters
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: Text(_loadingOlderChapters
                          ? 'Carregando capítulos antigos...'
                          : 'Carregar capítulos anteriores'),
                    ),
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
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await DownloadManager.downloadChapter(
                    manga: manga,
                    chapter: chapter,
                    useDataSaver: StorageService.dataSaverEnabled,
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Erro no download: $e')),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}
