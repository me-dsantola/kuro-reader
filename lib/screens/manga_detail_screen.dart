import '../widgets/app_feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';
import '../services/download_manager.dart';
import '../services/profile_palette_service.dart';
import '../widgets/yomi_blobatar_studio.dart';
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
  late ProfileAdaptivePalette _mangaPalette;

  bool _loadingChapters = true;
  bool _loadingOlderChapters = false;
  bool _canLoadOlderChapters = false;
  int _nextChapterOffset = 500;
  String _selectedLang = 'TODOS';
  bool _sortAscending = false;

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.manga.source;
    _mangaPalette = ProfilePaletteService.synchronousFallbackForManga(
      widget.manga,
    );
    _resolveCoverPalette();

    final savedOffset = StorageService.settingsBox.get(
      'chapter_feed_offset_${widget.manga.id}',
      defaultValue: 500,
    );
    if (savedOffset is int && savedOffset >= 500) {
      _nextChapterOffset = savedOffset;
    }
    final offlineOrCached = StorageService.getOfflineOrCachedChapters(
      widget.manga.id,
    );
    if (offlineOrCached.isNotEmpty) {
      _chaptersBySource = {widget.manga.source: offlineOrCached};
      _loadingChapters = false;
    }
    // Refresh the cached list without blocking the initial chapter view.
    _discoverAndSelectBestSource();
  }

  Future<void> _resolveCoverPalette() async {
    final extracted = await ProfilePaletteService.resolveForManga(widget.manga);
    if (mounted && extracted != _mangaPalette) {
      setState(() => _mangaPalette = extracted);
    }
  }

  /// Verifica todas as fontes disponíveis para este título, compara a quantidade de capítulos
  /// e seleciona DE CARA a fonte mais completa (ex: One Piece com mais capítulos),
  /// mantendo também capítulos baixados/em cache caso o aparelho esteja offline.
  Future<void> _discoverAndSelectBestSource() async {
    try {
      final map = await MangaDexService.discoverAllSourcesForManga(
        widget.manga,
      );
      if (!mounted) return;

      final offlineOrCached = StorageService.getOfflineOrCachedChapters(
        widget.manga.id,
      );
      final mergedMap = <MangaSourceType, List<Chapter>>{};
      for (final entry in map.entries) {
        final ids = entry.value.map((ch) => ch.id).toSet();
        if (entry.key == widget.manga.source || entry.value.isNotEmpty) {
          mergedMap[entry.key] = [
            ...entry.value,
            if (entry.key == widget.manga.source)
              ...offlineOrCached.where((ch) => ids.add(ch.id)),
          ];
        } else {
          mergedMap[entry.key] = entry.value;
        }
      }
      if (!mergedMap.containsKey(widget.manga.source) &&
          offlineOrCached.isNotEmpty) {
        mergedMap[widget.manga.source] = offlineOrCached;
      }

      MangaSourceType bestSource = widget.manga.source;
      int maxChapters = -1;

      for (final entry in mergedMap.entries) {
        if (entry.value.length > maxChapters) {
          maxChapters = entry.value.length;
          bestSource = entry.key;
        }
      }

      setState(() {
        _chaptersBySource = mergedMap;
        _recommendedMostCompleteSource = bestSource;
        _selectedSource = bestSource;
        _loadingChapters = false;
        _canLoadOlderChapters = MangaDexService.hasOlderChapters(
          widget.manga.id,
        );
      });
    } catch (_) {
      final offlineOrCached = StorageService.getOfflineOrCachedChapters(
        widget.manga.id,
      );
      if (mounted) {
        setState(() {
          _chaptersBySource = {widget.manga.source: offlineOrCached};
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
        final extra =
            older[entry.key] ??
            older[MangaSourceType.mangadex] ??
            const <Chapter>[];
        updated[entry.key] = [
          ...entry.value,
          ...extra.where((ch) => seen.add(ch.id)),
        ];
      }
      final primary = updated[_selectedSource] ?? const <Chapter>[];
      await StorageService.cacheMangaChapters(
        widget.manga.id,
        primary,
        titleKey: widget.manga.normalizedTitleKey,
      );
      await StorageService.settingsBox.put(
        'chapter_feed_offset_${widget.manga.id}',
        _nextChapterOffset + 500,
      );
      if (!mounted) return;
      setState(() {
        _chaptersBySource = updated;
        _nextChapterOffset += 500;
        _canLoadOlderChapters = MangaDexService.hasOlderChapters(
          widget.manga.id,
        );
        _loadingOlderChapters = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOlderChapters = false);
      AppFeedback.show(
        context,
        const SnackBar(
          content: Text(
            'Não foi possível buscar os capítulos antigos. Tente novamente.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmAndDownloadEntireManga(List<Chapter> chapters) async {
    final uniqueToDownload = DownloadManager.deduplicateForBatchDownload(
      chapters,
    );
    if (uniqueToDownload.isEmpty) return;

    final palette = _mangaPalette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.primary.withValues(alpha: 0.35)),
        ),
        title: Row(
          children: [
            Icon(Icons.downloading_rounded, color: palette.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Baixar obra inteira?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Deseja baixar todos os ${uniqueToDownload.length} capítulos de "${widget.manga.title}" para ler offline?\n\n'
          'A obra será adicionada automaticamente à sua Biblioteca e ficará acessível mesmo sem internet.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: palette.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('Baixar (${uniqueToDownload.length} caps)'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    AppFeedback.show(
      context,
      SnackBar(
        content: Text(
          '"${widget.manga.title}" adicionado à Biblioteca. Iniciando download de ${uniqueToDownload.length} capítulos...',
        ),
      ),
    );

    final count = await DownloadManager.downloadManga(
      manga: widget.manga,
      chapters: uniqueToDownload,
      useDataSaver: StorageService.dataSaverEnabled,
    );

    if (!mounted) return;
    AppFeedback.show(
      context,
      SnackBar(
        content: Text(
          'Download concluído: $count de ${uniqueToDownload.length} capítulos salvos offline na sua Biblioteca!',
        ),
      ),
    );
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
    final bool hasZeroChaptersEverywhere =
        !_loadingChapters &&
        _chaptersBySource.values.every((list) => list.isEmpty);
    final palette = _mangaPalette;

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.dark(
          primary: palette.primary,
          onPrimary: YomiPalette.pureWhite,
          secondary: palette.secondary,
          surface: palette.surface,
          onSurface: YomiPalette.pureWhite,
        ),
      ),
      child: Scaffold(
        backgroundColor: YomiPalette.pitchBlack,
        body: ValueListenableBuilder(
          // Rebuild the header when this manga's last chapter changes, not on
          // every page-position write from the reader (which causes scroll jank).
          valueListenable: StorageService.historyBox.listenable(
            keys: ['last_${widget.manga.id}'],
          ),
          builder: (context, Box historyBox, _) {
            final lastChapter = StorageService.getLastReadChapter(
              widget.manga.id,
            );

            Widget coverThumb = YomiCoverImage(
              manga: widget.manga,
              highRes: true,
              width: 115,
              height: 165,
            );
            if (hasZeroChaptersEverywhere) {
              coverThumb = ColorFiltered(
                colorFilter: _grayscaleFilter,
                child: coverThumb,
              );
            }

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  backgroundColor: palette.bannerDark,
                  actions: [
                    if (filteredChapters.isNotEmpty)
                      IconButton(
                        tooltip: 'Baixar mangá inteiro para ler offline',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.45),
                        ),
                        icon: Icon(
                          Icons.downloading_rounded,
                          color: palette.secondary,
                        ),
                        onPressed: () =>
                            _confirmAndDownloadEntireManga(filteredChapters),
                      ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Adicionar à lista de leitura',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.45),
                      ),
                      icon: const Icon(
                        Icons.playlist_add_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () =>
                          showAddMangaToReadingListSheet(context, widget.manga),
                    ),
                    const SizedBox(width: 6),
                    ValueListenableBuilder(
                      valueListenable: StorageService.favBox.listenable(
                        keys: [widget.manga.id],
                      ),
                      builder: (context, Box favBox, _) {
                        final isFav = StorageService.isFavorite(
                          widget.manga.id,
                        );
                        return IconButton(
                          tooltip: isFav
                              ? 'Remover dos favoritos'
                              : 'Adicionar aos favoritos',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.45,
                            ),
                          ),
                          icon: Icon(
                            isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFav ? palette.primary : Colors.white,
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
                        YomiCoverImage(manga: widget.manga, highRes: true),
                        ColoredBox(
                          color: palette.bannerDark.withValues(alpha: 0.68),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                YomiPalette.pitchBlack,
                                palette.bannerDark.withValues(alpha: 0.45),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.55, 1.0],
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
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: palette.primary.withValues(
                                        alpha: 0.45,
                                      ),
                                      width: 1.4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: palette.primary.withValues(
                                          alpha: 0.28,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: coverThumb,
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
                                            color: palette.primary.withValues(
                                              alpha: 0.24,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: palette.primary,
                                            ),
                                          ),
                                          child: Text(
                                            _selectedSource.label,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: palette.soft,
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
                                              '0 CAPÍTULOS',
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
                        if (!_loadingChapters &&
                            _chaptersBySource.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: palette.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: palette.primary.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 16,
                                      color: palette.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Seletor Inteligente de Fonte (Auto-selecionada a mais completa)',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: palette.soft,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _chaptersBySource.entries.map((
                                      entry,
                                    ) {
                                      final src = entry.key;
                                      final count = entry.value.length;
                                      final isSelected = src == _selectedSource;
                                      final isBest =
                                          src ==
                                              _recommendedMostCompleteSource &&
                                          count > 0;

                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          selected: isSelected,
                                          selectedColor: palette.primary
                                              .withValues(alpha: 0.28),
                                          backgroundColor:
                                              YomiPalette.pitchBlack,
                                          side: BorderSide(
                                            color: isSelected
                                                ? palette.primary
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
                                                    color: palette.primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'MAIS COMPLETA',
                                                    style: TextStyle(
                                                      fontSize: 8.5,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          onSelected: (_) {
                                            setState(
                                              () => _selectedSource = src,
                                            );
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
                                backgroundColor: palette.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: palette.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        // Botão para baixar a obra inteira e salvá-la na Biblioteca para leitura offline
                        if (filteredChapters.isNotEmpty) ...[
                          ValueListenableBuilder<
                            Map<String, ({int completed, int total})>
                          >(
                            valueListenable:
                                DownloadManager.activeMangaDownloads,
                            builder: (context, batchMap, _) {
                              final batch = batchMap[widget.manga.id];
                              if (batch != null) {
                                final progress = batch.total > 0
                                    ? batch.completed / batch.total
                                    : 0.0;
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: palette.primary.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: palette.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Baixando obra inteira: ${batch.completed} de ${batch.total} capítulos...',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: palette.soft,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: progress.clamp(0.02, 1.0),
                                          minHeight: 6,
                                          backgroundColor: Colors.white12,
                                          valueColor: AlwaysStoppedAnimation(
                                            palette.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return ValueListenableBuilder(
                                valueListenable: StorageService.downloadsBox
                                    .listenable(),
                                builder: (context, Box downloadsBox, _) {
                                  final downloadedCount =
                                      StorageService.countDownloadedChaptersForManga(
                                        widget.manga.id,
                                      );
                                  final uniqueCount =
                                      DownloadManager.deduplicateForBatchDownload(
                                        filteredChapters,
                                      ).length;
                                  final allDownloaded =
                                      uniqueCount > 0 &&
                                      downloadedCount >= uniqueCount;

                                  return SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: palette.soft,
                                        backgroundColor: palette.surface
                                            .withValues(alpha: 0.75),
                                        side: BorderSide(
                                          color: palette.primary.withValues(
                                            alpha: 0.45,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      onPressed: allDownloaded
                                          ? null
                                          : () =>
                                                _confirmAndDownloadEntireManga(
                                                  filteredChapters,
                                                ),
                                      icon: Icon(
                                        allDownloaded
                                            ? Icons.offline_pin_rounded
                                            : Icons.downloading_rounded,
                                        color: allDownloaded
                                            ? palette.secondary
                                            : palette.primary,
                                      ),
                                      label: Text(
                                        allDownloaded
                                            ? 'Obra inteira baixada na Biblioteca ($downloadedCount caps)'
                                            : downloadedCount > 0
                                            ? 'Baixar mangá inteiro ($downloadedCount/$uniqueCount baixados)'
                                            : 'Baixar mangá inteiro ($uniqueCount caps)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
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
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: palette.soft,
                                      ),
                                    ),
                                    backgroundColor: palette.surface,
                                    side: BorderSide(
                                      color: palette.primary.withValues(
                                        alpha: 0.24,
                                      ),
                                    ),
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
                                color: palette.secondary,
                              ),
                              onPressed: () {
                                setState(
                                  () => _sortAscending = !_sortAscending,
                                );
                              },
                            ),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'TODOS',
                                  label: Text('All'),
                                ),
                                ButtonSegment(
                                  value: 'PT-BR',
                                  label: Text('PT'),
                                ),
                                ButtonSegment(value: 'EN', label: Text('EN')),
                              ],
                              selected: {_selectedLang},
                              style: ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    WidgetStateProperty.resolveWith((states) {
                                      if (states.contains(
                                        WidgetState.selected,
                                      )) {
                                        return palette.primary.withValues(
                                          alpha: 0.32,
                                        );
                                      }
                                      return palette.surface;
                                    }),
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
                  SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: palette.primary),
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
                    delegate: SliverChildBuilderDelegate((context, index) {
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
                              ? palette.primary
                              : Colors.white.withValues(alpha: 0.25),
                          size: 22,
                        ),
                        title: Text(
                          'Cap. ${chapter.chapterNumber} - ${chapter.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.normal
                                : FontWeight.w600,
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
                            color: Colors.white.withValues(
                              alpha: isRead ? 0.25 : 0.5,
                            ),
                          ),
                        ),
                        trailing: ChapterDownloadButton(
                          manga: widget.manga,
                          chapter: chapter,
                          accentColor: palette.primary,
                          doneColor: palette.secondary,
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
                    }, childCount: filteredChapters.length),
                  ),
                if (!_loadingChapters && _canLoadOlderChapters)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.soft,
                          side: BorderSide(
                            color: palette.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        onPressed: _loadingOlderChapters
                            ? null
                            : _loadOlderChapters,
                        icon: _loadingOlderChapters
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.primary,
                                ),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(
                          _loadingOlderChapters
                              ? 'Carregando capítulos antigos...'
                              : 'Carregar capítulos anteriores',
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ChapterDownloadButton extends StatelessWidget {
  final Manga manga;
  final Chapter chapter;
  final Color accentColor;
  final Color doneColor;

  const ChapterDownloadButton({
    super.key,
    required this.manga,
    required this.chapter,
    this.accentColor = YomiPalette.ensoRed,
    this.doneColor = YomiPalette.sakuraPink,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: StorageService.downloadsBox.listenable(
        keys: [chapter.id],
      ),
      builder: (context, Box box, _) {
        final isDownloaded = StorageService.isChapterDownloaded(chapter.id);

        if (isDownloaded) {
          return IconButton(
            tooltip: 'Baixado (Toque para remover)',
            icon: Icon(Icons.download_done_rounded, color: doneColor),
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
                        color: accentColor,
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
                    useDataSaver: StorageService.dataSaverEnabled,
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  AppFeedback.show(
                    context,
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
