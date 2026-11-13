import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/appearance_controller.dart';
import '../services/device_state_service.dart';
import '../services/favorite_updates_service.dart';
import '../services/library_progress.dart';
import '../services/mangadex_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/home_billboard.dart';
import '../widgets/individual_glass_capsule.dart';
import '../widgets/yomi_blobatar_studio.dart';
import '../widgets/floating_continue_cover.dart';
import '../services/yomi_theme_system.dart';
import 'favorite_updates_screen.dart';
import 'home_tabs.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

/// Clipper que desenha a onda de transição ("wave wipe") revelando a próxima paleta.
class HomeWaveWipeClipper extends CustomClipper<Path> {
  final double progress;
  final bool forward;

  const HomeWaveWipeClipper({
    required this.progress,
    this.forward = true,
  });

  @override
  Path getClip(Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.0) return Path();
    if (p >= 1.0) return Path()..addRect(Offset.zero & size);

    const waveAmp = 26.0;
    final totalSpan = size.width + waveAmp * 2;
    final leadX = forward
        ? -waveAmp + totalSpan * p
        : size.width + waveAmp - totalSpan * p;

    final path = Path();
    if (forward) {
      path.moveTo(0, 0);
      path.lineTo(leadX, 0);
      const segments = 28;
      for (var i = 0; i <= segments; i++) {
        final t = i / segments;
        final y = size.height * t;
        final wave = math.sin((t * 2.2 + p) * math.pi * 2) *
            waveAmp *
            math.sin(p * math.pi);
        path.lineTo(leadX + wave, y);
      }
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(leadX, 0);
      const segments = 28;
      for (var i = 0; i <= segments; i++) {
        final t = i / segments;
        final y = size.height * t;
        final wave = math.sin((t * 2.2 + p) * math.pi * 2) *
            waveAmp *
            math.sin(p * math.pi);
        path.lineTo(leadX - wave, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant HomeWaveWipeClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.forward != forward;
}

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

class _HomeOverviewScreenState extends State<HomeOverviewScreen>
    with SingleTickerProviderStateMixin {
  List<Manga> _popularMangas = [];
  bool _loadingPopular = false;
  bool _openingFeatured = false;
  int _popularGeneration = 0;
  int _featuredIndex = 0;
  int _previousFeaturedIndex = 0;
  bool _transitionForward = true;
  int _paletteGeneration = 0;
  Timer? _featuredTimer;

  // Cache LRU limitado (máx. 4 destaques) para evitar pressão de memória
  static const int _maxPreloadedEntries = 4;
  final LinkedHashMap<String, ProfileAdaptivePalette> _preloadedPalettes =
      LinkedHashMap();
  final Set<String> _preloadedImages = <String>{};
  final Set<String> _preloadingInFlight = <String>{};

  late final AnimationController _waveController;
  ProfileAdaptivePalette _fromPalette =
      ProfilePaletteService.paletteNotifier.value;
  ProfileAdaptivePalette _toPalette =
      ProfilePaletteService.paletteNotifier.value;

  // Controle de encolhimento/recolhimento do Header sincronizado apenas com rolagem vertical
  double _headerCollapse = 0.0;

  List<Manga> get _featuredItems => _visiblePopular.take(5).toList();

  ProfileAdaptivePalette _deterministicFallback(Manga manga) {
    final cached = _preloadedPalettes[manga.compositeId];
    if (cached != null) return cached;
    final syncFallback =
        ProfilePaletteService.synchronousFallbackForManga(manga);
    final profilePalette = ProfilePaletteService.paletteNotifier.value;
    if (!identical(syncFallback, profilePalette)) return syncFallback;
    final hue = manga.title.runes.fold<int>(
      0,
      (hash, c) => (hash * 31 + c) & 0x7fffffff,
    ) %
        360;
    return ProfileAdaptivePalette.fromColor(
      HSVColor.fromAHSV(1, hue.toDouble(), 0.65, 0.85).toColor(),
    );
  }

  void _storePaletteInBoundedCache(String key, ProfileAdaptivePalette palette) {
    _preloadedPalettes.remove(key);
    if (_preloadedPalettes.length >= _maxPreloadedEntries) {
      final evicted = _preloadedPalettes.keys.first;
      _preloadedPalettes.remove(evicted);
      _preloadedImages.remove(evicted);
    }
    _preloadedPalettes[key] = palette;
  }

  Future<void> _warmCandidate(Manga manga) async {
    final key = manga.compositeId;
    if (_preloadingInFlight.contains(key)) return;
    _preloadingInFlight.add(key);
    try {
      final resolver =
          widget.paletteResolver ?? ProfilePaletteService.resolveForManga;
      final resolved = await resolver(manga);
      _storePaletteInBoundedCache(key, resolved);
      if (mounted && !DeviceStateService.instance.isOffline) {
        final rawUrl = manga.getCoverUrl(highRes: true);
        if (rawUrl.isNotEmpty) {
          final width = (MediaQuery.sizeOf(context).width *
                  MediaQuery.devicePixelRatioOf(context))
              .ceil()
              .clamp(240, 1080)
              .toInt();
          final provider = ResizeImage(
            NetworkImage(
              rawUrl,
              headers: manga.customHeaders.isEmpty ? null : manga.customHeaders,
            ),
            width: width,
          );
          await precacheImage(provider, context).catchError((Object _) {});
        }
      }
      _preloadedImages.add(key);
    } catch (_) {
      _storePaletteInBoundedCache(key, _deterministicFallback(manga));
      _preloadedImages.add(key);
    } finally {
      _preloadingInFlight.remove(key);
    }
  }

  void _warmNeighbors(int currentIndex) {
    final items = _featuredItems;
    if (items.isEmpty) return;
    final nextIdx = (currentIndex + 1) % items.length;
    unawaited(_warmCandidate(items[currentIndex]));
    if (nextIdx != currentIndex) {
      unawaited(_warmCandidate(items[nextIdx]));
    }
  }

  ProfileAdaptivePalette get _currentInterpolatedPalette {
    final t = Curves.easeInOutCubic.transform(_waveController.value);
    return ProfileAdaptivePalette.lerp(_fromPalette, _toPalette, t);
  }

  void _syncGlobalPaletteProgress() {
    if (!mounted) return;
    if (_waveController.status == AnimationStatus.completed ||
        _waveController.value >= 1.0) {
      if (YomiThemeController.instance.reactiveColorsEnabled) {
        YomiThemeController.instance.updateReactiveAccent(
          _toPalette.primary,
        );
      }
    }
  }

  void _selectFeatured(int index, {bool manual = false}) {
    final items = _featuredItems;
    if (items.isEmpty) return;
    final selected = (index % items.length + items.length) % items.length;
    final manga = items[selected];
    final generation = ++_paletteGeneration;
    final reduceMotion =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
            DeviceStateService.instance.value.reduceEffects;
    final startPalette = _currentInterpolatedPalette;
    final targetInitial = _deterministicFallback(manga);

    setState(() {
      _transitionForward = selected >= _featuredIndex ||
          (_featuredIndex == items.length - 1 && selected == 0);
      _previousFeaturedIndex = _featuredIndex;
      _featuredIndex = selected;
      _fromPalette = startPalette;
      _toPalette = targetInitial;
    });

    if (reduceMotion) {
      _waveController.value = 1.0;
      _syncGlobalPaletteProgress();
    } else {
      _waveController.forward(from: 0.0);
    }

    _warmNeighbors(selected);

    (widget.paletteResolver ?? ProfilePaletteService.resolveForManga)(
      manga,
    ).then((resolved) {
      _storePaletteInBoundedCache(manga.compositeId, resolved);
      if (!mounted || generation != _paletteGeneration) return;
      if (resolved != _toPalette) {
        setState(() {
          _fromPalette = _currentInterpolatedPalette;
          _toPalette = resolved;
        });
        if (reduceMotion) {
          _waveController.value = 1.0;
          _syncGlobalPaletteProgress();
        } else if (!_waveController.isAnimating) {
          _waveController.forward(from: 0.0);
        }
      }
    });
  }

  bool _handleHomeVerticalScroll(ScrollNotification notification) {
    // Rolagem horizontal de carrosséis NÃO deve encolher nem recolher o header
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (!AppearanceController.instance.value.autoHideMenus) {
      if (_headerCollapse != 0.0) {
        setState(() => _headerCollapse = 0.0);
      }
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final pixels = notification.metrics.pixels;
      if (pixels <= 8) {
        if (_headerCollapse != 0.0) {
          setState(() => _headerCollapse = 0.0);
        }
        return false;
      }
      final delta = notification.scrollDelta ?? 0.0;
      if (delta.abs() < 0.5) return false;
      final next = (_headerCollapse + (delta / 76.0)).clamp(0.0, 1.0);
      if ((next - _headerCollapse).abs() > 0.01) {
        setState(() => _headerCollapse = next);
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: 1.0,
    )..addListener(_syncGlobalPaletteProgress);

    _loadPopularMangas();
    _featuredTimer = Timer.periodic(widget.featuredInterval, (_) {
      if (!mounted ||
          _openingFeatured ||
          _featuredItems.length < 2 ||
          !TickerMode.of(context) ||
          MediaQuery.disableAnimationsOf(context) ||
          DeviceStateService.instance.value.reduceEffects ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      final nextIdx = (_featuredIndex + 1) % _featuredItems.length;
      final nextManga = _featuredItems[nextIdx];
      // Se o próximo destaque ainda não estiver pré-carregado, prepara-o sem piscar a tela
      if (!_preloadedImages.contains(nextManga.compositeId)) {
        unawaited(_warmCandidate(nextManga));
      }
      _selectFeatured(nextIdx);
    });
    StorageService.nsfwModeNotifier.addListener(_loadPopularMangas);
  }

  @override
  void dispose() {
    _featuredTimer?.cancel();
    _waveController.removeListener(_syncGlobalPaletteProgress);
    _waveController.dispose();
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
          _previousFeaturedIndex = 0;
        });
        _selectFeatured(0);
      }
    } catch (_) {
      // Mantém títulos anteriores em falhas temporárias
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          _waveController,
          ProfilePaletteService.paletteNotifier,
          StorageService.profileNotifier,
          StorageService.nsfwModeNotifier,
        ]),
        builder: (context, _) {
          final palette = _currentInterpolatedPalette;
          final profile = StorageService.profileNotifier.value;
          final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
              DeviceStateService.instance.value.reduceEffects;
          final collapse = reduceMotion
              ? (_headerCollapse > 0.5 ? 1.0 : 0.0)
              : _headerCollapse;

          return Scaffold(
            extendBodyBehindAppBar: true,
            body: NotificationListener<ScrollNotification>(
              onNotification: _handleHomeVerticalScroll,
              child: Stack(
                children: [
                  ValueListenableBuilder(
                    valueListenable: StorageService.historyBox.listenable(
                      keys: const ['recent_reading_list'],
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
                              _featured(context, palette, reduceMotion),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: _popularSection(context, palette),
                              ),
                              const SizedBox(height: 28),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                  // Header com superfície própria de alto contraste sincronizado com rolagem e paleta
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildCollapsibleHeader(
                      context,
                      palette: palette,
                      profile: profile,
                      collapse: collapse,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _buildCollapsibleHeader(
    BuildContext context, {
    required ProfileAdaptivePalette palette,
    required UserProfile profile,
    required double collapse,
  }) {
    final topPad = MediaQuery.paddingOf(context).top;
    // Encolhe suavemente até ocultar quando collapse == 1.0, coordenado com a barra inferior
    final slideY = -(collapse * 0.85);
    final barHeight = 56.0 - (10.0 * collapse);
    final logoSize = 23.0 - (3.0 * collapse);
    final fgColor = palette.readableOnSurface;

    return IgnorePointer(
      ignoring: collapse > 0.92,
      child: FractionalTranslation(
        translation: Offset(0, slideY),
        child: Opacity(
          opacity: (1.0 - collapse * 0.9).clamp(0.0, 1.0),
          child: Padding(
            padding: EdgeInsets.only(
              top: topPad + 4,
              left: 16,
              right: 16,
            ),
            child: SizedBox(
              height: barHeight,
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 132,
                    ),
                    child: IndividualGlassCapsule(
                      borderRadius: BorderRadius.circular(18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      surfaceTint: palette.surfaceTint,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: YomiEnsoLogo(
                          fontSize: logoSize,
                          palette: palette,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IndividualGlassCapsule(
                    isCircle: true,
                    width: 48,
                    height: 48,
                    surfaceTint: palette.surfaceTint,
                    tooltip: 'Buscar mangás',
                    onTap: widget.onExplore,
                    child: Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: fgColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IndividualGlassCapsule(
                    isCircle: true,
                    width: 48,
                    height: 48,
                    surfaceTint: palette.surfaceTint,
                    child: Center(
                      child: YomiProfileAvatarView(
                        profile: profile,
                        size: 34 - (4 * collapse),
                        borderColor: palette.primary,
                        adaptiveHue: palette.hue,
                        onTap: widget.onProfile ?? widget.onLibrary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _featured(
    BuildContext context,
    ProfileAdaptivePalette palette,
    bool reduceMotion,
  ) {
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

    final currentManga = popular[_featuredIndex % popular.length];
    final prevManga = popular[_previousFeaturedIndex % popular.length];

    return ValueListenableBuilder(
      valueListenable: StorageService.favBox.listenable(),
      builder: (context, Box box, _) => GestureDetector(
        onHorizontalDragEnd: popular.length > 1
            ? (details) {
                final vx = details.primaryVelocity ?? 0;
                if (vx < -180) {
                  _selectFeatured(_featuredIndex + 1, manual: true);
                } else if (vx > 180) {
                  _selectFeatured(_featuredIndex - 1, manual: true);
                }
              }
            : null,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Efeito Ambilight: aura luminosa ambiental difusa ao redor do destaque
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, _) {
                        final currentPalette = _currentInterpolatedPalette;
                        final enabled =
                            YomiThemeController.instance.ambilightEnabled;
                        if (!enabled) return const SizedBox.shrink();

                        return Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0.0, -0.15),
                              radius: 1.15,
                              colors: [
                                currentPalette.primary.withValues(alpha: 0.38),
                                currentPalette.secondary.withValues(
                                  alpha: 0.18,
                                ),
                                currentPalette.primary.withValues(alpha: 0.05),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.38, 0.72, 1.0],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Efeito Ambilight: aura luminosa vazando para a parte de baixo após o destaque
                Positioned(
                  bottom: -72,
                  left: 0,
                  right: 0,
                  height: 120,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, _) {
                        final currentPalette = _currentInterpolatedPalette;
                        final enabled =
                            YomiThemeController.instance.ambilightEnabled;
                        if (!enabled) return const SizedBox.shrink();

                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                currentPalette.primary.withValues(alpha: 0.32),
                                currentPalette.secondary.withValues(
                                  alpha: 0.12,
                                ),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) {
                    final progress = _waveController.value;
                    if (reduceMotion ||
                        progress >= 1.0 ||
                        prevManga.compositeId == currentManga.compositeId) {
                      return HomeBillboard(
                        key: ValueKey(currentManga.compositeId),
                        manga: currentManga,
                        artwork:
                            YomiCoverImage(manga: currentManga, highRes: true),
                        accent: palette.primary,
                        inList: StorageService.isMangaInReadLater(
                          currentManga.id,
                        ),
                        opening: _openingFeatured,
                        onRead: () => _readFeatured(currentManga),
                        onToggleList: () =>
                            _toggleReadLaterWithFeedback(currentManga),
                      );
                    }

                    final t = Curves.easeInOutCubic.transform(progress);
                    final slideOffset = _transitionForward
                        ? (1.0 - t) * 28.0
                        : -(1.0 - t) * 28.0;

                    return Stack(
                      children: [
                        Opacity(
                          opacity: (1.0 - t).clamp(0.0, 1.0),
                          child: HomeBillboard(
                            key: ValueKey('prev_${prevManga.compositeId}'),
                            manga: prevManga,
                            artwork: YomiCoverImage(
                              manga: prevManga,
                              highRes: true,
                            ),
                            accent: _fromPalette.primary,
                            inList: StorageService.isMangaInReadLater(
                              prevManga.id,
                            ),
                            opening: _openingFeatured,
                            onRead: () => _readFeatured(prevManga),
                            onToggleList: () =>
                                _toggleReadLaterWithFeedback(prevManga),
                          ),
                        ),
                        Transform.translate(
                          offset: Offset(slideOffset, 0),
                          child: Opacity(
                            opacity: t.clamp(0.0, 1.0),
                            child: HomeBillboard(
                              key: ValueKey(currentManga.compositeId),
                              manga: currentManga,
                              artwork: YomiCoverImage(
                                manga: currentManga,
                                highRes: true,
                              ),
                              accent: palette.primary,
                              inList: StorageService.isMangaInReadLater(
                                currentManga.id,
                              ),
                              opening: _openingFeatured,
                              onRead: () => _readFeatured(currentManga),
                              onToggleList: () =>
                                  _toggleReadLaterWithFeedback(currentManga),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
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
                        onTap: () => _selectFeatured(index, manual: true),
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: 40,
                          height: 36,
                          child: Center(
                            child: AnimatedContainer(
                              duration: reduceMotion
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
      ),
    );
  }

  Future<void> _toggleReadLaterWithFeedback(Manga manga) async {
    try {
      final added = await StorageService.toggleReadLater(manga);
      if (mounted) {
        AppFeedback.show(
          context,
          SnackBar(
            content: Text(
              added
                  ? '"${manga.title}" adicionado à lista Ler mais tarde.'
                  : '"${manga.title}" removido de Ler mais tarde.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        AppFeedback.show(
          context,
          const SnackBar(
            content: Text('Não foi possível atualizar sua lista. Tente novamente.'),
          ),
        );
      }
    }
  }

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
        await StorageService.recordKnownChaptersCount(
          manga.id,
          0,
          titleKey: manga.normalizedTitleKey,
        );
        if (!mounted) return;
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

  Widget _sectionHeader({
    required String title,
    required String actionLabel,
    required Color accentColor,
    required VoidCallback onAction,
  }) =>
      Row(
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

  /// Compartilha a animação de capa (`FloatingContinueCover`) com a Biblioteca.
  Widget _readingCard(
    BuildContext context,
    Map<String, dynamic> item, {
    required ProfileAdaptivePalette palette,
    bool featured = false,
  }) {
    final manga = item['manga'] as Manga;
    final cardPalette =
        ProfilePaletteService.synchronousFallbackForManga(manga);
    final chapter = item['chapter'] as Chapter;
    final page = StorageService.getSavedPageIndex(chapter.id) + 1;
    final reading = LibraryProgress.forManga(manga);
    final progress = chapter.pages > 0
        ? (page / chapter.pages).clamp(0.0, 1.0)
        : reading.fraction;
    final percentText = progress != null
        ? '${(progress * 100).round()}%'
        : 'Progresso indisponível';
    final isFav = StorageService.isFavorite(manga.id);

    void open() => _openChapter(context, manga, chapter);
    void openManga() => _openMangaDetail(context, manga, 'home_continue');

    return Material(
      color: featured ? cardPalette.surfaceTint : YomiPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: featured
              ? cardPalette.primary.withValues(alpha: 0.42)
              : Colors.white10,
        ),
      ),
      clipBehavior: Clip.none,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: open,
        child: Padding(
          padding: EdgeInsets.all(featured ? 16 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: openManga,
                    child: featured
                        ? FloatingContinueCover(
                            manga: manga,
                            width: 84,
                            height: 120,
                            palette: cardPalette,
                            isFavorite: isFav,
                            onFavoriteToggle: () =>
                                StorageService.toggleFavorite(manga),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: YomiCoverImage(
                              manga: manga,
                              width: 56,
                              height: 84,
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
                                    color: cardPalette.primary,
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
                    backgroundColor: cardPalette.primary,
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

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

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
          child: ValueListenableBuilder(
            valueListenable: StorageService.historyBox.listenable(),
            builder: (context, Box historyBox, _) => ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rollItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final m = rollItems[idx];
                final isZeroConfirmed =
                    StorageService.isConfirmedZeroChapters(m);
                final coverWidth =
                    homeCoverWidth(MediaQuery.sizeOf(context).width - 32);
                Widget cover = YomiCoverImage(manga: m, width: coverWidth);
                if (isZeroConfirmed) {
                  cover = ColorFiltered(
                    colorFilter: _grayscaleFilter,
                    child: cover,
                  );
                }

                return Semantics(
                  label: isZeroConfirmed
                      ? '${m.title} — 0 capítulos disponíveis'
                      : m.title,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () =>
                        _openMangaDetail(context, m, 'home_popular_$idx'),
                    child: Opacity(
                      opacity: isZeroConfirmed ? 0.62 : 1.0,
                      child: SizedBox(
                        width: coverWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    cover,
                                    if (isZeroConfirmed)
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          color: Colors.black
                                              .withValues(alpha: 0.80),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 3,
                                          ),
                                          alignment: Alignment.center,
                                          child: const Text(
                                            '0 CAPÍTULOS',
                                            style: TextStyle(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              m.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: isZeroConfirmed
                                    ? Colors.white54
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
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
  ) =>
      Material(
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
  ) =>
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
