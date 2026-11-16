import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/comment_models.dart';
import '../models/manga_models.dart';
import '../services/download_manager.dart';
import '../services/mangadex_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/comments_section_widget.dart';
import '../widgets/manga_detail_sections.dart';
import '../widgets/yomi_blobatar_studio.dart';
import 'home_tabs.dart';
import 'reader_screen.dart';

class MangaDetailScreen extends StatefulWidget {
  final Manga manga;
  final String heroTag;
  final Future<Map<MangaSourceType, List<Chapter>>> Function(
    Manga manga, {
    int offset,
  })?
  sourceDiscoveryLoader;
  final Future<String?> Function(String text)? synopsisTranslator;

  const MangaDetailScreen({
    super.key,
    required this.manga,
    required this.heroTag,
    this.sourceDiscoveryLoader,
    this.synopsisTranslator,
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
  bool _chapterLoadError = false;
  bool _loadingOlderChapters = false;
  bool _canLoadOlderChapters = false;
  int _nextChapterOffset = 500;
  String _selectedLang = 'TODOS';
  bool _sortAscending = false;
  String? _batchDownloadError;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _initForCurrentManga();
  }

  @override
  void didUpdateWidget(covariant MangaDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manga.compositeId != widget.manga.compositeId) {
      _invalidateChapterFilterMemo();
      _initForCurrentManga();
    }
  }

  void _invalidateChapterFilterMemo() {
    _memoChapters = null;
    _memoSource = null;
    _memoSelectedSource = null;
    _memoLanguage = null;
    _memoAscending = null;
  }

  void _initForCurrentManga() {
    _chaptersBySource = {};
    _recommendedMostCompleteSource = null;
    _loadingChapters = true;
    _chapterLoadError = false;
    _loadingOlderChapters = false;
    _canLoadOlderChapters = false;
    _nextChapterOffset = 500;
    _selectedLang = 'TODOS';
    _sortAscending = false;
    _batchDownloadError = null;

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
    final targetId = widget.manga.compositeId;
    final extracted = await ProfilePaletteService.resolveForManga(widget.manga);
    if (mounted &&
        widget.manga.compositeId == targetId &&
        extracted != _mangaPalette) {
      setState(() => _mangaPalette = extracted);
    }
  }

