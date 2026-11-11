import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/favorite_updates_service.dart';
import '../services/mangadex_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/yomi_blobatar_studio.dart';
import 'favorite_updates_screen.dart';
import 'home_tabs.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

/// Reading shortcuts share the same covers, artwork and surfaces as the library.
class HomeOverviewScreen extends StatefulWidget {
  final VoidCallback onExplore;
  final VoidCallback onLibrary;
  final VoidCallback? onProfile;

  const HomeOverviewScreen({
    super.key,
    required this.onExplore,
    required this.onLibrary,
    this.onProfile,
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

  @override
  void initState() {
    super.initState();
    _loadPopularMangas();
    StorageService.nsfwModeNotifier.addListener(_loadPopularMangas);
  }

  @override
  void dispose() {
    StorageService.nsfwModeNotifier.removeListener(_loadPopularMangas);
    super.dispose();
  }

  Future<void> _loadPopularMangas() async {
    if (_loadingPopular) return;
    setState(() => _loadingPopular = true);
    try {
      final fetched = await MangaDexService.fetchPopularMangas(
        limit: 12,
        includeNsfw: StorageService.nsfwMode.allowNsfwFetch,
      );
      if (mounted && fetched.isNotEmpty) {
        setState(() => _popularMangas = fetched);
      }
    } catch (_) {
      // Keep actual previously fetched titles on temporary failures.
    } finally {
      if (mounted) setState(() => _loadingPopular = false);
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
      final palette = ProfilePaletteService.paletteNotifier.value;
      final profile = StorageService.profileNotifier.value;

      return Scaffold(
        appBar: AppBar(
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
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _welcome(context, palette),
                    const SizedBox(height: 22),
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
                    _popularAndForYouRollSection(context, palette),
                    const SizedBox(height: 20),
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

  Widget _welcome(BuildContext context, ProfileAdaptivePalette palette) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.bannerDark,
                Color.lerp(const Color(0xFF1A0710), palette.primary, 0.28)!,
                const Color(0xFF0A0A10),
              ],
            ),
            border: Border.all(color: palette.primary.withValues(alpha: 0.32)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _HomeHeroToriiPainter(
                    accentColor: palette.primary,
                    secondaryColor: palette.secondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HISTÓRIAS QUE\nTE LEVAM MAIS LONGE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                        height: 1.3,
                        color: palette.secondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Descubra\nnovos mundos',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Mangás, webtoons e muito mais\nem um só lugar.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: widget.onExplore,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.explore_rounded, size: 18),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Explorar agora',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.chevron_right_rounded, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

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
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: accentColor,
              ),
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
        : '12%';
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
                        if (featured) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: progress ?? 0.12,
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

  /// Replaces the old illustrative genre cards with a horizontal roll of the most popular titles!
  Widget _popularAndForYouRollSection(
    BuildContext context,
    ProfileAdaptivePalette palette,
  ) {
    return ValueListenableBuilder(
      valueListenable: StorageService.favBox.listenable(),
      builder: (context, Box favBox, _) {
        final favs = StorageService.getFavorites();
        final seen = <String>{};
        final rollItems = <Manga>[];
        for (final m in _popularMangas) {
          if (seen.add(m.id)) rollItems.add(m);
        }
        for (final m in favs) {
          if (seen.add(m.id)) rollItems.add(m);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              title: 'Títulos mais populares',
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
              height: rollItems.isEmpty ? 0 : 196,
              child: ListView.separated(
                // ignore: deprecated_member_use
                cacheExtent: 1500,
                scrollDirection: Axis.horizontal,
                itemCount: rollItems.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, idx) {
                  final m = rollItems[idx];
                  return GestureDetector(
                    onTap: () =>
                        _openMangaDetail(context, m, 'home_popular_$idx'),
                    child: SizedBox(
                      width: 112,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: YomiCoverImage(manga: m, width: 112),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
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
      },
    );
  }

  Widget _shortcuts(BuildContext context, ProfileAdaptivePalette palette) {
    final explore = _shortcut(
      'Explorar',
      'Encontre novas histórias',
      Icons.explore_rounded,
      palette.primary,
      widget.onExplore,
    );
    final library = _shortcut(
      'Biblioteca',
      'Suas obras favoritas',
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
    String description,
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

  Widget _updates(BuildContext context, ProfileAdaptivePalette palette) =>
      ValueListenableBuilder(
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
                side: BorderSide(
                  color: palette.secondary.withValues(alpha: 0.35),
                ),
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
                  MaterialPageRoute(
                    builder: (_) => const FavoriteUpdatesScreen(),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _HomeHeroToriiPainter extends CustomPainter {
  final Color accentColor;
  final Color secondaryColor;

  const _HomeHeroToriiPainter({
    this.accentColor = const Color(0xFFE11D48),
    this.secondaryColor = const Color(0xFFF472B6),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sunCenter = Offset(size.width * 0.80, size.height * 0.44);
    final sunRadius = 46.0;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor.withValues(alpha: 0.48),
          accentColor.withValues(alpha: 0.14),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: 95));
    canvas.drawCircle(sunCenter, 95, glowPaint);

    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()..color = accentColor.withValues(alpha: 0.82),
    );

    final cityPaint = Paint()
      ..color = const Color(0xFF0A0509).withValues(alpha: 0.72);
    final blds = [
      Rect.fromLTWH(size.width * 0.56, size.height * 0.58, 18, size.height),
      Rect.fromLTWH(size.width * 0.63, size.height * 0.50, 22, size.height),
      Rect.fromLTWH(size.width * 0.71, size.height * 0.62, 16, size.height),
      Rect.fromLTWH(size.width * 0.88, size.height * 0.52, 24, size.height),
      Rect.fromLTWH(size.width * 0.94, size.height * 0.44, 22, size.height),
    ];
    for (final r in blds) {
      canvas.drawRect(r, cityPaint);
    }

    final toriiPaint = Paint()
      ..color = const Color(0xFF090408)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final tx = sunCenter.dx + 4;
    final ty = sunCenter.dy - 4;
    canvas.drawLine(
      Offset(tx - 24, ty - 10),
      Offset(tx + 24, ty - 10),
      toriiPaint,
    );
    canvas.drawLine(
      Offset(tx - 18, ty - 2),
      Offset(tx + 18, ty - 2),
      toriiPaint,
    );
    canvas.drawLine(
      Offset(tx - 12, ty - 10),
      Offset(tx - 14, ty + 24),
      toriiPaint,
    );
    canvas.drawLine(
      Offset(tx + 12, ty - 10),
      Offset(tx + 14, ty + 24),
      toriiPaint,
    );

    final charPaint = Paint()
      ..color = const Color(0xFF08060A).withValues(alpha: 0.92);
    final charX = size.width * 0.72;
    final charY = size.height * 0.64;
    canvas.drawCircle(Offset(charX, charY - 22), 14, charPaint);
    final torso = Path()
      ..moveTo(charX - 24, size.height)
      ..quadraticBezierTo(charX - 22, charY - 6, charX, charY - 8)
      ..quadraticBezierTo(charX + 24, charY - 6, charX + 26, size.height)
      ..close();
    canvas.drawPath(torso, charPaint);

    canvas.drawCircle(
      Offset(charX, charY + 14),
      10,
      Paint()
        ..color = accentColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeHeroToriiPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.secondaryColor != secondaryColor;
}
