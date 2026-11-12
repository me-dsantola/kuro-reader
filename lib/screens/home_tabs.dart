import '../widgets/app_feedback.dart';
import '../widgets/appearance_settings.dart';
import '../services/appearance_controller.dart';
import '../services/device_state_service.dart';
import '../models/catalog_sort.dart';
import '../widgets/catalog_sort_control.dart';
import 'favorite_updates_screen.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';
import '../services/download_manager.dart';
import '../services/favorite_updates_service.dart';
import '../services/catalog_request_state.dart';
import '../services/profile_palette_service.dart';
import '../widgets/frosted_surface.dart';
import '../widgets/yomi_blobatar_studio.dart';
import 'home_overview_screen.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

class YomiPalette {
  static const Color pitchBlack = Color(0xFF070709);
  static const Color surface = Color(0xFF121217);
  static const Color surfaceElevated = Color(0xFF181820);
  static const Color ensoRed = Color(0xFFE11D48);
  static const Color crimsonGlow = Color(0xFF9F1239);
  static const Color sakuraPink = Color(0xFFF472B6);
  static const Color sakuraSoft = Color(0xFFFBCFE8);
  static const Color pureWhite = Color(0xFFFAFAFA);
}

/// Widget Inteligente de Capa Multi-CDN (Nativo sem sqflite + Fallback i0.wp.com / wsrv.nl / codetabs + Auto-Recuperação AniList)
class YomiCoverImage extends StatefulWidget {
  final Manga manga;
  final bool highRes;
  final double? width;
  final double? height;
  final BoxFit fit;

  const YomiCoverImage({
    super.key,
    required this.manga,
    this.highRes = false,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<YomiCoverImage> createState() => _YomiCoverImageState();
}

class _YomiCoverImageState extends State<YomiCoverImage> {
  late List<String> _candidates;
  int _index = 0;
  bool _triedTitleRecovery = false;
  bool _exhausted = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _initCandidates();
  }

  @override
  void didUpdateWidget(covariant YomiCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manga.compositeId != widget.manga.compositeId ||
        oldWidget.highRes != widget.highRes ||
        oldWidget.manga.getRawCoverUrl(highRes: widget.highRes) !=
            widget.manga.getRawCoverUrl(highRes: widget.highRes)) {
      _initCandidates();
    }
  }

  void _initCandidates() {
    _generation++;
    _candidates = List<String>.from(
      widget.manga.getAllCandidateCoverUrls(highRes: widget.highRes),
    );
    _index = 0;
    _triedTitleRecovery = false;
    _exhausted = false;
    if (_candidates.isEmpty) {
      _recoverCoverByTitle();
    }
  }

  Future<void> _recoverCoverByTitle() async {
    if (_triedTitleRecovery) {
      if (mounted) setState(() => _exhausted = true);
      return;
    }
    _triedTitleRecovery = true;
    final generation = _generation;
    final resolved = await MangaDexService.resolveCoverUrlByTitle(
      widget.manga.title,
    );
    if (!mounted || generation != _generation) return;
    if (resolved != null && resolved.isNotEmpty) {
      final newUrls = yomiCandidateImageUrls(resolved);
      if (newUrls.isNotEmpty) {
        setState(() {
          _index = _candidates.length;
          _candidates.addAll(newUrls);
          _exhausted = false;
        });
        return;
      }
    }
    setState(() => _exhausted = true);
  }

  void _advanceToNextCandidate() {
    if (!mounted) return;
    if (_index + 1 < _candidates.length) {
      setState(() => _index++);
    } else if (!_triedTitleRecovery) {
      _recoverCoverByTitle();
    } else if (!_exhausted) {
      setState(() => _exhausted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (DeviceStateService.instance.isOffline ||
        _exhausted ||
        _candidates.isEmpty ||
        _index >= _candidates.length) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: YomiPalette.surface,
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final icon = Icon(
              DeviceStateService.instance.isOffline
                  ? Icons.offline_pin_rounded
                  : _triedTitleRecovery && _exhausted
                  ? Icons.auto_stories_rounded
                  : Icons.sync_rounded,
              color: YomiPalette.ensoRed,
              size: 22,
            );
            if (constraints.maxHeight < 60) return icon;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 4),
                Text(
                  widget.manga.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ],
            );
          },
        ),
      );
    }

    final currentUrl = _candidates[_index];
    return Image.network(
      currentUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      headers: kIsWeb ? null : widget.manga.customHeaders,
      // Decode covers close to their displayed size. Without this, large
      // source images can consume tens of MB per grid item and cause jank.
      cacheWidth: (() {
        final logicalWidth =
            widget.width ??
            (widget.highRes
                ? MediaQuery.sizeOf(context).width
                : MediaQuery.sizeOf(context).width / 3);
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        return (logicalWidth * pixelRatio).ceil().clamp(160, 1080).toInt();
      })(),
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: widget.width,
          height: widget.height,
          color: YomiPalette.surface,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: YomiPalette.ensoRed,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _advanceToNextCandidate();
        });
        return Container(
          width: widget.width,
          height: widget.height,
          color: YomiPalette.surface,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: YomiPalette.sakuraPink,
            ),
          ),
        );
      },
    );
  }
}

