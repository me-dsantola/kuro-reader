import 'dart:async';
import 'package:flutter/material.dart';
import '../models/catalog_sort.dart';
import '../models/manga_models.dart';
import '../services/appearance_controller.dart';
import '../services/catalog_request_state.dart';
import '../services/mangadex_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/catalog_sort_control.dart';
import '../widgets/frosted_surface.dart';
import '../widgets/yomi_brand_widgets.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  void _scheduleTitleSearch(String value) {
    _catalogRequests.beginSearch();
    MangaDexService.resetAggregator();
    setState(() {
      _mangas = [];
      _isLoading = true;
      _isEnrichingCatalog = false;
      _error = null;
    });
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _loadMangas(reset: true);
    });
  }

  List<Manga> _mangas = [];
  bool _isLoading = true;
  final _catalogRequests = CatalogRequestState();
  bool get _isLoadingMore => _catalogRequests.isLoadingMore;
  bool _isEnrichingCatalog = false;
  String? _error;
  int get _catalogRequestGeneration => _catalogRequests.generation;

  CatalogSort _catalogSort = CatalogSort.latest;
  final Set<CanonicalTag> _includedTags = {};
  final Set<CanonicalTag> _excludedTags = {};
  final Set<MangaSourceType> _enabledSources = {
    MangaSourceType.mangadex,
    MangaSourceType.anilist,
    MangaSourceType.jikanMal,
    MangaSourceType.comick,
    MangaSourceType.comicsHq,
    MangaSourceType.adultSource,
  };

  @override
  void initState() {
    super.initState();
    _loadMangas(reset: true);
    _scrollController.addListener(_onScroll);
    StorageService.nsfwModeNotifier.addListener(_onNsfwModeChanged);
  }

  @override
  void dispose() {
    StorageService.nsfwModeNotifier.removeListener(_onNsfwModeChanged);
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onNsfwModeChanged() {
    if (!StorageService.nsfwMode.allowNsfwFetch) {
      _includedTags.removeWhere((t) => t.isNsfwOnly);
      _excludedTags.removeWhere((t) => t.isNsfwOnly);
    }
    _loadMangas(reset: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 450 &&
        !_isLoading &&
        !_isLoadingMore &&
        !_isEnrichingCatalog) {
      _loadMoreMangas();
    }
  }

  YomiSearchFilter get _currentFilter => YomiSearchFilter(
    query: _searchController.text.trim(),
    includedTags: Set.of(_includedTags),
    excludedTags: Set.of(_excludedTags),
    enabledSources: Set.of(_enabledSources),
    allowNsfw: StorageService.nsfwMode.allowNsfwFetch,
    sort: _catalogSort,
    hideZeroChapters: StorageService.hideZeroChapterTitles,
  );

  Future<void> _loadMangas({bool reset = true}) async {
    final generation = _catalogRequests.beginSearch();
    setState(() {
      _isLoading = true;
      _isEnrichingCatalog = false;
      _error = null;
    });
    if (reset && _scrollController.hasClients) _scrollController.jumpTo(0);
    try {
      final filter = _currentFilter;
      final fastSearch =
          reset &&
          filter.query.trim().isNotEmpty &&
          filter.enabledSources.contains(MangaSourceType.mangadex);
      final primaryFilter = fastSearch
          ? YomiSearchFilter(
              query: filter.query,
              includedTags: filter.includedTags,
              excludedTags: filter.excludedTags,
              enabledSources: {MangaSourceType.mangadex},
              allowNsfw: filter.allowNsfw,
              sort: filter.sort,
              hideZeroChapters: filter.hideZeroChapters,
            )
          : filter;
      final result = await MangaDexService.fetchMergedCatalog(
        filter: primaryFilter,
        reset: reset,
      );
      if (mounted && generation == _catalogRequestGeneration) {
        setState(() {
          _mangas = result;
          _isLoading = false;
        });
      }
      // Show real readable MangaDex matches immediately, then enrich with
      // secondary catalogs. Never make the first result wait for all APIs.
      if (fastSearch && mounted && generation == _catalogRequestGeneration) {
        final secondary = filter.enabledSources.difference({
          MangaSourceType.mangadex,
        });
        if (secondary.isNotEmpty) {
          setState(() => _isEnrichingCatalog = true);
          try {
            final extra = await MangaDexService.fetchMergedCatalog(
              filter: YomiSearchFilter(
                query: filter.query,
                includedTags: filter.includedTags,
                excludedTags: filter.excludedTags,
                enabledSources: secondary,
                allowNsfw: filter.allowNsfw,
                sort: filter.sort,
                hideZeroChapters: filter.hideZeroChapters,
              ),
            );
            if (mounted && generation == _catalogRequestGeneration) {
              setState(() {
                final seenIds = _mangas.map((m) => m.compositeId).toSet();
                final readableTitles = _mangas
                    .where((m) => m.source == MangaSourceType.mangadex)
                    .map((m) => m.normalizedTitleKey)
                    .where((key) => key.length >= 3)
                    .toSet();
                _mangas.addAll(
                  extra.where((m) {
                    if (!seenIds.add(m.compositeId)) return false;
                    // Don't show a metadata-only duplicate beneath an already
                    // readable MangaDex result for the same normalized title.
                    return m.normalizedTitleKey.length < 3 ||
                        !readableTitles.contains(m.normalizedTitleKey);
                  }),
                );
              });
            }
          } finally {
            if (mounted && generation == _catalogRequestGeneration) {
              setState(() => _isEnrichingCatalog = false);
            }
          }
        }
      }
      if (mounted &&
          generation == _catalogRequestGeneration &&
          _mangas.isEmpty &&
          MangaDexService.sourceStatusBanner.value != null) {
        setState(() => _error = MangaDexService.sourceStatusBanner.value);
      }
    } catch (e) {
      if (mounted && generation == _catalogRequestGeneration) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreMangas() async {
    if (_isLoading || _isLoadingMore || _isEnrichingCatalog) return;
    final generation = _catalogRequests.beginNextPage();
    if (generation == null) return;
    setState(() {});
    try {
      final result = await MangaDexService.fetchMergedCatalog(
        filter: _currentFilter,
        reset: false,
      );
      if (mounted &&
          generation == _catalogRequestGeneration &&
          result.isNotEmpty) {
        setState(() {
          final existingIds = _mangas.map((m) => m.compositeId).toSet();
          _mangas.addAll(result.where((m) => existingIds.add(m.compositeId)));
        });
      }
    } catch (_) {
      // Keep the current catalog visible if a later page fails.
    } finally {
      if (mounted && generation == _catalogRequestGeneration) {
        setState(() => _catalogRequests.finishNextPage(generation));
      }
    }
  }

  void _openTagFilterModal(ProfileAdaptivePalette palette) {
    // Edits remain local until Apply. Dismissing the sheet cancels the draft.
    final draftIncluded = Set<CanonicalTag>.of(_includedTags);
    final draftExcluded = Set<CanonicalTag>.of(_excludedTags);
    final draftSources = Set<MangaSourceType>.of(_enabledSources);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => ValueListenableBuilder<NsfwDisplayMode>(
        valueListenable: StorageService.nsfwModeNotifier,
        builder: (context, mode, _) => StatefulBuilder(
          builder: (context, setModalState) {
            final visibleSources = MangaSourceType.values
                .where(
                  (source) =>
                      mode.allowNsfwFetch ||
                      source != MangaSourceType.adultSource,
                )
                .toList();
            final groups = TagCategoryGroup.values.where(
              (group) =>
                  mode.allowNsfwFetch || group != TagCategoryGroup.nsfwVault,
            );
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              maxChildSize: 0.94,
              minChildSize: 0.5,
              builder: (context, scrollController) => SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filtrar catálogo',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setModalState(() {
                              draftIncluded.clear();
                              draftExcluded.clear();
                              draftSources
                                ..clear()
                                ..addAll(MangaSourceType.values);
                            }),
                            child: Text(
                              'Limpar filtros',
                              style: TextStyle(color: palette.secondary),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Toque para incluir, novamente para excluir e uma terceira vez para limpar a tag.',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            ExpansionTile(
                              key: const PageStorageKey('catalog-sources'),
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(
                                bottom: 12,
                              ),
                              shape: const Border(),
                              collapsedShape: const Border(),
                              title: Text(
                                'Fontes de catálogo',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: palette.soft,
                                ),
                              ),
                              subtitle: Text(
                                '${visibleSources.where(draftSources.contains).length} de ${visibleSources.length} ativas',
                                style: const TextStyle(fontSize: 12),
                              ),
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final source in visibleSources)
                                      Tooltip(
                                        message:
                                            'Mantenha ao menos uma fonte ativa',
                                        child: FilterChip(
                                          selected: draftSources.contains(
                                            source,
                                          ),
                                          backgroundColor:
                                              YomiPalette.pitchBlack,
                                          selectedColor: palette.primary
                                              .withValues(alpha: 0.28),
                                          side: BorderSide(
                                            color: draftSources.contains(source)
                                                ? palette.primary
                                                : Colors.white24,
                                          ),
                                          labelStyle: const TextStyle(
                                            color: YomiPalette.pureWhite,
                                          ),
                                          checkmarkColor: YomiPalette.pureWhite,
                                          label: Text(
                                            '${source.badge} • ${source.label}',
                                          ),
                                          onSelected: (enabled) =>
                                              setModalState(() {
                                                if (enabled) {
                                                  draftSources.add(source);
                                                } else if (visibleSources
                                                        .where(
                                                          draftSources.contains,
                                                        )
                                                        .length >
                                                    1) {
                                                  draftSources.remove(source);
                                                }
                                              }),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            for (final group in groups)
                              ExpansionTile(
                                key: PageStorageKey(
                                  'catalog-tags-${group.name}',
                                ),
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: const EdgeInsets.only(
                                  bottom: 12,
                                ),
                                shape: const Border(),
                                collapsedShape: const Border(),
                                initiallyExpanded:
                                    group == TagCategoryGroup.genres,
                                title: Text(
                                  group.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: palette.soft,
                                  ),
                                ),
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final tag
                                          in CanonicalTag.values.where(
                                            (tag) =>
                                                tag.group == group &&
                                                (mode.allowNsfwFetch ||
                                                    !tag.isNsfwOnly),
                                          ))
                                        _filterTag(
                                          tag: tag,
                                          included: draftIncluded.contains(tag),
                                          excluded: draftExcluded.contains(tag),
                                          palette: palette,
                                          onTap: () => setModalState(() {
                                            if (draftIncluded.remove(tag)) {
                                              draftExcluded.add(tag);
                                            } else if (!draftExcluded.remove(
                                              tag,
                                            )) {
                                              draftIncluded.add(tag);
                                            }
                                          }),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            if (!mounted) return;
                            if (!StorageService.nsfwMode.allowNsfwFetch) {
                              draftIncluded.removeWhere(
                                (tag) => tag.isNsfwOnly,
                              );
                              draftExcluded.removeWhere(
                                (tag) => tag.isNsfwOnly,
                              );
                            }
                            setState(() {
                              _includedTags
                                ..clear()
                                ..addAll(draftIncluded);
                              _excludedTags
                                ..clear()
                                ..addAll(draftExcluded);
                              _enabledSources
                                ..clear()
                                ..addAll(draftSources);
                            });
                            Navigator.pop(sheetContext);
                            _loadMangas(reset: true);
                          },
                          icon: const Icon(Icons.done_all_rounded),
                          label: const Text('Aplicar filtros'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _filterTag({
    required CanonicalTag tag,
    required bool included,
    required bool excluded,
    required ProfileAdaptivePalette palette,
    required VoidCallback onTap,
  }) {
    final accent = excluded ? palette.secondary : palette.primary;
    final active = included || excluded;
    return Semantics(
      button: true,
      selected: active,
      label:
          '${tag.label}: ${included
              ? "incluída"
              : excluded
              ? "excluída"
              : "sem filtro"}',
      child: Material(
        color: active ? accent.withValues(alpha: 0.2) : YomiPalette.pitchBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: active ? accent : Colors.white24),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active) ...[
                  Icon(
                    excluded
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    tag.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: excluded
                          ? palette.secondary
                          : YomiPalette.pureWhite,
                      decoration: excluded ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayed = List<Manga>.of(_mangas);
    if (_catalogSort == CatalogSort.title) {
      displayed.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    }
    const catalogControlsHeight = 112.0;

    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        final catalogAppBar = AppBar(
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            child: YomiEnsoLogo(fontSize: 24),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          flexibleSpace: const FrostedSurface(child: SizedBox.expand()),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(catalogControlsHeight),
            child: SizedBox(
              height: catalogControlsHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onChanged: _scheduleTitleSearch,
                            onSubmitted: (_) {
                              _searchDebounce?.cancel();
                              _loadMangas(reset: true);
                            },
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText:
                                  'Buscar obras (One Piece, Solo Leveling, Batman...)',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: palette.primary,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        color: Colors.white54,
                                      ),
                                      onPressed: () {
                                        _searchDebounce?.cancel();
                                        _searchController.clear();
                                        _loadMangas(reset: true);
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: palette.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 0,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: palette.primary.withValues(
                                    alpha: 0.22,
                                  ),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: palette.primary.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: palette.primary,
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Badge(
                          isLabelVisible:
                              _includedTags.isNotEmpty ||
                              _excludedTags.isNotEmpty,
                          label: Text(
                            '${_includedTags.length + _excludedTags.length}',
                          ),
                          backgroundColor: palette.primary,
                          child: IconButton.filledTonal(
                            tooltip: 'Filtros de catálogo',
                            style: IconButton.styleFrom(
                              backgroundColor: palette.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: palette.primary.withValues(
                                    alpha: 0.22,
                                  ),
                                ),
                              ),
                            ),
                            onPressed: () => _openTagFilterModal(palette),
                            icon: Icon(
                              Icons.tune_rounded,
                              color: palette.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Ordenar por',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        CatalogSortControl(
                          value: _catalogSort,
                          onChanged: (sort) {
                            if (sort == _catalogSort) return;
                            _searchDebounce?.cancel();
                            setState(() => _catalogSort = sort);
                            _loadMangas(reset: true);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        return ValueListenableBuilder<AppearancePreferences>(
          valueListenable: AppearanceController.instance,
          builder: (context, appearance, _) => Scaffold(
            backgroundColor: YomiPalette.pitchBlack,
            body: RefreshIndicator(
              color: palette.primary,
              onRefresh: () => _loadMangas(reset: true),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    key: const ValueKey('catalog-scroll-header'),
                    title: catalogAppBar.title,
                    centerTitle: true,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    scrolledUnderElevation: 0,
                    flexibleSpace: catalogAppBar.flexibleSpace,
                    bottom: catalogAppBar.bottom,
                    floating: AppearanceController.instance.value.autoHideMenus,
                    pinned: !AppearanceController.instance.value.autoHideMenus,
                    snap:
                        AppearanceController.instance.value.autoHideMenus &&
                        !MediaQuery.disableAnimationsOf(context),
                  ),
                  if (_isLoading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: palette.primary,
                        ),
                      ),
                    )
                  else if (_error != null && _mangas.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 48,
                                color: palette.primary,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Não foi possível consultar os catálogos. Tente novamente ou leia em Biblioteca → Baixados.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: palette.primary,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _loadMangas(reset: true),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Tentar novamente'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (_mangas.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _isEnrichingCatalog
                                ? 'Buscando em outras fontes…'
                                : 'Nenhuma obra encontrada. Tente outro título ou revise os filtros.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.soft),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.62,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 16,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => MangaGridCard(
                            manga: displayed[index],
                            heroPrefix: 'explore',
                          ),
                          childCount: displayed.length,
                        ),
                      ),
                    ),
                    if (_isLoadingMore)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: palette.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

