import 'dart:async';
import '../widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/favorite_updates_service.dart';
import '../services/mangadex_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/yomi_blobatar_studio.dart';
import '../widgets/home_billboard.dart';
import 'favorite_updates_screen.dart';
import 'home_tabs.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

/// Reading shortcuts share the same covers, artwork and surfaces as the library.
class HomeOverviewScreen extends StatefulWidget {
  final VoidCallback onExplore;
  final VoidCallback onLibrary;
  final VoidCallback? onProfile;
  final Duration featuredInterval;
  final Future<ProfileAdaptivePalette> Function(Manga)? paletteResolver;

  const HomeOverviewScreen({
    super.key,
    required this.onExplore,
    required this.onLibrary,
    this.onProfile,
    this.featuredInterval = const Duration(seconds: 8),
    this.paletteResolver,
  });

  static List<Chapter> buildSortedChapterList(Manga manga, Chapter current) {
    final cached = StorageService.getOfflineOrCachedChapters(manga.id);
    final byNum = <String, Chapter>{};
    for (final c in cached) {
      final key = c.chapterNumber.trim();
      final existing = byNum[key];
      if (existing == null) {
        byNum[key] = c;
      } else if (c.language == current.language &&
          existing.language != current.language) {
        byNum[key] = c;
      } else if (c.language == 'PT-BR' && existing.language != 'PT-BR') {
        byNum[key] = c;
      }
    }
    byNum[current.chapterNumber.trim()] = current;
    final list = byNum.values.toList()
      ..sort((a, b) => a.numericChapter.compareTo(b.numericChapter));
    return list;
  }

  @override
  State<HomeOverviewScreen> createState() => _HomeOverviewScreenState();
}

class _HomeOverviewScreenState extends State<HomeOverviewScreen> {
  List<Manga> _popularMangas = [];
  bool _loadingPopular = false;
  bool _openingFeatured = false;
  int _popularGeneration = 0;
  int _featuredIndex = 0;
  int _paletteGeneration = 0;
  Timer? _featuredTimer;
  ProfileAdaptivePalette? _featuredPalette;

  List<Manga> get _featuredItems => _visiblePopular.take(5).toList();