class YomiEnsoLogo extends StatelessWidget {
  final double fontSize;
  const YomiEnsoLogo({super.key, this.fontSize = 23});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Y',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: YomiPalette.pureWhite,
              decoration: TextDecoration.none,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: CustomPaint(
              size: Size(fontSize * 0.86, fontSize * 0.86),
              painter: _EnsoOPainter(color: palette.primary),
            ),
          ),
          Text(
            'MI',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: YomiPalette.pureWhite,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnsoOPainter extends CustomPainter {
  final Color color;
  const _EnsoOPainter({this.color = YomiPalette.ensoRed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawArc(rect, -0.55, 5.25, false, paint);
  }

  @override
  bool shouldRepaint(covariant _EnsoOPainter oldDelegate) =>
      oldDelegate.color != color;
}

class YomiSakuraArtwork extends StatelessWidget {
  const YomiSakuraArtwork({super.key});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ProfileAdaptivePalette>(
        valueListenable: ProfilePaletteService.paletteNotifier,
        builder: (context, palette, _) => CustomPaint(
          painter: _ToriiSakuraBannerPainter(
            accentColor: palette.primary,
            secondaryColor: palette.secondary,
          ),
        ),
      );
}

class YomiSakuraBanner extends StatelessWidget {
  final String badgeText;
  final String subtitleText;

  const YomiSakuraBanner({
    super.key,
    this.badgeText = 'DESCUBRA SUA PRÓXIMA LEITURA',
    this.subtitleText = 'Leitura: MangaDex · Catálogos: AniList, MAL e Kitsu',
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) => Container(
        constraints: const BoxConstraints(minHeight: 118),
        width: double.infinity,
        child: CustomPaint(
          painter: _ToriiSakuraBannerPainter(
            accentColor: palette.primary,
            secondaryColor: palette.secondary,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  YomiPalette.pitchBlack.withValues(alpha: 0.92),
                ],
              ),
            ),
            alignment: Alignment.bottomLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: palette.primary, width: 1),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: palette.soft,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitleText,
                  style: TextStyle(
                    fontSize: 12,
                    color: YomiPalette.pureWhite.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToriiSakuraBannerPainter extends CustomPainter {
  final Color accentColor;
  final Color secondaryColor;

  const _ToriiSakuraBannerPainter({
    this.accentColor = YomiPalette.ensoRed,
    this.secondaryColor = YomiPalette.sakuraPink,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final darkTint = Color.lerp(const Color(0xFF070709), accentColor, 0.22)!;
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [darkTint, const Color(0xFF070709)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final sunCenter = Offset(size.width * 0.76, size.height * 0.48);
    final haloPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(sunCenter, 58, haloPaint);

    final sunPaint = Paint()..color = accentColor.withValues(alpha: 0.88);
    canvas.drawCircle(sunCenter, 42, sunPaint);

    final mountainPaint = Paint()..color = const Color(0xFF0B0810);
    final mountainPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.66)
      ..lineTo(size.width * 0.25, size.height * 0.44)
      ..lineTo(size.width * 0.50, size.height * 0.56)
      ..lineTo(size.width * 0.74, size.height * 0.62)
      ..lineTo(size.width, size.height * 0.70)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(mountainPath, mountainPaint);

    final toriiPaint = Paint()
      ..color = YomiPalette.pitchBlack
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final tx = sunCenter.dx;
    final ty = sunCenter.dy + 2;
    canvas.drawLine(
      Offset(tx - 24, ty - 12),
      Offset(tx + 24, ty - 12),
      toriiPaint,
    );
    canvas.drawLine(
      Offset(tx - 18, ty - 4),
      Offset(tx + 18, ty - 4),
      toriiPaint,
    );
    canvas.drawLine(
      Offset(tx - 13, ty - 12),
      Offset(tx - 15, ty + 22),
      toriiPaint,
    );
    canvas.drawLine(
      Offset(tx + 13, ty - 12),
      Offset(tx + 15, ty + 22),
      toriiPaint,
    );

    final sakuraPaint = Paint()..color = secondaryColor.withValues(alpha: 0.62);
    final petals = [
      Offset(size.width * 0.12, size.height * 0.28),
      Offset(size.width * 0.28, size.height * 0.50),
      Offset(size.width * 0.45, size.height * 0.22),
      Offset(size.width * 0.62, size.height * 0.35),
      Offset(size.width * 0.88, size.height * 0.25),
      Offset(size.width * 0.20, size.height * 0.36),
    ];
    for (final p in petals) {
      canvas.drawOval(
        Rect.fromCenter(center: p, width: 8.5, height: 4.6),
        sakuraPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ToriiSakuraBannerPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.secondaryColor != secondaryColor;
}

// ============================================================================
// ABA 0: PERFIL (BANNER + MASCOTE BLOBATAR + RECENTES, LISTAS EM ROLL & FAVORITOS)
// ============================================================================
class ProfileDashboardScreen extends StatefulWidget {
  final VoidCallback? onGoToExplore;
  final VoidCallback? onGoToSettings;

  const ProfileDashboardScreen({
    super.key,
    required this.onGoToExplore,
    required this.onGoToSettings,
  });

  @override
  State<ProfileDashboardScreen> createState() => _ProfileDashboardScreenState();
}

class _ProfileDashboardScreenState extends State<ProfileDashboardScreen> {
  int _selectedGenreIdx = 0;

  @override
  void initState() {
    super.initState();
    ProfilePaletteService.bindToProfileNotifier(StorageService.profileNotifier);
  }

  void _openChapterFromProfile(
    BuildContext context,
    Manga manga,
    Chapter chapter,
  ) {
    final chapters = HomeOverviewScreen.buildSortedChapterList(manga, chapter);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReaderScreen(manga: manga, chapter: chapter, allChapters: chapters),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        StorageService.profileNotifier,
        StorageService.nsfwModeNotifier,
        ProfilePaletteService.paletteNotifier,
      ]),
      builder: (context, _) {
        final profile = StorageService.profileNotifier.value;
        final palette = ProfilePaletteService.paletteNotifier.value;
        final accent = palette.primary;
        final secondary = palette.secondary;
        final hasCustomPhoto =
            !profile.useBlobatarAsAvatar &&
            (profile.avatarImagePath?.trim().isNotEmpty ?? false);

        return Scaffold(
          backgroundColor: YomiPalette.pitchBlack,
          body: ValueListenableBuilder(
            valueListenable: StorageService.historyBox.listenable(
              keys: ['recent_reading_list'],
            ),
            builder: (context, Box historyBox, _) {
              return ValueListenableBuilder(
                valueListenable: StorageService.favBox.listenable(),
                builder: (context, Box favBox, _) {
                  return ValueListenableBuilder(
                    valueListenable: StorageService.settingsBox.listenable(),
                    builder: (context, Box settingsBox, _) {
                      final continueList =
                          StorageService.getContinueReadingList();
                      final favorites = StorageService.getFavorites();
                      final readingLists = StorageService.getReadingLists();
                      final pendingUpdatesCount =
                          FavoriteUpdatesService.allPending(favorites).length;
                      final genreTags = profile.genreTags;

                      return ListView(
                        padding: const EdgeInsets.only(bottom: 116),
                        children: [
                          // 1. BANNER ADAPTATIVO + TOP BAR + BOTÃO DIRETO DE BANNER + AVATAR CENTRAL SOBREPOSTO
                          SizedBox(
                            height: 294,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Banner Art / Custom Image / Preset
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: 232,
                                  child: GestureDetector(
                                    onTap: () =>
                                        showYomiProfileAndBlobatarEditor(
                                          context,
                                          profile,
                                          initialTab: 1,
                                        ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        YomiBannerBackdrop(
                                          bannerPath: profile.bannerImagePath,
                                          palette: palette,
                                        ),
                                        DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.black.withValues(
                                                  alpha: 0.40,
                                                ),
                                                Colors.transparent,
                                                YomiPalette.pitchBlack
                                                    .withValues(alpha: 0.90),
                                                YomiPalette.pitchBlack,
                                              ],
                                              stops: const [
                                                0.0,
                                                0.35,
                                                0.84,
                                                1.0,
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Direct 1-tap Banner Change Pill Button
                                        Positioned(
                                          left: 14,
                                          bottom: 36,
                                          child: Material(
                                            color: Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              side: BorderSide(
                                                color: accent.withValues(
                                                  alpha: 0.55,
                                                ),
                                              ),
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              onTap: () =>
                                                  showYomiProfileAndBlobatarEditor(
                                                    context,
                                                    profile,
                                                    initialTab: 1,
                                                  ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.wallpaper_rounded,
                                                      size: 14,
                                                      color: palette.soft,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    const Text(
                                                      'Banner',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Transparent Top Bar (YOMI logo + Bell + Gear + More)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: SafeArea(
                                    bottom: false,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          const YomiEnsoLogo(),
                                          const Spacer(),
                                          IconButton(
                                            tooltip:
                                                'Notificações e capítulos de favoritos',
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const FavoriteUpdatesScreen(),
                                              ),
                                            ),
                                            icon: Badge(
                                              isLabelVisible:
                                                  pendingUpdatesCount > 0,
                                              backgroundColor: accent,
                                              label: Text(
                                                pendingUpdatesCount > 99
                                                    ? '99+'
                                                    : '$pendingUpdatesCount',
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              child: Icon(
                                                pendingUpdatesCount > 0
                                                    ? Icons
                                                          .notifications_active_rounded
                                                    : Icons
                                                          .notifications_none_rounded,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Ajustes & Backup',
                                            onPressed: widget.onGoToSettings,
                                            icon: const Icon(
                                              Icons.settings_outlined,
                                              color: Colors.white,
                                              size: 23,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Personalizar Perfil e Mascote',
                                            onPressed: () =>
                                                showYomiProfileAndBlobatarEditor(
                                                  context,
                                                  profile,
                                                  initialTab: 0,
                                                ),
                                            icon: const Icon(
                                              Icons.more_vert_rounded,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Overlapping Centered Avatar + Edit Button + Companion Blobatar
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: SizedBox(
                                      width: 126,
                                      height: 120,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: accent.withValues(
                                                    alpha: 0.35,
                                                  ),
                                                  blurRadius: 28,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                            child: YomiProfileAvatarView(
                                              profile: profile,
                                              size: 114,
                                              borderColor: Colors.white
                                                  .withValues(alpha: 0.75),
                                              adaptiveHue: palette.hue,
                                              onTap: () =>
                                                  showYomiProfileAndBlobatarEditor(
                                                    context,
                                                    profile,
                                                    initialTab: hasCustomPhoto
                                                        ? 1
                                                        : 0,
                                                  ),
                                            ),
                                          ),
                                          if (hasCustomPhoto)
                                            Positioned(
                                              left: -4,
                                              bottom: 2,
                                              child: Tooltip(
                                                message:
                                                    'Personalizar Mascote ${profile.effectiveBlobatarName}',
                                                child: GestureDetector(
                                                  onTap: () =>
                                                      showYomiProfileAndBlobatarEditor(
                                                        context,
                                                        profile,
                                                        initialTab: 0,
                                                      ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(2),
                                                    decoration: BoxDecoration(
                                                      color: YomiPalette
                                                          .pitchBlack,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: accent,
                                                        width: 1.5,
                                                      ),
                                                    ),
                                                    child: YomiProfileBlobatar(
                                                      profile: profile,
                                                      size: 32,
                                                      adaptiveHue: palette.hue,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          Positioned(
                                            right: 4,
                                            bottom: 2,
                                            child: GestureDetector(
                                              onTap: () =>
                                                  showYomiProfileAndBlobatarEditor(
                                                    context,
                                                    profile,
                                                    initialTab: 1,
                                                  ),
                                              child: Container(
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  color: accent,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color:
                                                        YomiPalette.pitchBlack,
                                                    width: 2.2,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: accent.withValues(
                                                        alpha: 0.5,
                                                      ),
                                                      blurRadius: 10,
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.edit_rounded,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // 2. NOME & BIO CENTRALIZADOS (SEM ESTATÍSTICAS)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                Text(
                                  profile.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  profile.bio.isEmpty
                                      ? 'Mais histórias, menos realidade.'
                                      : profile.bio,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 3. BOTÃO OUTLINED "Editar perfil"
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      showYomiProfileAndBlobatarEditor(
                                        context,
                                        profile,
                                        initialTab: 1,
                                      ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: accent.withValues(
                                      alpha: 0.05,
                                    ),
                                    side: BorderSide(
                                      color: accent.withValues(alpha: 0.65),
                                      width: 1.2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(26),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.person_outline_rounded,
                                    size: 19,
                                  ),
                                  label: const Text(
                                    'Editar perfil',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // 4. CARD INTERATIVO DO MASCOTE BLOBATAR COM NOME PERSONALIZADO
                                Material(
                                  color: palette.cardSurface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    side: BorderSide(
                                      color: accent.withValues(alpha: 0.28),
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        showYomiProfileAndBlobatarEditor(
                                          context,
                                          profile,
                                          initialTab: 0,
                                        ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          YomiProfileBlobatar(
                                            profile: profile,
                                            size: 46,
                                            adaptiveHue: palette.hue,
                                            interactiveCycleOnTap: true,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Mascote ${profile.effectiveBlobatarName}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                const Text(
                                                  'Personalize nome, expressão, silhueta, foto e banner.',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: accent,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 22),

                                // 5. GÊNEROS FAVORITOS
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Gêneros favoritos',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () =>
                                          showYomiProfileAndBlobatarEditor(
                                            context,
                                            profile,
                                            initialTab: 2,
                                          ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'Editar',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: secondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: List.generate(genreTags.length, (
                                      i,
                                    ) {
                                      final isSelected =
                                          i ==
                                          (_selectedGenreIdx %
                                              genreTags.length);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: GestureDetector(
                                          onTap: () => setState(
                                            () => _selectedGenreIdx = i,
                                          ),
                                          onLongPress: () =>
                                              showYomiProfileAndBlobatarEditor(
                                                context,
                                                profile,
                                                initialTab: 2,
                                              ),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? accent.withValues(
                                                      alpha: 0.22,
                                                    )
                                                  : const Color(0xFF121218),
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              border: Border.all(
                                                color: isSelected
                                                    ? accent
                                                    : Colors.white10,
                                                width: isSelected ? 1.3 : 1.0,
                                              ),
                                            ),
                                            child: Text(
                                              genreTags[i],
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSelected
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),

                                const SizedBox(height: 26),

                                // 6. SEÇÃO 1: OBRAS LIDAS RECENTEMENTE (EM ROLL)
                                _buildRecentWorksRoll(
                                  context,
                                  continueList,
                                  palette,
                                ),

                                const SizedBox(height: 26),

                                // 7. SEÇÃO 2: LISTAS DE LEITURA COM OS TÍTULOS EM ROLL
                                _buildReadingListsRollSection(
                                  context,
                                  readingLists,
                                  palette,
                                ),

                                const SizedBox(height: 26),

                                // 8. SEÇÃO 3: OBRAS FAVORITAS (EM ROLL)
                                _buildFavoriteWorksRollSection(
                                  context,
                                  favorites,
                                  palette,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRecentWorksRoll(
    BuildContext context,
    List<Map<String, dynamic>> continueList,
    ProfileAdaptivePalette palette,
  ) {
    final accent = palette.primary;
    final secondary = palette.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: accent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Obras lidas recentemente',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: widget.onGoToExplore,
              child: Text(
                'Explorar →',
                style: TextStyle(
                  color: secondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (continueList.isEmpty)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onGoToExplore,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.cardSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.menu_book_rounded, color: accent),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nenhuma obra lida recentemente',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'As obras e capítulos que você abrir aparecerão automaticamente aqui.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 202,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: continueList.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final item = continueList[idx];
                final Manga manga = item['manga'];
                final Chapter chapter = item['chapter'];
                final savedPage = StorageService.getSavedPageIndex(chapter.id);

                return GestureDetector(
                  onTap: () => _openChapterFromProfile(context, manga, chapter),
                  onLongPress: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MangaDetailScreen(
                        manga: manga,
                        heroTag: 'profile_recent_${manga.compositeId}',
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: 118,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                YomiCoverImage(manga: manga, highRes: false),
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.78,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Text(
                                      'Cap. ${chapter.chapterNumber} · P.${savedPage + 1}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: palette.soft,
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
                          manga.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
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

  Widget _buildReadingListsRollSection(
    BuildContext context,
    List<UserReadingList> readingLists,
    ProfileAdaptivePalette palette,
  ) {
    final accent = palette.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    Icons.collections_bookmark_rounded,
                    color: accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Listas de leitura',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.2),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => showCreateOrEditReadingListDialog(context),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text(
                'Nova lista',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (readingLists.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: palette.cardSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crie suas próprias listas de leitura personalizadas',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Organize seus mangás, manhwas e HQs em coleções com títulos em roll.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: Icon(
                        Icons.add_circle_outline_rounded,
                        size: 16,
                        color: accent,
                      ),
                      label: const Text('Criar Lista Personalizada'),
                      onPressed: () =>
                          showCreateOrEditReadingListDialog(context),
                    ),
                    ActionChip(
                      label: const Text('+ Para Ler Depois'),
                      onPressed: () => StorageService.createReadingList(
                        'Para Ler Depois',
                        description: 'Obras salvas para começar em breve',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          for (final list in readingLists) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.cardSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              list.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (list.description.isNotEmpty)
                              Text(
                                list.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white60,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Editar lista',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => showCreateOrEditReadingListDialog(
                          context,
                          existing: list,
                        ),
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: palette.soft,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Excluir lista',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            StorageService.deleteReadingList(list.id),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (list.mangas.isEmpty)
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Nenhuma obra adicionada a esta lista ainda.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => showCreateOrEditReadingListDialog(
                            context,
                            existing: list,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Adicionar'),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      height: 186,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: list.mangas.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, idx) => SizedBox(
                          width: 108,
                          child: MangaGridCard(
                            manga: list.mangas[idx],
                            heroPrefix: 'profile_list_${list.id}',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  Widget _buildFavoriteWorksRollSection(
    BuildContext context,
    List<Manga> favorites,
    ProfileAdaptivePalette palette,
  ) {
    final accent = palette.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.favorite_rounded, color: accent, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Obras favoritas',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (favorites.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.cardSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Icon(Icons.favorite_border_rounded, color: accent, size: 32),
                const SizedBox(height: 10),
                const Text(
                  'Sua vitrine de Obras Favoritas está vazia',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Toque no ícone de coração em qualquer Mangá, Manhwa ou Webtoon para destacá-lo no seu perfil.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.22),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: widget.onGoToExplore,
                  icon: const Icon(Icons.explore_rounded, size: 18),
                  label: const Text('Explorar Catálogo'),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: favorites.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, idx) => SizedBox(
                width: 112,
                child: MangaGridCard(
                  manga: favorites[idx],
                  heroPrefix: 'profile_fav',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// ABA 1: EXPLORAR (6 FONTES SIMULTÂNEAS + SELETOR RÁPIDO DE FONTE NO TOPO)
// ============================================================================
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
    setState(() {}); // Keep the clear-search button in sync.
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
    query: _searchController.text,
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
          _isEnrichingCatalog = true;
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
              _isEnrichingCatalog = false;
            }
          }
        }
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

// ============================================================================
// ABA 2: MINHA BIBLIOTECA (IDENTIDADE VISUAL LUAR + FAVORITOS + LISTAS)
// ============================================================================
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: DeviceStateService.instance,
    builder: (context, status, _) => DefaultTabController(
      key: ValueKey(status.internet == InternetState.offline),
      length: 2,
      initialIndex: status.internet == InternetState.offline ? 1 : 0,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: TabBar(
              indicatorColor: Theme.of(context).colorScheme.primary,
              labelColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(text: 'Minha Biblioteca'),
                Tab(icon: Icon(Icons.offline_pin_rounded), text: 'Baixados'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_LibraryCollectionScreen(), DownloadsScreen()],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LibraryCollectionScreen extends StatefulWidget {
  const _LibraryCollectionScreen();
  @override
  State<_LibraryCollectionScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<_LibraryCollectionScreen> {
  bool _checkingUpdates = false;
  bool _downloadingLibraryOffline = false;
  bool _searching = false;
  String _searchQuery = '';
  String _selectedFilterId = 'all'; // 'all', 'favorites', or list.id
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDownloadLibraryOffline(
    List<Manga> titles,
    ProfileAdaptivePalette palette,
  ) async {
    if (_downloadingLibraryOffline || titles.isEmpty) return;

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
                'Disponibilizar Biblioteca Offline?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Deseja baixar os capítulos das ${titles.length} obra(s) da sua Biblioteca para leitura offline?\n\n'
          'Todas as páginas serão salvas no seu aparelho para que você possa abrir e ler sua Biblioteca inteira mesmo sem internet.',
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
            label: Text('Baixar (${titles.length} obras)'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _downloadingLibraryOffline = true);

    AppFeedback.show(
      context,
      SnackBar(
        content: Text(
          'Iniciando download offline de ${titles.length} obra(s) da Biblioteca...',
        ),
      ),
    );

    int totalDownloadedChapters = 0;
    try {
      for (final manga in titles) {
        if (!mounted) break;
        try {
          List<Chapter> chapters = StorageService.getOfflineOrCachedChapters(
            manga.id,
          );
          if (chapters.isEmpty) {
            final bySource = await MangaDexService.discoverAllSourcesForManga(
              manga,
            );
            for (final list in bySource.values) {
              if (list.length > chapters.length) {
                chapters = list;
              }
            }
          }
          if (chapters.isNotEmpty) {
            totalDownloadedChapters += await DownloadManager.downloadManga(
              manga: manga,
              chapters: chapters,
              useDataSaver: StorageService.dataSaverEnabled,
            );
          }
        } catch (_) {}
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingLibraryOffline = false);
        AppFeedback.show(
          context,
          SnackBar(
            content: Text(
              'Biblioteca disponível offline ($totalDownloadedChapters capítulos baixados)!',
            ),
          ),
        );
      }
    }
  }

  Future<void> _checkUpdates() async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    var newChapters = 0;
    var failures = 0;
    // Explicit action only: no background polling or notification permission.
    final favorites = StorageService.getFavorites();
    for (final manga in favorites) {
      if (!mounted) break;
      try {
        newChapters += await FavoriteUpdatesService.checkFavorite(manga);
      } catch (_) {
        failures++;
      }
    }
    if (!mounted) return;
    setState(() => _checkingUpdates = false);
    AppFeedback.show(
      context,
      SnackBar(
        content: Text(
          failures > 0
              ? 'Verificação parcial: $newChapters capítulos novos; $failures obras indisponíveis.'
              : '$newChapters capítulos novos. Na primeira verificação, o histórico é inicializado.',
        ),
      ),
    );
  }

  Widget _buildReadingListRoll({
    required String title,
    required String subtitle,
    required List<Manga> items,
    required ProfileAdaptivePalette palette,
    required String heroPrefix,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white60,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: palette.secondary,
                  ),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Editar lista',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: Colors.white70,
                  ),
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Excluir lista',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.white54,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                'Nenhuma obra adicionada a esta lista ainda. Abra uma obra e toque no ícone de lista no topo para adicioná-la.',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
            )
          else
            SizedBox(
              height: 188,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final manga = items[index];
                  final pendingCount = FavoriteUpdatesService.pendingFor(
                    manga,
                  ).length;
                  return SizedBox(
                    width: 114,
                    child: Stack(
                      children: [
                        MangaGridCard(manga: manga, heroPrefix: heroPrefix),
                        if (pendingCount > 0)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$pendingCount novos',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return Scaffold(
          backgroundColor: YomiPalette.pitchBlack,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Identidade visual sutil e escura da Biblioteca (estante ao luar + pagode + livros YOMI)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: YomiMoonlitLibraryBackdropPainter(
                        accentColor: palette.primary,
                        secondaryColor: palette.secondary,
                        opacity: 0.18,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.46),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: ValueListenableBuilder<NsfwDisplayMode>(
                  valueListenable: StorageService.nsfwModeNotifier,
                  builder: (context, _, _) {
                    return ValueListenableBuilder(
                      valueListenable: StorageService.favBox.listenable(),
                      builder: (context, Box box, _) {
                        return ValueListenableBuilder(
                          valueListenable: StorageService.settingsBox
                              .listenable(),
                          builder: (context, Box settings, _) {
                            final allFavorites = StorageService.getFavorites();
                            final readingLists =
                                StorageService.getReadingLists();
                            final query = _searchQuery.trim().toLowerCase();

                            List<Manga> filterMangas(List<Manga> source) {
                              if (query.isEmpty) return source;
                              return source
                                  .where(
                                    (m) =>
                                        m.title.toLowerCase().contains(query),
                                  )
                                  .toList();
                            }

                            final favorites = filterMangas(allFavorites);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cabeçalho inspirado na referência visual da Biblioteca
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    12,
                                    14,
                                    6,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: double.infinity,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.local_library_rounded,
                                                  color: palette.primary,
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 8),
                                                const Flexible(
                                                  child: Text(
                                                    'Biblioteca',
                                                    style: TextStyle(
                                                      fontSize: 24,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Colors.white,
                                                      letterSpacing: -0.4,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Suas leituras em um só lugar.',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.white.withValues(
                                                  alpha: 0.68,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Wrap(
                                        alignment: WrapAlignment.end,
                                        children: [
                                          IconButton(
                                            tooltip: 'Buscar na biblioteca',
                                            icon: Icon(
                                              _searching
                                                  ? Icons.close_rounded
                                                  : Icons.search_rounded,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _searching = !_searching;
                                                if (!_searching) {
                                                  _searchCtrl.clear();
                                                  _searchQuery = '';
                                                }
                                              });
                                            },
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Criar nova lista de leitura',
                                            icon: Icon(
                                              Icons.playlist_add_rounded,
                                              color: palette.secondary,
                                            ),
                                            onPressed: () =>
                                                showCreateOrEditReadingListDialog(
                                                  context,
                                                ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Baixar Biblioteca para ler offline',
                                            onPressed:
                                                DeviceStateService
                                                        .instance
                                                        .isOffline ||
                                                    _downloadingLibraryOffline ||
                                                    (allFavorites.isEmpty &&
                                                        readingLists.isEmpty)
                                                ? null
                                                : () {
                                                    final uniqueTitles =
                                                        <String, Manga>{
                                                          for (final m
                                                              in allFavorites)
                                                            m.id: m,
                                                          for (final l
                                                              in readingLists)
                                                            for (final m
                                                                in l.mangas)
                                                              m.id: m,
                                                        }.values.toList();
                                                    _confirmAndDownloadLibraryOffline(
                                                      uniqueTitles,
                                                      palette,
                                                    );
                                                  },
                                            icon: _downloadingLibraryOffline
                                                ? SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color:
                                                              palette.primary,
                                                        ),
                                                  )
                                                : Icon(
                                                    Icons.downloading_rounded,
                                                    color: palette.primary,
                                                  ),
                                          ),
                                          IconButton(
                                            tooltip: 'Central de atualizações',
                                            icon: Badge(
                                              isLabelVisible:
                                                  FavoriteUpdatesService.allPending(
                                                    allFavorites,
                                                  ).isNotEmpty,
                                              backgroundColor: palette.primary,
                                              child: const Icon(
                                                Icons.notifications_outlined,
                                              ),
                                            ),
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const FavoriteUpdatesScreen(),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Verificar novos capítulos dos favoritos',
                                            onPressed:
                                                DeviceStateService
                                                        .instance
                                                        .isOffline ||
                                                    _checkingUpdates
                                                ? null
                                                : _checkUpdates,
                                            icon: _checkingUpdates
                                                ? SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color:
                                                              palette.primary,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons.sync_rounded,
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (_searching)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      4,
                                      16,
                                      8,
                                    ),
                                    child: TextField(
                                      controller: _searchCtrl,
                                      onChanged: (v) =>
                                          setState(() => _searchQuery = v),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Filtrar favoritos e listas...',
                                        prefixIcon: Icon(
                                          Icons.search_rounded,
                                          color: palette.secondary,
                                        ),
                                        filled: true,
                                        fillColor: palette.surface.withValues(
                                          alpha: 0.9,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide(
                                            color: palette.primary.withValues(
                                              alpha: 0.35,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // Chips de filtro: Tudo, Favoritos e Listas criadas pelo usuário
                                SizedBox(
                                  height: 40,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    children: [
                                      _buildFilterChip(
                                        id: 'all',
                                        label: 'Visão Geral',
                                        icon: Icons.auto_stories_rounded,
                                        palette: palette,
                                      ),
                                      const SizedBox(width: 8),
                                      _buildFilterChip(
                                        id: 'favorites',
                                        label:
                                            'Favoritos (${allFavorites.length})',
                                        icon: Icons.favorite_rounded,
                                        palette: palette,
                                      ),
                                      for (final list in readingLists) ...[
                                        const SizedBox(width: 8),
                                        _buildFilterChip(
                                          id: list.id,
                                          label:
                                              '${list.name} (${list.mangas.length})',
                                          icon: Icons.queue_music_rounded,
                                          palette: palette,
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      ActionChip(
                                        avatar: Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                          color: palette.secondary,
                                        ),
                                        label: const Text('Nova Lista'),
                                        backgroundColor: palette.surface
                                            .withValues(alpha: 0.8),
                                        side: BorderSide(
                                          color: palette.primary.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                        labelStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                        onPressed: () =>
                                            showCreateOrEditReadingListDialog(
                                              context,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child:
                                      (allFavorites.isEmpty &&
                                          readingLists.isEmpty)
                                      ? ListView(
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            20,
                                            20,
                                            110,
                                          ),
                                          children: [
                                            const YomiMascotCompanionCard(
                                              message:
                                                  'Sua estante ao luar está pronta! Favorita obras ou crie listas personalizadas para organizá-las aqui.',
                                            ),
                                            const SizedBox(height: 28),
                                            Container(
                                              padding: const EdgeInsets.all(24),
                                              decoration: BoxDecoration(
                                                color: palette.surface
                                                    .withValues(alpha: 0.72),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: palette.primary
                                                      .withValues(alpha: 0.28),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .favorite_border_rounded,
                                                    size: 54,
                                                    color: palette.secondary
                                                        .withValues(alpha: 0.6),
                                                  ),
                                                  const SizedBox(height: 14),
                                                  const Text(
                                                    'Sua biblioteca está vazia',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Toque no coração em qualquer Mangá, Manhwa ou HQ para salvá-la nos Favoritos, ou crie suas próprias listas de leitura.',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.65,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  FilledButton.icon(
                                                    style:
                                                        FilledButton.styleFrom(
                                                          backgroundColor:
                                                              palette.primary,
                                                          foregroundColor:
                                                              Colors.white,
                                                        ),
                                                    onPressed: () =>
                                                        showCreateOrEditReadingListDialog(
                                                          context,
                                                        ),
                                                    icon: const Icon(
                                                      Icons
                                                          .playlist_add_rounded,
                                                    ),
                                                    label: const Text(
                                                      'Criar primeira lista de leitura',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : _buildLibraryContent(
                                          favorites: favorites,
                                          readingLists: readingLists,
                                          filterMangas: filterMangas,
                                          palette: palette,
                                        ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String id,
    required String label,
    required IconData icon,
    required ProfileAdaptivePalette palette,
  }) {
    final selected = _selectedFilterId == id;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => setState(() => _selectedFilterId = id),
      avatar: Icon(
        icon,
        size: 15,
        color: selected ? Colors.white : palette.secondary,
      ),
      label: Text(label),
      selectedColor: palette.primary,
      backgroundColor: palette.surface.withValues(alpha: 0.82),
      side: BorderSide(
        color: selected
            ? palette.primary
            : Colors.white.withValues(alpha: 0.12),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : Colors.white70,
      ),
    );
  }

  Widget _buildLibraryContent({
    required List<Manga> favorites,
    required List<UserReadingList> readingLists,
    required List<Manga> Function(List<Manga>) filterMangas,
    required ProfileAdaptivePalette palette,
  }) {
    if (_selectedFilterId == 'favorites') {
      return _buildGridSection(
        items: favorites,
        palette: palette,
        heroPrefix: 'lib_fav',
        headerNote:
            'Toque no sino para verificar novidades. Segure em uma obra para adicioná-la a uma lista de leitura.',
      );
    }

    final selectedList = readingLists
        .where((l) => l.id == _selectedFilterId)
        .firstOrNull;
    if (selectedList != null) {
      final listItems = filterMangas(selectedList.mangas);
      return _buildGridSection(
        items: listItems,
        palette: palette,
        heroPrefix: 'lib_list_${selectedList.id}',
        headerNote: selectedList.description.isNotEmpty
            ? selectedList.description
            : 'Lista personalizada "${selectedList.name}".',
        trailingAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: () => showCreateOrEditReadingListDialog(
                context,
                existing: selectedList,
              ),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Editar'),
            ),
            TextButton.icon(
              onPressed: () async {
                await StorageService.deleteReadingList(selectedList.id);
                if (mounted) {
                  setState(() => _selectedFilterId = 'all');
                }
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Excluir'),
            ),
          ],
        ),
      );
    }

    // Visão Geral ('all'): Roll de Favoritos + Rolls de Listas de Leitura + Grade completa
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
      children: [
        _buildReadingListRoll(
          title: 'Obras Favoritas',
          subtitle: 'Suas obras marcadas com coração',
          items: favorites,
          palette: palette,
          heroPrefix: 'lib_roll_fav',
        ),
        for (final list in readingLists)
          _buildReadingListRoll(
            title: list.name,
            subtitle: list.description.isNotEmpty
                ? list.description
                : 'Lista de leitura personalizada',
            items: filterMangas(list.mangas),
            palette: palette,
            heroPrefix: 'lib_roll_${list.id}',
            onEdit: () =>
                showCreateOrEditReadingListDialog(context, existing: list),
            onDelete: () => StorageService.deleteReadingList(list.id),
          ),
        if (favorites.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            'Todos os Favoritos na Estante',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.62,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final manga = favorites[index];
              final count = FavoriteUpdatesService.pendingFor(manga).length;
              return Stack(
                children: [
                  MangaGridCard(manga: manga, heroPrefix: 'lib'),
                  if (count > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$count novos',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildGridSection({
    required List<Manga> items,
    required ProfileAdaptivePalette palette,
    required String heroPrefix,
    required String headerNote,
    Widget? trailingAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  headerNote,
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
              ?trailingAction,
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma obra encontrada neste filtro.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final manga = items[index];
                    final count = FavoriteUpdatesService.pendingFor(
                      manga,
                    ).length;
                    return Stack(
                      children: [
                        MangaGridCard(manga: manga, heroPrefix: heroPrefix),
                        if (count > 0)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count novos',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ============================================================================
// ABA 3: CAPÍTULOS OFFLINE
// ============================================================================
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  Future<void> _delete(BuildContext context, {Chapter? chapter}) async {
    final all = chapter == null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          all ? 'Apagar todos os downloads?' : 'Apagar este capítulo?',
        ),
        content: Text(
          all
              ? 'Os arquivos serão removidos do aparelho, incluindo downloads ocultos pelo filtro de conteúdo. Favoritos e progresso serão preservados.'
              : 'O capítulo ${chapter.chapterNumber} poderá ser baixado novamente. O progresso de leitura será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      if (all) {
        await DownloadManager.deleteAllDownloads();
      } else {
        await DownloadManager.deleteChapter(chapter.id);
      }
      if (!context.mounted) return;
      AppFeedback.show(
        context,
        SnackBar(
          content: Text(
            all ? 'Armazenamento offline limpo.' : 'Download removido.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      AppFeedback.show(
        context,
        const SnackBar(
          content: Text(
            'Não foi possível apagar. Aguarde os downloads e tente novamente.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Icon(
                  Icons.download_for_offline_rounded,
                  color: palette.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Capítulos salvos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Apagar todos os downloads',
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  color: palette.secondary,
                ),
                onPressed: () => _delete(context),
              ),
            ],
          ),
          body: ValueListenableBuilder<NsfwDisplayMode>(
            valueListenable: StorageService.nsfwModeNotifier,
            builder: (context, _, _) {
              return ValueListenableBuilder(
                valueListenable: StorageService.downloadsBox.listenable(),
                builder: (context, Box box, _) {
                  final items = StorageService.getAllDownloadedChapters();
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 64,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Nenhum capítulo disponível com os filtros atuais',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const YomiMascotCompanionCard(
                              message:
                                  'Baixe capítulos nas páginas das obras para ler mesmo sem internet!',
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final entry = items[index];
                      final manga = Manga.fromMap(
                        Map<String, dynamic>.from(entry['manga'] ?? {}),
                      );
                      final chapter = Chapter.fromMap(
                        Map<String, dynamic>.from(entry['chapter'] ?? {}),
                      );
                      final paths = StorageService.getDownloadedChapterPaths(
                        chapter.id,
                      );

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: YomiCoverImage(
                            manga: manga,
                            width: 48,
                            height: 68,
                          ),
                        ),
                        title: Text(
                          manga.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          'Cap. ${chapter.chapterNumber} (${chapter.language}) • ${paths.length} págs',
                          style: TextStyle(
                            color: palette.secondary,
                            fontSize: 12.5,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.white54,
                          ),
                          tooltip: 'Apagar capítulo',
                          onPressed: () => _delete(context, chapter: chapter),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReaderScreen(
                                manga: manga,
                                chapter: chapter,
                                allChapters:
                                    HomeOverviewScreen.buildSortedChapterList(
                                      manga,
                                      chapter,
                                    ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================================
// ABA 4: CONFIGURAÇÕES (CONTROLE DE CONTEÚDO ADULTO, LEITOR & BACKUP PERMANENTE)
// ============================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _showRestoreBackupModal() {
    final ctrl = TextEditingController();
    final palette = ProfilePaletteService.paletteNotifier.value;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restaurar Código de Backup YOMI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cole o backup para mesclar perfil, favoritos, listas, histórico e preferências. Imagens baixadas não são restauradas. O código não é criptografado.',
              style: TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Cole o código de backup aqui...',
                filled: true,
                fillColor: YomiPalette.pitchBlack,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: ctx,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Restaurar dados?'),
                      content: const Text(
                        'O backup será mesclado aos dados locais. '
                        'Itens com a mesma chave serão substituídos. '
                        'Salve um backup atual antes de continuar.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Restaurar'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !ctx.mounted) return;
                  final ok = await StorageService.importFullBackupJson(
                    ctrl.text,
                  );
                  if (!ctx.mounted) return;
                  AppFeedback.show(
                    ctx,
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Perfil, favoritos, listas e histórico mesclados com sucesso.'
                            : 'Backup inválido ou erro ao restaurar. Confira seus dados locais.',
                      ),
                    ),
                  );
                  if (ok) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Restaurar Agora'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Icon(Icons.settings_rounded, color: palette.primary),
                const SizedBox(width: 10),
                const Text('Configurações'),
              ],
            ),
          ),
          body: ValueListenableBuilder<NsfwDisplayMode>(
            valueListenable: StorageService.nsfwModeNotifier,
            builder: (context, nsfwMode, _) {
              return ValueListenableBuilder(
                valueListenable: StorageService.settingsBox.listenable(),
                builder: (context, Box settingsBox, _) {
                  final lockNsfwStartup = StorageService.lockNsfwOnStartup;
                  final hideZero = StorageService.hideZeroChapterTitles;
                  final dataSaver = StorageService.dataSaverEnabled;

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const AppearanceSettings(),
                      const SizedBox(height: 22),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Abrir o Perfil ao iniciar'),
                        subtitle: const Text(
                          'Desative para iniciar pela tela de leituras recentes.',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                        activeThumbColor: palette.primary,
                        value: StorageService
                            .profileNotifier
                            .value
                            .openOnProfileByDefault,
                        onChanged: (enabled) async {
                          final current = StorageService.profileNotifier.value;
                          await StorageService.updateUserProfile(
                            current.copyWith(openOnProfileByDefault: enabled),
                          );
                        },
                      ),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 10),
                      Text(
                        'Filtro de Conteúdo Sensível / Adulto (18+)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: palette.soft,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: palette.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Colors.white10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final mode in NsfwDisplayMode.values)
                              ListTile(
                                leading: Icon(
                                  nsfwMode == mode
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: nsfwMode == mode
                                      ? palette.primary
                                      : Colors.white54,
                                ),
                                title: Text(
                                  mode.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  mode.subtitle,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white60,
                                  ),
                                ),
                                onTap: () => StorageService.setNsfwMode(mode),
                              ),
                            const Divider(color: Colors.white10, height: 1),
                            SwitchListTile(
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Sempre iniciar com Conteúdo Adulto Desligado',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Garante que toda vez que o app for aberto, o modo 18+ volte automaticamente para Seguro (Oculto).',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                              value: lockNsfwStartup,
                              onChanged: (val) =>
                                  StorageService.setLockNsfwOnStartup(val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Catálogo & Leitor de Alta Performance',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: palette.soft,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: palette.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Colors.white10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SwitchListTile(
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Ocultar totalmente obras "Só Capa" (0 capítulos)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Ative para ocultar títulos sem capítulos confirmados nesta fonte.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                              value: hideZero,
                              onChanged: (val) =>
                                  StorageService.setHideZeroChapterTitles(val),
                            ),
                            const Divider(color: Colors.white10, height: 1),
                            SwitchListTile(
                              activeThumbColor: palette.primary,
                              title: const Text(
                                'Economia de Dados (Data Saver)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Prefere as páginas de menor tamanho oferecidas pela fonte, quando disponíveis.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                              value: dataSaver,
                              onChanged: (val) =>
                                  StorageService.setDataSaverEnabled(val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Backup Automático & Sincronização no Aparelho',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: palette.soft,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: palette.primary.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_done_rounded,
                                  color: palette.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Backup automático ativo no seu aparelho',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Seus favoritos, listas, perfil, mascote e histórico são salvos automaticamente no armazenamento persistente do telefone. Se você desinstalar e instalar o YOMI novamente, seus dados são restaurados automaticamente sem precisar colar códigos.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: palette.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () async {
                                      final ok =
                                          await StorageService.syncAutoBackupNow();
                                      if (!context.mounted) return;
                                      AppFeedback.show(
                                        context,
                                        SnackBar(
                                          content: Text(
                                            ok
                                                ? 'Backup automático atualizado no aparelho com sucesso!'
                                                : 'Adicione favoritos ou configure o perfil para salvar o backup no aparelho.',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.backup_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Salvar no Aparelho'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final restored =
                                          await StorageService.tryRestoreFromDeviceAutoBackup();
                                      if (!context.mounted) return;
                                      AppFeedback.show(
                                        context,
                                        SnackBar(
                                          content: Text(
                                            restored
                                                ? 'Dados restaurados automaticamente do aparelho!'
                                                : 'Nenhum backup salvo encontrado no aparelho.',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.settings_backup_restore_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Restaurar do Aparelho'),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 22),
                            const Row(
                              children: [
                                Icon(
                                  Icons.qr_code_rounded,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Exporte um backup antes de desinstalar (Opcional / Outro Celular)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final code =
                                          StorageService.exportFullBackupJson();
                                      await Clipboard.setData(
                                        ClipboardData(text: code),
                                      );
                                      if (!context.mounted) return;
                                      AppFeedback.show(
                                        context,
                                        const SnackBar(
                                          content: Text(
                                            'Código de Backup copiado para a área de transferência!',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.copy_all_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Copiar Código'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _showRestoreBackupModal,
                                    icon: const Icon(
                                      Icons.restore_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Colar Código'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================================
// CARD UNIFICADO COM TÍTULO SEMPRE VISÍVEL + PRETO E BRANCO PARA 0 CAPÍTULOS
// ============================================================================
class MangaGridCard extends StatefulWidget {
  final Manga manga;
  final String heroPrefix;

  const MangaGridCard({
    super.key,
    required this.manga,
    required this.heroPrefix,
  });

  @override
  State<MangaGridCard> createState() => _MangaGridCardState();
}

class _MangaGridCardState extends State<MangaGridCard> {
  bool _peekUnblurred = false;

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
  Widget build(BuildContext context) {
    final heroTag = '${widget.heroPrefix}_cover_${widget.manga.compositeId}';
    final titleKey = widget.manga.normalizedTitleKey;

    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return ValueListenableBuilder<NsfwDisplayMode>(
          valueListenable: StorageService.nsfwModeNotifier,
          builder: (context, nsfwMode, _) {
            return ValueListenableBuilder(
              valueListenable: StorageService.historyBox.listenable(
                keys: [
                  'chapters_count_${widget.manga.id}',
                  if (titleKey.isNotEmpty) 'chapters_count_title_$titleKey',
                ],
              ),
              builder: (context, Box historyBox, _) {
                final knownChapters = StorageService.getKnownChaptersCount(
                  widget.manga.id,
                  widget.manga.availableChaptersCount,
                  titleKey: titleKey,
                );
                final isCoverOnly = knownChapters == 0;
                final shouldBlur =
                    widget.manga.isNsfw &&
                    nsfwMode == NsfwDisplayMode.blurred &&
                    !_peekUnblurred;

                Widget coverImage = YomiCoverImage(
                  manga: widget.manga,
                  highRes: false,
                );
                if (isCoverOnly) {
                  coverImage = ColorFiltered(
                    colorFilter: _grayscaleFilter,
                    child: coverImage,
                  );
                }

                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MangaDetailScreen(
                        manga: widget.manga,
                        heroTag: heroTag,
                      ),
                    ),
                  ),
                  onLongPress: widget.manga.isNsfw
                      ? () => setState(() => _peekUnblurred = true)
                      : () => showAddMangaToReadingListSheet(
                          context,
                          widget.manga,
                        ),
                  onLongPressEnd: widget.manga.isNsfw
                      ? (_) => setState(() => _peekUnblurred = false)
                      : null,
                  onLongPressCancel: widget.manga.isNsfw
                      ? () => setState(() => _peekUnblurred = false)
                      : null,
                  child: Opacity(
                    opacity: isCoverOnly ? 0.62 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Hero(
                            tag: heroTag,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  coverImage,
                                  if (shouldBlur)
                                    BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 14,
                                        sigmaY: 14,
                                      ),
                                      child: Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.45,
                                        ),
                                        alignment: Alignment.center,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.visibility_off_rounded,
                                              color: palette.secondary,
                                              size: 22,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '18+ Segure p/ ver',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: palette.soft,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  // Se tiver apenas a capa (0 capítulos), mostra faixa discreta
                                  if (isCoverOnly)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.78,
                                        ),
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
                                  // Indicador discreto de capítulos baixados offline
                                  ValueListenableBuilder(
                                    valueListenable: StorageService.downloadsBox
                                        .listenable(),
                                    builder: (context, Box dlBox, _) {
                                      final dlCount =
                                          StorageService.countDownloadedChaptersForManga(
                                            widget.manga.id,
                                          );
                                      if (dlCount <= 0) {
                                        return const SizedBox.shrink();
                                      }
                                      return Positioned(
                                        top: 6,
                                        left: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.78,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: palette.secondary
                                                  .withValues(alpha: 0.55),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.offline_pin_rounded,
                                                size: 10,
                                                color: palette.secondary,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                '$dlCount',
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: palette.soft,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // Coração se estiver nos favoritos
                                  ValueListenableBuilder(
                                    valueListenable: StorageService.favBox
                                        .listenable(keys: [widget.manga.id]),
                                    builder: (context, Box box, _) {
                                      if (!StorageService.isFavorite(
                                        widget.manga.id,
                                      )) {
                                        return const SizedBox.shrink();
                                      }
                                      return Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.75,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.favorite_rounded,
                                            size: 13,
                                            color: palette.primary,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 30,
                          child: Text(
                            widget.manga.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: isCoverOnly
                                  ? Colors.white54
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