  /// Verifica todas as fontes disponíveis para este título, compara a quantidade de capítulos
  /// e seleciona DE CARA a fonte mais completa (ex: One Piece com mais capítulos),
  /// mantendo também capítulos baixados/em cache caso o aparelho esteja offline.
  Future<void> _discoverAndSelectBestSource() async {
    final epoch = ++_loadEpoch;
    try {
      final loader =
          widget.sourceDiscoveryLoader ??
          MangaDexService.discoverAllSourcesForManga;
      final map = await loader(widget.manga);
      if (!mounted || epoch != _loadEpoch) return;

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
        _chapterLoadError = false;
        _canLoadOlderChapters = MangaDexService.hasOlderChapters(
          widget.manga.id,
        );
      });
    } catch (_) {
      final offlineOrCached = StorageService.getOfflineOrCachedChapters(
        widget.manga.id,
      );
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          _chaptersBySource = {widget.manga.source: offlineOrCached};
          _loadingChapters = false;
          _chapterLoadError = offlineOrCached.isEmpty;
        });
      }
    }
  }

  void _retryLoadChapters() {
    setState(() {
      _loadingChapters = true;
      _chapterLoadError = false;
    });
    _discoverAndSelectBestSource();
  }

  Future<void> _loadOlderChapters() async {
    if (_loadingOlderChapters || !_canLoadOlderChapters) return;
    setState(() => _loadingOlderChapters = true);
    try {
      final loader =
          widget.sourceDiscoveryLoader ??
          MangaDexService.discoverAllSourcesForManga;
      final older = await loader(
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

    setState(() => _batchDownloadError = null);

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
    setState(() {
      _batchDownloadError = count < uniqueToDownload.length
          ? 'Falha ao baixar ${uniqueToDownload.length - count} capítulos.'
          : null;
    });
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
    final selectedUpper = _selectedLang.toUpperCase();
    final filtered = selectedUpper == 'TODOS'
        ? List<Chapter>.from(base)
        : base
              .where((c) => c.language.toUpperCase().contains(selectedUpper))
              .toList();
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
        !_chapterLoadError &&
        _chaptersBySource.values.every((list) => list.isEmpty);
    final availableLanguages =
        _currentSourceChapters.map((c) => c.language).toSet().toList()..sort();
    final palette = _mangaPalette;
    final mediaPadding = MediaQuery.paddingOf(context);
    final horizontalInset = math.max(mediaPadding.left, mediaPadding.right);

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

            return CustomScrollView(
              slivers: [
                ValueListenableBuilder(
                  valueListenable: StorageService.favBox.listenable(
                    keys: [widget.manga.id],
                  ),
                  builder: (context, Box favBox, _) {
                    final isFav = StorageService.isFavorite(widget.manga.id);
                    return MangaDetailHeaderSliver(
                      manga: widget.manga,
                      heroTag: widget.heroTag,
                      palette: palette,
                      sourceLabel: _selectedSource.label,
                      hasZeroChaptersEverywhere: hasZeroChaptersEverywhere,
                      showDownloadAction: filteredChapters.isNotEmpty,
                      isFavorite: isFav,
                      onDownloadAll: () =>
                          _confirmAndDownloadEntireManga(filteredChapters),
                      onAddToList: () =>
                          showAddMangaToReadingListSheet(context, widget.manga),
                      onToggleFavorite: () =>
                          StorageService.toggleFavorite(widget.manga),
                    );
                  },
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      YomiDetailSpacing.md + horizontalInset,
                      YomiDetailSpacing.md,
                      YomiDetailSpacing.md + horizontalInset,
                      YomiDetailSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_loadingChapters &&
                            !_chapterLoadError &&
                            _chaptersBySource.isNotEmpty) ...[
                          SmartSourceSelectorCard(
                            chaptersBySource: _chaptersBySource,
                            selectedSource: _selectedSource,
                            recommendedMostCompleteSource:
                                _recommendedMostCompleteSource,
                            palette: palette,
                            onSelectSource: (src) {
                              setState(() {
                                _selectedSource = src;
                                _batchDownloadError = null;
                              });
                            },
                          ),
                          const SizedBox(height: YomiDetailSpacing.md),
                        ],
                        ValueListenableBuilder<
                          Map<String, ({int completed, int total})>
                        >(
                          valueListenable: DownloadManager.activeMangaDownloads,
                          builder: (context, batchMap, _) {
                            return ValueListenableBuilder(
                              valueListenable:
                                  StorageService.downloadsBox.listenable(),
                              builder: (context, Box downloadsBox, _) {
                                final downloadedCount =
                                    StorageService.countDownloadedChaptersForManga(
                                      widget.manga.id,
                                    );
                                final uniqueCount =
                                    DownloadManager.deduplicateForBatchDownload(
                                      filteredChapters,
                                    ).length;
                                return MangaActionButtonsBar(
                                  palette: palette,
                                  lastChapter: lastChapter,
                                  filteredChapters: filteredChapters,
                                  loadingChapters: _loadingChapters,
                                  chapterLoadError: _chapterLoadError,
                                  hasZeroChaptersEverywhere:
                                      hasZeroChaptersEverywhere,
                                  activeBatchDownload: batchMap[widget.manga.id],
                                  batchDownloadError: _batchDownloadError,
                                  downloadedCount: downloadedCount,
                                  uniqueDownloadCount: uniqueCount,
                                  onStartReading: () => _openChapter(
                                    _sortAscending
                                        ? filteredChapters.first
                                        : filteredChapters.last,
                                    filteredChapters,
                                  ),
                                  onContinueLastChapter: () {
                                    if (lastChapter == null) return;
                                    _openChapter(
                                      lastChapter,
                                      filteredChapters.isNotEmpty
                                          ? filteredChapters
                                          : [lastChapter],
                                    );
                                  },
                                  onRetryLoad: _retryLoadChapters,
                                  onDownloadEntireManga: () =>
                                      _confirmAndDownloadEntireManga(
                                        filteredChapters,
                                      ),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: YomiDetailSpacing.md),
                        if (widget.manga.tags.isNotEmpty) ...[
                          MangaGenresWrap(
                            tags: widget.manga.tags,
                            palette: palette,
                          ),
                          const SizedBox(height: YomiDetailSpacing.sm),
                        ],
                        MangaSynopsisSection(
                          manga: widget.manga,
                          palette: palette,
                          synopsisTranslator: widget.synopsisTranslator,
                        ),
                        const SizedBox(height: YomiDetailSpacing.lg),
                        MangaChaptersHeader(
                          chapterCount: filteredChapters.length,
                          sortAscending: _sortAscending,
                          selectedLanguage: _selectedLang,
                          availableLanguages: availableLanguages,
                          palette: palette,
                          onToggleSort: () {
                            setState(() => _sortAscending = !_sortAscending);
                          },
                          onSelectLanguage: (lang) {
                            setState(() {
                              _selectedLang = lang;
                              _batchDownloadError = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loadingChapters)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: YomiDetailSpacing.xxl,
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: palette.primary,
                        ),
                      ),
                    ),
                  )
                else if (filteredChapters.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: YomiDetailSpacing.xl + horizontalInset,
                        vertical: YomiDetailSpacing.xl,
                      ),
                      child: _chapterLoadError
                          ? Column(
                              children: [
                                Icon(
                                  Icons.wifi_off_rounded,
                                  size: 48,
                                  color: palette.secondary.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                                const SizedBox(height: YomiDetailSpacing.sm),
                                const Text(
                                  'Não foi possível carregar os capítulos no momento. Verifique sua conexão e tente novamente.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: YomiDetailSpacing.md),
                                FilledButton.icon(
                                  onPressed: _retryLoadChapters,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: palette.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Tentar novamente'),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                const Icon(
                                  Icons.sentiment_dissatisfied_rounded,
                                  size: 48,
                                  color: Colors.white38,
                                ),
                                const SizedBox(height: YomiDetailSpacing.sm),
                                Text(
                                  hasZeroChaptersEverywhere
                                      ? 'Este título possui apenas a capa registrada e nenhum capítulo disponível nas fontes consultadas.'
                                      : 'Nenhum capítulo neste filtro de idioma. Toque em "Todos" acima para ver todos os capítulos da fonte.',
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
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: YomiDetailSpacing.md + horizontalInset,
                          vertical: YomiDetailSpacing.xxs,
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
                          '${chapter.displayLabel} - ${chapter.title}',
                          maxLines: 2,
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
                      padding: EdgeInsets.fromLTRB(
                        YomiDetailSpacing.md + horizontalInset,
                        YomiDetailSpacing.sm,
                        YomiDetailSpacing.md + horizontalInset,
                        YomiDetailSpacing.md,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.soft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: YomiDetailSpacing.md,
                              vertical: YomiDetailSpacing.sm,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalInset),
                    child: YomiCommentsSection(
                      targetId: widget.manga.id,
                      targetType: CommentTargetType.manga,
                      title: 'Comentários da Obra',
                      palette: palette,
                      lazyLoadUntilExpanded: true,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: mediaPadding.bottom + YomiDetailSpacing.xl,
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