  void _selectFeatured(int index) {
    final items = _featuredItems;
    if (items.isEmpty) return;
    final selected = index % items.length;
    final manga = items[selected];
    final generation = ++_paletteGeneration;
    final fallback = ProfilePaletteService.synchronousFallbackForManga(manga);
    final profile = ProfilePaletteService.paletteNotifier.value;
    final hue =
        manga.title.runes.fold<int>(
          0,
          (hash, c) => (hash * 31 + c) & 0x7fffffff,
        ) %
        360;
    setState(() {
      _featuredIndex = selected;
      _featuredPalette = identical(fallback, profile)
          ? ProfileAdaptivePalette.fromColor(
              HSVColor.fromAHSV(1, hue.toDouble(), 0.65, 0.85).toColor(),
            )
          : fallback;
    });
    (widget.paletteResolver ?? ProfilePaletteService.resolveForManga)(
      manga,
    ).then((palette) {
      if (mounted &&
          generation == _paletteGeneration &&
          !identical(palette, ProfilePaletteService.paletteNotifier.value)) {
        setState(() => _featuredPalette = palette);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPopularMangas();
    _featuredTimer = Timer.periodic(widget.featuredInterval, (_) {
      if (!mounted ||
          _openingFeatured ||
          _featuredItems.length < 2 ||
          !TickerMode.of(context) ||
          MediaQuery.disableAnimationsOf(context) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      _selectFeatured(_featuredIndex + 1);
    });
    StorageService.nsfwModeNotifier.addListener(_loadPopularMangas);
  }

  @override
  void dispose() {
    _featuredTimer?.cancel();
    StorageService.nsfwModeNotifier.removeListener(_loadPopularMangas);
    super.dispose();
  }

  Future<void> _loadPopularMangas() async {
    final generation = ++_popularGeneration;
    setState(() => _loadingPopular = true);
    try {
      final fetched = await MangaDexService.fetchPopularMangas(
        limit: 12,
        includeNsfw: StorageService.nsfwMode.allowNsfwFetch,
      );
      if (mounted && generation == _popularGeneration) {
        setState(() {
          _popularMangas = fetched;
          _featuredIndex = 0;
        });
        _selectFeatured(0);
      }
    } catch (_) {
      // Keep actual previously fetched titles on temporary failures.
    } finally {
      if (mounted && generation == _popularGeneration) {
        setState(() => _loadingPopular = false);
      }
    }
  }

  void _openChapter(BuildContext context, Manga manga, Chapter chapter) {
    final chapters = HomeOverviewScreen.buildSortedChapterList(manga, chapter);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReaderScreen(manga: manga, chapter: chapter, allChapters: chapters),
      ),
    );
  }

  void _openMangaDetail(BuildContext context, Manga manga, String tagPrefix) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaDetailScreen(
          manga: manga,
          heroTag: '${tagPrefix}_${manga.compositeId}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ProfilePaletteService.paletteNotifier,
      StorageService.profileNotifier,
      StorageService.nsfwModeNotifier,
    ]),
    builder: (context, _) {
      final palette =
          _featuredPalette ?? ProfilePaletteService.paletteNotifier.value;
      final profile = StorageService.profileNotifier.value;

      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const YomiEnsoLogo(),
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: 'Buscar mangás',
              onPressed: widget.onExplore,
              icon: const Icon(Icons.search_rounded, size: 25),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14, left: 4),
              child: Center(
                child: YomiProfileAvatarView(
                  profile: profile,
                  size: 34,
                  borderColor: palette.primary,
                  adaptiveHue: palette.hue,
                  onTap: widget.onProfile ?? widget.onLibrary,
                ),
              ),
            ),
          ],
        ),
        body: ValueListenableBuilder(
          valueListenable: StorageService.historyBox.listenable(
            keys: ['recent_reading_list'],
          ),
          builder: (context, Box box, _) {
            final recent = StorageService.getContinueReadingList()
                .take(12)
                .toList();
            return ValueListenableBuilder(
              valueListenable: StorageService.historyBox.listenable(
                keys: [
                  for (final item in recent)
                    'page_${(item['chapter'] as Chapter).id}',
                ],
              ),
              builder: (context, Box history, _) => SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _featured(context, palette),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _popularSection(context, palette),
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (recent.isNotEmpty) ...[
                            _sectionHeader(
                              title: 'Continue lendo',
                              actionLabel: 'Ver todos',
                              accentColor: palette.secondary,
                              onAction: recent.length > 1
                                  ? () => _showAllRecentSheet(
                                      context,
                                      recent,
                                      palette,
                                    )
                                  : widget.onLibrary,
                            ),
                            const SizedBox(height: 12),
                            _readingCard(
                              context,
                              recent.first,
                              palette: palette,
                              featured: true,
                            ),
                            const SizedBox(height: 24),
                          ],

                          _shortcuts(context, palette),
                          const SizedBox(height: 14),
                          YomiMascotCompanionCard(
                            compact: true,
                            message: recent.isNotEmpty
                                ? 'Continue sua jornada de onde parou!'
                                : 'Escolha uma obra popular para começar!',
                            onTap: widget.onProfile,
                          ),
                          const SizedBox(height: 12),
                          _updates(context, palette),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  void _showAllRecentSheet(
    BuildContext context,
    List<Map<String, dynamic>> recent,
    ProfileAdaptivePalette palette,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: YomiPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Histórico de Leituras Recentes',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: recent.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) =>
                      _readingCard(context, recent[idx], palette: palette),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Manga> get _visiblePopular => _popularMangas
      .where((m) => StorageService.nsfwMode.allowNsfwFetch || !m.isNsfw)
      .toList();

  Future<void> _readFeatured(Manga manga) async {
    if (_openingFeatured) return;
    setState(() => _openingFeatured = true);
    try {
      final saved = StorageService.getLastReadChapter(manga.id);
      if (saved != null) {
        _openChapter(context, manga, saved);
        return;
      }
      final chapters = await MangaDexService.fetchChapters(manga);
      if (!mounted) return;
      if (chapters.isEmpty) {
        _openMangaDetail(context, manga, 'home_featured');
        AppFeedback.show(
          context,
          const SnackBar(
            content: Text('Nenhum capítulo disponível nesta fonte no momento.'),
          ),
        );
        return;
      }
      final sorted = List<Chapter>.from(chapters)
        ..sort((a, b) => a.numericChapter.compareTo(b.numericChapter));
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            manga: manga,
            chapter: sorted.first,
            allChapters: sorted,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        AppFeedback.show(
          context,
          const SnackBar(
            content: Text('Não foi possível abrir a leitura. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingFeatured = false);
    }
  }

  Widget _featured(BuildContext context, ProfileAdaptivePalette palette) {
    final popular = _featuredItems;
    if (popular.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 108, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sua próxima história começa aqui',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Descubra mangás, acompanhe suas leituras e guarde seus favoritos.',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: widget.onExplore,
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Explorar agora'),
            ),
          ],
        ),
      );
    }
    final manga = popular[_featuredIndex % popular.length];
    return ValueListenableBuilder(
      valueListenable: StorageService.favBox.listenable(),
      builder: (context, Box box, _) => Column(
        children: [
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            child: HomeBillboard(
              key: ValueKey(manga.compositeId),
              manga: manga,
              artwork: YomiCoverImage(manga: manga, highRes: true),
              accent: palette.primary,
              inList: StorageService.isFavorite(manga.id),
              opening: _openingFeatured,
              onRead: () => _readFeatured(manga),
              onToggleList: () async {
                try {
                  await StorageService.toggleFavorite(manga);
                } catch (_) {
                  if (context.mounted) {
                    AppFeedback.show(
                      context,
                      const SnackBar(
                        content: Text(
                          'Não foi possível atualizar sua lista. Tente novamente.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ),
          if (popular.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < popular.length; index++)
                  Semantics(
                    button: true,
                    selected: index == _featuredIndex,
                    label: 'Destaque ${index + 1} de ${popular.length}',
                    child: InkWell(
                      onTap: () => _selectFeatured(index),
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        width: 40,
                        height: 36,
                        child: Center(
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            height: 5,
                            width: index == _featuredIndex ? 23 : 6,
                            decoration: BoxDecoration(
                              color: index == _featuredIndex
                                  ? palette.primary
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required String actionLabel,
    required Color accentColor,
    required VoidCallback onAction,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
      ),
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onAction,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                actionLabel,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 16, color: accentColor),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _readingCard(
    BuildContext context,
    Map<String, dynamic> item, {
    required ProfileAdaptivePalette palette,
    bool featured = false,
  }) {
    final manga = item['manga'] as Manga;
    final chapter = item['chapter'] as Chapter;
    final page = StorageService.getSavedPageIndex(chapter.id) + 1;
    final progress = chapter.pages > 0
        ? (page / chapter.pages).clamp(0.0, 1.0)
        : null;
    final percentText = progress != null
        ? '${(progress * 100).round()}%'
        : 'Progresso indisponível';
    void open() => _openChapter(context, manga, chapter);
    void openManga() => _openMangaDetail(context, manga, 'home_continue');

    return Material(
      color: featured ? palette.surfaceTint : YomiPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: featured
              ? palette.primary.withValues(alpha: 0.42)
              : Colors.white10,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: EdgeInsets.all(featured ? 16 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: openManga,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: YomiCoverImage(
                        manga: manga,
                        width: featured ? 80 : 56,
                        height: featured ? 114 : 84,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: openManga,
                                child: Text(
                                  manga.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: featured ? 17.5 : 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Opções da obra',
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 20,
                                color: Colors.white70,
                              ),
                              color: YomiPalette.surfaceElevated,
                              onSelected: (val) async {
                                if (val == 'manga') {
                                  openManga();
                                } else if (val == 'read') {
                                  open();
                                } else if (val == 'list') {
                                  await showAddMangaToReadingListSheet(
                                    context,
                                    manga,
                                  );
                                } else if (val == 'done') {
                                  await StorageService.markChapterAsRead(
                                    manga,
                                    chapter,
                                  );
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'manga',
                                  child: Row(
                                    children: [
                                      Icon(Icons.menu_book_rounded, size: 18),
                                      SizedBox(width: 10),
                                      Text('Ver página do mangá'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'read',
                                  child: Row(
                                    children: [
                                      Icon(Icons.play_arrow_rounded, size: 18),
                                      SizedBox(width: 10),
                                      Text('Continuar leitura'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'list',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.playlist_add_rounded,
                                        size: 18,
                                      ),
                                      SizedBox(width: 10),
                                      Text('Salvar em lista'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'done',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 18,
                                      ),
                                      SizedBox(width: 10),
                                      Text('Marcar como concluído'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cap. ${chapter.chapterNumber} · ${chapter.language}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          chapter.pages > 0
                              ? 'Página $page de ${chapter.pages}'
                              : 'Página $page',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.white54,
                          ),
                        ),
                        if (featured && progress != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 5,
                                    color: palette.primary,
                                    backgroundColor: Colors.white12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                percentText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (featured) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: open,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 16,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(
                    'Continuar leitura',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// A popularity ranking contains only titles fetched from the provider.
  Widget _popularSection(BuildContext context, ProfileAdaptivePalette palette) {
    final seen = <String>{};
    final rollItems = <Manga>[];
    for (final m in _visiblePopular) {
      if (seen.add(m.compositeId)) rollItems.add(m);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          title: 'Mangás Populares',
          actionLabel: 'Ver todos',
          accentColor: palette.secondary,
          onAction: widget.onExplore,
        ),
        const SizedBox(height: 12),
        if (rollItems.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loadingPopular
                ? const LinearProgressIndicator()
                : TextButton.icon(
                    onPressed: _loadPopularMangas,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar carregar recomendações'),
                  ),
          ),
        SizedBox(
          height: rollItems.isEmpty
              ? 0
              : homeCoverWidth(MediaQuery.sizeOf(context).width - 32) * 1.5 +
                    MediaQuery.textScalerOf(context).scale(12.5) * 3 +
                    16,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rollItems.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final m = rollItems[idx];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openMangaDetail(context, m, 'home_popular_$idx'),
                child: SizedBox(
                  width: homeCoverWidth(MediaQuery.sizeOf(context).width - 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: YomiCoverImage(
                            manga: m,
                            width: homeCoverWidth(
                              MediaQuery.sizeOf(context).width - 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _shortcuts(BuildContext context, ProfileAdaptivePalette palette) {
    final explore = _shortcut(
      'Explorar',
      Icons.explore_rounded,
      palette.primary,
      widget.onExplore,
    );
    final library = _shortcut(
      'Biblioteca',
      Icons.bookmarks_rounded,
      palette.primary,
      widget.onLibrary,
    );
    if (MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [explore, const SizedBox(height: 12), library],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: explore),
          const SizedBox(width: 12),
          Expanded(child: library),
        ],
      ),
    );
  }

  Widget _shortcut(
    String title,
    IconData icon,
    Color accentColor,
    VoidCallback onTap,
  ) => Material(
    color: YomiPalette.surface.withValues(alpha: 0.75),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Colors.white10),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: accentColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _updates(
    BuildContext context,
    ProfileAdaptivePalette palette,
  ) => ValueListenableBuilder(
    valueListenable: StorageService.settingsBox.listenable(),
    builder: (context, Box box, _) => ValueListenableBuilder(
      valueListenable: StorageService.favBox.listenable(),
      builder: (context, Box favs, _) {
        final pending = FavoriteUpdatesService.allPending(
          StorageService.getFavorites(),
        );
        if (pending.isEmpty) return const SizedBox.shrink();
        return Material(
          color: YomiPalette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: palette.secondary.withValues(alpha: 0.35)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Badge(
              label: Text('${pending.length}'),
              backgroundColor: palette.primary,
              child: Icon(
                Icons.notifications_active_rounded,
                color: palette.secondary,
              ),
            ),
            title: const Text(
              'Novidades nos favoritos',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('${pending.length} capítulos aguardando'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FavoriteUpdatesScreen()),
            ),
          ),
        );
      },
    ),
  );
}
