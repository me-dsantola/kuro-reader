import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/device_state_service.dart';
import '../services/mangadex_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../screens/manga_detail_screen.dart';

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
    if (!kIsWeb) {
      final localCoverPath =
          StorageService.getOfflineCoverPath(widget.manga.id);
      if (localCoverPath != null) {
        final file = File(localCoverPath);
        if (file.existsSync()) {
          return Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
          );
        }
      }
    }

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
      cacheWidth: (() {
        final logicalWidth = widget.width ??
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
  final ProfileAdaptivePalette? palette;
  final bool showEmblem;
  const YomiEnsoLogo({
    super.key,
    this.fontSize = 23,
    this.palette,
    this.showEmblem = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, globalPalette, _) {
        final active = palette ?? globalPalette;
        final textColor = active.readableOnSurface;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showEmblem) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(fontSize * 0.3),
                child: Image.asset(
                  'assets/images/yomi_logo.png',
                  width: fontSize * 1.2,
                  height: fontSize * 1.2,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              'Y',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: textColor,
                decoration: TextDecoration.none,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: CustomPaint(
                size: Size(fontSize * 0.86, fontSize * 0.86),
                painter: _EnsoOPainter(color: active.primary),
              ),
            ),
            Text(
              'MI',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: textColor,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        );
      },
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
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
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
                final isCoverOnly =
                    StorageService.isConfirmedZeroChapters(widget.manga);
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
                  child: Semantics(
                    button: true,
                    label: isCoverOnly
                        ? '${widget.manga.title} — 0 capítulos disponíveis'
                        : widget.manga.title,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Hero(
                              tag: heroTag,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Opacity(
                                    opacity: isCoverOnly ? 0.62 : 1.0,
                                    child: coverImage,
                                  ),
                                  // Blur NSFW
                                  if (shouldBlur)
                                    Positioned.fill(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: 14,
                                          sigmaY: 14,
                                        ),
                                        child: Container(
                                          color: Colors.black.withValues(
                                            alpha: 0.35,
                                          ),
                                          child: Center(
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.visibility_off_rounded,
                                                color: Colors.white,
                                              ),
                                              tooltip: 'Espiar capa',
                                              onPressed: () {
                                                setState(
                                                  () => _peekUnblurred = true,
                                                );
                                                Future.delayed(
                                                  const Duration(seconds: 4),
                                                  () {
                                                    if (mounted) {
                                                      setState(
                                                        () =>
                                                            _peekUnblurred =
                                                                false,
                                                      );
                                                    }
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Badge de 0 capítulos
                                  if (isCoverOnly)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.82,
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
