import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../blobatar/flutter.dart' as blob;
import '../models/manga_models.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';

class BlobatarShapeOption {
  final String id;
  final String label;
  final double? traitAt;

  const BlobatarShapeOption(this.id, this.label, this.traitAt);
}

class BlobatarExpressionOption {
  final String id;
  final String label;
  final blob.Expression expression;

  const BlobatarExpressionOption(this.id, this.label, this.expression);
}

const List<BlobatarShapeOption> kBlobatarShapes = [
  BlobatarShapeOption('auto', 'Auto', null),
  BlobatarShapeOption('round', 'Redondo', 0.11),
  BlobatarShapeOption('organic', 'Orgânico', 0.35),
  BlobatarShapeOption('boxy', 'Bloco', 0.54),
  BlobatarShapeOption('capsule', 'Cápsula', 0.65),
  BlobatarShapeOption('nub', 'Broto', 0.745),
  BlobatarShapeOption('cloud', 'Nuvem', 0.825),
  BlobatarShapeOption('droplet', 'Gota', 0.888),
  BlobatarShapeOption('hexagon', 'Hexágono', 0.933),
  BlobatarShapeOption('sun', 'Sol', 0.965),
  BlobatarShapeOption('triangle', 'Triângulo', 0.99),
];

const List<BlobatarExpressionOption> kBlobatarExpressions = [
  BlobatarExpressionOption('happy', 'Feliz', blob.happy),
  BlobatarExpressionOption('idle', 'Calmo', blob.idle),
  BlobatarExpressionOption('love', 'Amor', blob.love),
  BlobatarExpressionOption('wink', 'Piscada', blob.wink),
  BlobatarExpressionOption('smug', 'Confiante', blob.smug),
  BlobatarExpressionOption('surprised', 'Surpreso', blob.surprised),
  BlobatarExpressionOption('thinking', 'Pensando', blob.thinking),
  BlobatarExpressionOption('shy', 'Tímido', blob.shy),
  BlobatarExpressionOption('sleepy', 'Sonolento', blob.sleepy),
  BlobatarExpressionOption('sad', 'Triste', blob.sad),
  BlobatarExpressionOption('mad', 'Bravo', blob.mad),
  BlobatarExpressionOption('unsure', 'Dúvida', blob.unsure),
  BlobatarExpressionOption('scared', 'Assustado', blob.scared),
  BlobatarExpressionOption('sick', 'Enjoado', blob.sick),
];

const List<double> kBlobatarHues = [12, 40, 78, 140, 190, 225, 275, 320];

BlobatarShapeOption blobatarShapeById(String id) => kBlobatarShapes.firstWhere(
  (s) => s.id == id,
  orElse: () => kBlobatarShapes.first,
);

BlobatarExpressionOption blobatarExpressionById(String id) =>
    kBlobatarExpressions.firstWhere(
      (e) => e.id == id,
      orElse: () => kBlobatarExpressions.first,
    );

blob.Backdrop blobatarBackdropById(String id) {
  switch (id) {
    case 'none':
      return blob.Backdrop.none;
    case 'square':
      return blob.Backdrop.square;
    case 'squircle':
      return blob.Backdrop.squircle;
    case 'circle':
    default:
      return blob.Backdrop.circle;
  }
}

blob.BlobatarOptions buildBlobatarOptionsForProfile(
  UserProfile profile, {
  blob.Expression? overrideExpression,
  double? adaptiveHue,
  blob.Backdrop? overrideBackdrop,
}) {
  final shape = blobatarShapeById(profile.blobatarShape);
  final expr =
      overrideExpression ??
      blobatarExpressionById(profile.blobatarExpression).expression;
  final backdrop =
      overrideBackdrop ?? blobatarBackdropById(profile.blobatarBackground);
  double? effectiveHue = profile.blobatarHue;
  if (effectiveHue != null && effectiveHue < 0) {
    effectiveHue = adaptiveHue;
  }
  return blob.BlobatarOptions(
    background: backdrop,
    hue: effectiveHue,
    expression: expr,
    traits: shape.traitAt == null
        ? null
        : <String, Object>{'shape': shape.traitAt!},
  );
}

class YomiProfileBlobatar extends StatefulWidget {
  final UserProfile profile;
  final double size;
  final double? adaptiveHue;
  final bool interactiveCycleOnTap;
  final blob.Backdrop? overrideBackdrop;
  final String? overrideExpressionId;

  const YomiProfileBlobatar({
    super.key,
    required this.profile,
    this.size = 64,
    this.adaptiveHue,
    this.interactiveCycleOnTap = false,
    this.overrideBackdrop,
    this.overrideExpressionId,
  });

  @override
  State<YomiProfileBlobatar> createState() => _YomiProfileBlobatarState();
}

class _YomiProfileBlobatarState extends State<YomiProfileBlobatar> {
  int? _cycledIndex;

  void _cycleExpression() {
    setState(() {
      final currentId =
          widget.overrideExpressionId ?? widget.profile.blobatarExpression;
      final baseIdx = kBlobatarExpressions.indexWhere((e) => e.id == currentId);
      final idx = _cycledIndex ?? (baseIdx >= 0 ? baseIdx : 0);
      _cycledIndex = (idx + 1) % kBlobatarExpressions.length;
    });
  }

  @override
  void didUpdateWidget(covariant YomiProfileBlobatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.blobatarExpression !=
        widget.profile.blobatarExpression) {
      _cycledIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final overrideExpr = _cycledIndex != null
        ? kBlobatarExpressions[_cycledIndex!].expression
        : (widget.overrideExpressionId != null
              ? blobatarExpressionById(widget.overrideExpressionId!).expression
              : null);
    final options = buildBlobatarOptionsForProfile(
      widget.profile,
      overrideExpression: overrideExpr,
      adaptiveHue: widget.adaptiveHue,
      overrideBackdrop: widget.overrideBackdrop,
    );
    final seed = widget.profile.effectiveBlobatarSeed;
    final isTestBinding = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('Test');
    final child = widget.profile.blobatarAnimated
        ? blob.AnimatedBlobatar(
            name: seed.isEmpty ? 'kuroyomi' : seed,
            size: widget.size,
            animation: blob.BlobatarAnimation.always,
            active: !isTestBinding,
            options: options,
            semanticLabel:
                'Mascote ${widget.profile.effectiveBlobatarName} de ${widget.profile.name}',
          )
        : blob.Blobatar(
            name: seed.isEmpty ? 'kuroyomi' : seed,
            size: widget.size,
            options: options,
            semanticLabel:
                'Mascote ${widget.profile.effectiveBlobatarName} de ${widget.profile.name}',
          );

    if (!widget.interactiveCycleOnTap) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _cycleExpression,
      child: child,
    );
  }
}

class YomiProfileAvatarView extends StatelessWidget {
  final UserProfile profile;
  final double size;
  final Color borderColor;
  final double borderWidth;
  final double? adaptiveHue;
  final VoidCallback? onTap;

  const YomiProfileAvatarView({
    super.key,
    required this.profile,
    this.size = 44,
    this.borderColor = const Color(0xFFE11D48),
    this.borderWidth = 2.0,
    this.adaptiveHue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final provider = ProfilePaletteService.resolveImageProvider(
      profile.avatarImagePath,
    );
    final showCustomPhoto = provider != null && !profile.useBlobatarAsAvatar;

    final avatarBox = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF14141C),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.28),
            blurRadius: size * 0.2,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: showCustomPhoto
            ? Image(
                image: provider,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => YomiProfileBlobatar(
                  profile: profile,
                  size: size,
                  adaptiveHue: adaptiveHue,
                  interactiveCycleOnTap: onTap == null,
                ),
              )
            : YomiProfileBlobatar(
                profile: profile,
                size: size,
                adaptiveHue: adaptiveHue,
                interactiveCycleOnTap: onTap == null,
              ),
      ),
    );

    if (onTap == null) return avatarBox;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: avatarBox,
    );
  }
}

/// Companion widget that embeds the user's named Blobatar mascot across screens
/// (End of Chapter, Home, Library, Downloads, Manga Details).
class YomiMascotCompanionCard extends StatelessWidget {
  final String message;
  final String? subtitle;
  final String? overrideExpressionId;
  final VoidCallback? onTap;
  final bool compact;

  const YomiMascotCompanionCard({
    super.key,
    required this.message,
    this.subtitle,
    this.overrideExpressionId,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        StorageService.profileNotifier,
        ProfilePaletteService.paletteNotifier,
      ]),
      builder: (context, _) {
        final profile = StorageService.profileNotifier.value;
        final palette = ProfilePaletteService.paletteNotifier.value;
        final mascotName = profile.effectiveBlobatarName;

        return Material(
          color: palette.surfaceTint.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
            side: BorderSide(color: palette.primary.withValues(alpha: 0.32)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap:
                onTap ??
                () => showYomiProfileAndBlobatarEditor(
                  context,
                  profile,
                  initialTab: 0,
                ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 14,
                vertical: compact ? 8 : 11,
              ),
              child: Row(
                children: [
                  YomiProfileBlobatar(
                    profile: profile,
                    size: compact ? 36 : 44,
                    adaptiveHue: palette.hue,
                    overrideExpressionId: overrideExpressionId,
                    interactiveCycleOnTap: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primary.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                mascotName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: palette.soft,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: compact ? 12 : 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Renders either a custom image banner (file/network/memory) or a built-in YOMI artistic preset.
class YomiBannerBackdrop extends StatelessWidget {
  final String? bannerPath;
  final ProfileAdaptivePalette palette;

  const YomiBannerBackdrop({
    super.key,
    required this.bannerPath,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final provider = ProfilePaletteService.resolveImageProvider(bannerPath);
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildArtisticFallback(),
      );
    }
    return _buildArtisticFallback();
  }

  Widget _buildArtisticFallback() {
    final preset = findBannerPreset(bannerPath);
    final primary = preset?.seedColor ?? palette.primary;
    final secondary = preset?.secondaryColor ?? palette.secondary;

    if (preset?.id == 'preset:moonlit_library') {
      return CustomPaint(
        painter: YomiMoonlitLibraryBackdropPainter(
          accentColor: primary,
          secondaryColor: secondary,
          opacity: 1.0,
        ),
      );
    }
    if (preset?.id == 'preset:seinen_eyes') {
      return CustomPaint(
        painter: _SeinenMangaPanelsBannerPainter(
          accentColor: primary,
          secondaryColor: secondary,
        ),
      );
    }
    return CustomPaint(
      painter: YomiToriiHorizonBannerPainter(
        accentColor: primary,
        secondaryColor: secondary,
      ),
    );
  }
}

class YomiToriiHorizonBannerPainter extends CustomPainter {
  final Color accentColor;
  final Color secondaryColor;

  const YomiToriiHorizonBannerPainter({
    this.accentColor = const Color(0xFFE11D48),
    this.secondaryColor = const Color(0xFFF472B6),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final darkBase = Color.lerp(const Color(0xFF070709), accentColor, 0.24)!;
    final midTone = Color.lerp(const Color(0xFF121217), accentColor, 0.34)!;
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [const Color(0xFF070709), darkBase, midTone],
    );
    canvas.drawRect(rect, Paint()..shader = bgGradient.createShader(rect));

    final sunCenter = Offset(size.width * 0.77, size.height * 0.56);
    final sunGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor.withValues(alpha: 0.75),
          accentColor.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: 92));
    canvas.drawCircle(sunCenter, 92, sunGlow);

    canvas.drawCircle(
      sunCenter,
      36,
      Paint()..color = accentColor.withValues(alpha: 0.90),
    );

    final hillPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.58,
        size.width * 0.65,
        size.height * 0.74,
      )
      ..quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.84,
        size.width,
        size.height * 0.66,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      hillPath,
      Paint()..color = const Color(0xFF070709).withValues(alpha: 0.90),
    );

    final toriiPaint = Paint()
      ..color = const Color(0xFF070709)
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

    final sakuraPaint = Paint()
      ..color = secondaryColor.withValues(alpha: 0.62);
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
  bool shouldRepaint(covariant YomiToriiHorizonBannerPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.secondaryColor != secondaryColor;
}

class _SeinenMangaPanelsBannerPainter extends CustomPainter {
  final Color accentColor;
  final Color secondaryColor;

  const _SeinenMangaPanelsBannerPainter({
    required this.accentColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF08080C));

    final panelBorder = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Manga panel dividers
    final leftRect = Rect.fromLTWH(
      size.width * 0.14,
      12,
      size.width * 0.36,
      size.height - 24,
    );
    final rightRect = Rect.fromLTWH(
      size.width * 0.52,
      12,
      size.width * 0.34,
      size.height - 24,
    );
    canvas.drawRect(
      leftRect,
      Paint()..color = const Color(0xFF14141C),
    );
    canvas.drawRect(
      rightRect,
      Paint()..color = const Color(0xFF101018),
    );
    canvas.drawRect(leftRect, panelBorder);
    canvas.drawRect(rightRect, panelBorder);

    // Glowing crimson/adaptive iris in left panel (matching Mockup 2)
    final eyeCenter = Offset(
      leftRect.left + leftRect.width * 0.52,
      leftRect.top + leftRect.height * 0.45,
    );
    canvas.drawOval(
      Rect.fromCenter(center: eyeCenter, width: 64, height: 28),
      Paint()..color = const Color(0xFF070709),
    );
    canvas.drawCircle(
      eyeCenter,
      11,
      Paint()..color = accentColor.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      eyeCenter,
      4.5,
      Paint()..color = const Color(0xFF050507),
    );
    canvas.drawCircle(
      eyeCenter.translate(-3, -3),
      2,
      Paint()..color = secondaryColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SeinenMangaPanelsBannerPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.secondaryColor != secondaryColor;
}

/// Subtle visual identity painter inspired by the Library reference image:
/// Moonlit window with crimson/adaptive full moon, distant Japanese pagoda,
/// bookshelf with manga spines, stacked YOMI books on desk, and sakura petals.
class YomiMoonlitLibraryBackdropPainter extends CustomPainter {
  final Color accentColor;
  final Color secondaryColor;
  final double opacity;

  const YomiMoonlitLibraryBackdropPainter({
    this.accentColor = const Color(0xFFE11D48),
    this.secondaryColor = const Color(0xFFF472B6),
    this.opacity = 0.48,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final skyDark = Color.lerp(
      const Color(0xFF070709),
      accentColor,
      0.26 * opacity,
    )!;
    final skyGlow = Color.lerp(
      const Color(0xFF0F080D),
      accentColor,
      0.42 * opacity,
    )!;

    // 1. Night window sky gradient on the right half
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [skyGlow, skyDark, const Color(0xFF070709)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // 2. Glowing Full Moon through the window
    final moonCenter = Offset(size.width * 0.76, size.height * 0.30);
    final moonRadius = (size.width * 0.17).clamp(38.0, 78.0);
    canvas.drawCircle(
      moonCenter,
      moonRadius * 1.9,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accentColor.withValues(alpha: 0.42 * opacity),
            accentColor.withValues(alpha: 0.12 * opacity),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: moonCenter, radius: moonRadius * 1.9),
        ),
    );
    canvas.drawCircle(
      moonCenter,
      moonRadius,
      Paint()..color = accentColor.withValues(alpha: 0.68 * opacity),
    );

    // 3. Distant Japanese Pagoda silhouette below the moon
    final pagodaPaint = Paint()
      ..color = const Color(0xFF060508).withValues(alpha: 0.88 * opacity);
    final px = size.width * 0.85;
    final py = size.height * 0.56;
    for (int tier = 0; tier < 3; tier++) {
      final w = (36.0 - tier * 8.0);
      final y = py - tier * 15.0;
      final roof = Path()
        ..moveTo(px - w, y)
        ..quadraticBezierTo(px, y - 10, px + w, y)
        ..lineTo(px + w * 0.72, y + 6)
        ..lineTo(px - w * 0.72, y + 6)
        ..close();
      canvas.drawPath(roof, pagodaPaint);
    }
    // Spire
    canvas.drawLine(
      Offset(px, py - 44),
      Offset(px, py - 58),
      Paint()
        ..color = pagodaPaint.color
        ..strokeWidth = 2,
    );

    // 4. Window frame bars
    final framePaint = Paint()
      ..color = const Color(0xFF050507).withValues(alpha: 0.85 * opacity)
      ..strokeWidth = 4;
    canvas.drawLine(
      Offset(size.width * 0.53, 0),
      Offset(size.width * 0.53, size.height * 0.76),
      framePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.53, size.height * 0.72),
      Offset(size.width, size.height * 0.72),
      framePaint,
    );

    // 5. Left Perspective Bookshelf & Manga Spines
    final shelfPaint = Paint()
      ..color = const Color(0xFF0A0609).withValues(alpha: 0.92 * opacity);
    final shelfHighlight = Paint()
      ..color = accentColor.withValues(alpha: 0.22 * opacity)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    // Shelf planks in slight perspective
    for (final ratio in [0.26, 0.48, 0.70]) {
      final plank = Path()
        ..moveTo(0, size.height * (ratio - 0.04))
        ..lineTo(size.width * 0.48, size.height * ratio)
        ..lineTo(size.width * 0.48, size.height * (ratio + 0.018))
        ..lineTo(0, size.height * (ratio - 0.022))
        ..close();
      canvas.drawPath(plank, shelfPaint);
      canvas.drawLine(
        Offset(0, size.height * (ratio - 0.04)),
        Offset(size.width * 0.48, size.height * ratio),
        shelfHighlight,
      );
    }

    // Manga volume spines on shelves
    final spinePaint = Paint()
      ..color = Color.lerp(
        const Color(0xFF12090E),
        accentColor,
        0.18,
      )!.withValues(alpha: 0.75 * opacity);
    for (int i = 0; i < 8; i++) {
      final left = 10.0 + i * (size.width * 0.052);
      final top = size.height * (0.50 + i * 0.004);
      final h = size.height * 0.16;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, size.width * 0.042, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, spinePaint);
      canvas.drawRRect(r, shelfHighlight);
    }

    // 6. Stacked YOMI books on the reading desk at bottom-center
    final deskTop = size.height * 0.76;
    final book1 = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.26, deskTop - 32, size.width * 0.42, 15),
      const Radius.circular(3),
    );
    final book2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.24, deskTop - 16, size.width * 0.45, 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(book1, spinePaint);
    canvas.drawRRect(book1, shelfHighlight);
    canvas.drawRRect(book2, spinePaint);
    canvas.drawRRect(book2, shelfHighlight);

    // 7. Falling Sakura Petals
    final petalPaint = Paint()
      ..color = secondaryColor.withValues(alpha: 0.65 * opacity);
    final petals = [
      Offset(size.width * 0.62, size.height * 0.18),
      Offset(size.width * 0.84, size.height * 0.16),
      Offset(size.width * 0.61, size.height * 0.42),
      Offset(size.width * 0.60, size.height * 0.58),
      Offset(size.width * 0.90, size.height * 0.52),
      Offset(size.width * 0.14, size.height * 0.84),
      Offset(size.width * 0.40, size.height * 0.82),
    ];
    for (final p in petals) {
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(-0.35);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 10, height: 5.5),
        petalPaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant YomiMoonlitLibraryBackdropPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor ||
      oldDelegate.secondaryColor != secondaryColor ||
      oldDelegate.opacity != opacity;
}

Color _blobatarHueColor(double hue) {
  return HSVColor.fromAHSV(1.0, hue % 360.0, 0.78, 0.92).toColor();
}

Future<void> showYomiProfileAndBlobatarEditor(
  BuildContext context,
  UserProfile current, {
  int initialTab = 0,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF121217),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => _ProfileAndBlobatarEditorSheet(
      current: current,
      initialTab: initialTab,
    ),
  );
}

class _ProfileAndBlobatarEditorSheet extends StatefulWidget {
  final UserProfile current;
  final int initialTab;

  const _ProfileAndBlobatarEditorSheet({
    required this.current,
    required this.initialTab,
  });

  @override
  State<_ProfileAndBlobatarEditorSheet> createState() =>
      _ProfileAndBlobatarEditorSheetState();
}

class _ProfileAndBlobatarEditorSheetState
    extends State<_ProfileAndBlobatarEditorSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _genreCtrl;
  late final TextEditingController _blobatarNameCtrl;
  late final TextEditingController _seedCtrl;
  late final TextEditingController _avatarUrlCtrl;
  late final TextEditingController _bannerUrlCtrl;

  late bool _useBlobatarAsAvatar;
  late String _blobatarShape;
  late String _blobatarExpression;
  late double? _blobatarHue;
  late String _blobatarBackground;
  late bool _blobatarAnimated;
  late int? _customAccentColor;
  ProfileAdaptivePalette _livePalette = const ProfileAdaptivePalette();

  static const List<String> _popularGenres = [
    'Ação',
    'Fantasia',
    'Romance',
    'Seinen',
    'Shounen',
    'Sobrenatural',
    'Isekai',
    'Sci-Fi',
    'Esportes',
    'Mistério',
    'Terror',
    'Comédia',
    'Drama',
    'Slice of Life',
  ];

  static const List<int> _accentSwatches = [
    0xFFE11D48, // Enso Red
    0xFFF472B6, // Sakura Pink
    0xFF8B5CF6, // Violet
    0xFF02A9FF, // Cyan Blue
    0xFF10B981, // Emerald
    0xFFF59E0B, // Amber
    0xFFEC4899, // Magenta
    0xFFEF4444, // Crimson
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    final c = widget.current;
    _nameCtrl = TextEditingController(text: c.name);
    _bioCtrl = TextEditingController(text: c.bio);
    _genreCtrl = TextEditingController(text: c.favoriteGenre);
    _blobatarNameCtrl = TextEditingController(text: c.effectiveBlobatarName);
    _seedCtrl = TextEditingController(
      text: c.blobatarSeed.isEmpty ? c.name : c.blobatarSeed,
    );
    _avatarUrlCtrl = TextEditingController(text: c.avatarImagePath ?? '');
    _bannerUrlCtrl = TextEditingController(text: c.bannerImagePath ?? '');
    _useBlobatarAsAvatar = c.useBlobatarAsAvatar;
    _blobatarShape = c.blobatarShape;
    _blobatarExpression = c.blobatarExpression;
    _blobatarHue = c.blobatarHue;
    _blobatarBackground = c.blobatarBackground;
    _blobatarAnimated = c.blobatarAnimated;
    _customAccentColor = c.customAccentColor;
    _refreshLivePalette();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _genreCtrl.dispose();
    _blobatarNameCtrl.dispose();
    _seedCtrl.dispose();
    _avatarUrlCtrl.dispose();
    _bannerUrlCtrl.dispose();
    super.dispose();
  }

  UserProfile _buildDraft() {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Kuroyomi'
        : _nameCtrl.text.trim();
    final mascotName = _blobatarNameCtrl.text.trim().isEmpty
        ? 'Kuro'
        : _blobatarNameCtrl.text.trim();
    final avatarPath = _avatarUrlCtrl.text.trim();
    final bannerPath = _bannerUrlCtrl.text.trim();
    return widget.current.copyWith(
      name: name,
      bio: _bioCtrl.text.trim().isEmpty
          ? 'Mais histórias, menos realidade.'
          : _bioCtrl.text.trim(),
      favoriteGenre: _genreCtrl.text.trim().isEmpty
          ? 'Ação, Fantasia, Romance, Seinen'
          : _genreCtrl.text.trim(),
      avatarImagePath: avatarPath.isEmpty ? null : avatarPath,
      clearAvatarImage: avatarPath.isEmpty,
      bannerImagePath: bannerPath.isEmpty ? null : bannerPath,
      clearBannerImage: bannerPath.isEmpty,
      useBlobatarAsAvatar: _useBlobatarAsAvatar,
      blobatarName: mascotName,
      blobatarSeed: _seedCtrl.text.trim(),
      blobatarShape: _blobatarShape,
      blobatarExpression: _blobatarExpression,
      blobatarHue: _blobatarHue,
      clearBlobatarHue: _blobatarHue == null,
      blobatarBackground: _blobatarBackground,
      blobatarAnimated: _blobatarAnimated,
      customAccentColor: _customAccentColor,
      clearCustomAccentColor: _customAccentColor == null,
      isConfigured: true,
    );
  }

  Future<void> _autoPersistDraft() async {
    final draft = _buildDraft();
    await StorageService.updateUserProfile(draft);
    await _refreshLivePalette();
  }

  Future<void> _refreshLivePalette() async {
    final draft = _buildDraft();
    final resolved = await ProfilePaletteService.resolveForProfile(draft);
    if (mounted) {
      setState(() => _livePalette = resolved);
    }
  }

  void _randomizeBlobatar() {
    final rng = math.Random();
    const seeds = [
      'kuroyomi',
      'sakura-spirit',
      'ronin-enso',
      'kitsune-moon',
      'cyber-shogun',
      'torii-wanderer',
      'akira-pulse',
      'shinobi-star',
      'amaterasu',
      'tsukuyomi',
    ];
    setState(() {
      _seedCtrl.text = '${seeds[rng.nextInt(seeds.length)]}-${rng.nextInt(99)}';
      _blobatarShape =
          kBlobatarShapes[1 + rng.nextInt(kBlobatarShapes.length - 1)].id;
      _blobatarExpression =
          kBlobatarExpressions[rng.nextInt(kBlobatarExpressions.length)].id;
      _blobatarHue = kBlobatarHues[rng.nextInt(kBlobatarHues.length)];
    });
    _autoPersistDraft();
  }

  void _toggleGenreTag(String genre) {
    final currentTags = _genreCtrl.text
        .split(RegExp(r'[,•·&/]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (currentTags.any((t) => t.toLowerCase() == genre.toLowerCase())) {
      currentTags.removeWhere((t) => t.toLowerCase() == genre.toLowerCase());
    } else {
      currentTags.add(genre);
    }
    setState(() {
      _genreCtrl.text = currentTags.join(', ');
    });
  }

  Future<void> _pickDeviceImage({required bool isBanner}) async {
    final picked = await ProfileImagePicker.pickLocalImage(
      slot: isBanner ? 'banner' : 'avatar',
    );
    if (!mounted) return;
    if (picked == null || picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma imagem selecionada do dispositivo. Você também pode escolher um tema artístico ou capa abaixo.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (isBanner) {
        _bannerUrlCtrl.text = picked;
      } else {
        _avatarUrlCtrl.text = picked;
        _useBlobatarAsAvatar = false;
      }
    });
    await _autoPersistDraft();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBanner
                ? 'Banner atualizado com sucesso!'
                : 'Foto de perfil atualizada com sucesso!',
          ),
        ),
      );
    }
  }

  List<Manga> _availableMangaCovers() {
    final seen = <String>{};
    final result = <Manga>[];
    for (final m in StorageService.getFavorites()) {
      if (seen.add(m.id) && m.getRawCoverUrl(highRes: true).isNotEmpty) {
        result.add(m);
      }
    }
    for (final item in StorageService.getContinueReadingList()) {
      final m = item['manga'];
      if (m is Manga &&
          seen.add(m.id) &&
          m.getRawCoverUrl(highRes: true).isNotEmpty) {
        result.add(m);
      }
    }
    for (final list in StorageService.getReadingLists()) {
      for (final m in list.mangas) {
        if (seen.add(m.id) && m.getRawCoverUrl(highRes: true).isNotEmpty) {
          result.add(m);
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final draft = _buildDraft();
    final accent = _livePalette.primary;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: accent, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Personalizar Perfil & Mascote',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    await StorageService.updateUserProfile(_buildDraft());
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Salvar',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(
                icon: Icon(Icons.face_retouching_natural_rounded, size: 18),
                text: 'Mascote Blobatar',
              ),
              Tab(
                icon: Icon(Icons.wallpaper_rounded, size: 18),
                text: 'Foto & Banner',
              ),
              Tab(
                icon: Icon(Icons.badge_outlined, size: 18),
                text: 'Identidade',
              ),
            ],
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBlobatarStudioTab(draft, accent),
                _buildPhotoAndBannerTab(draft, accent),
                _buildIdentityTab(draft, accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlobatarStudioTab(UserProfile draft, Color accent) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // Live Blobatar Stage
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_livePalette.bannerDark, const Color(0xFF15151E)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '${draft.effectiveBlobatarName.toUpperCase()} • ${blobatarExpressionById(_blobatarExpression).label.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: _livePalette.soft,
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _randomizeBlobatar,
                    icon: Icon(Icons.casino_rounded, size: 18, color: accent),
                    label: Text(
                      'Sortear',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              YomiProfileBlobatar(
                profile: draft,
                size: 118,
                adaptiveHue: _livePalette.hue,
                interactiveCycleOnTap: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'Toque no mascote para testar as reações ao vivo!',
                style: TextStyle(fontSize: 11.5, color: Colors.white60),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: accent,
                title: const Text(
                  'Usar Blobatar como foto principal do perfil',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Se desativado, sua foto personalizada fica no círculo principal e o Blobatar acompanha como mascote no perfil.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white60),
                ),
                value: _useBlobatarAsAvatar,
                onChanged: (val) {
                  setState(() => _useBlobatarAsAvatar = val);
                  _autoPersistDraft();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Mascot Name Input
        TextField(
          controller: _blobatarNameCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Nome do seu Mascote (Blobatar)',
            helperText:
                'Seu companheiro aparecerá ao fim dos capítulos e nas páginas do app',
            prefixIcon: Icon(Icons.pets_rounded, color: accent),
            filled: true,
            fillColor: const Color(0xFF070709),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),

        // Seed Input
        TextField(
          controller: _seedCtrl,
          onChanged: (_) {
            setState(() {});
            _refreshLivePalette();
          },
          decoration: InputDecoration(
            labelText: 'Semente (Seed) do Mascote',
            helperText:
                'Qualquer palavra gera uma criatura única e determinística',
            prefixIcon: Icon(Icons.fingerprint_rounded, color: accent),
            filled: true,
            fillColor: const Color(0xFF070709),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 20),

        // Expression Picker
        const Text(
          'Expressão do Mascote',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: kBlobatarExpressions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (context, idx) {
            final item = kBlobatarExpressions[idx];
            final selected = item.id == _blobatarExpression;
            final previewProfile = draft.copyWith(blobatarExpression: item.id);
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                setState(() => _blobatarExpression = item.id);
                _autoPersistDraft();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.2)
                      : const Color(0xFF0A0A0E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? accent : Colors.white10,
                    width: selected ? 1.6 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    blob.Blobatar(
                      name: draft.effectiveBlobatarSeed.isEmpty
                          ? 'kuroyomi'
                          : draft.effectiveBlobatarSeed,
                      size: 46,
                      options: buildBlobatarOptionsForProfile(
                        previewProfile,
                        adaptiveHue: _livePalette.hue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: selected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 22),

        // Shape / Silhouette Picker
        const Text(
          'Formato / Silhueta',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: kBlobatarShapes.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (context, idx) {
            final item = kBlobatarShapes[idx];
            final selected = item.id == _blobatarShape;
            final previewProfile = draft.copyWith(blobatarShape: item.id);
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                setState(() => _blobatarShape = item.id);
                _autoPersistDraft();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.2)
                      : const Color(0xFF0A0A0E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? accent : Colors.white10,
                    width: selected ? 1.6 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    blob.Blobatar(
                      name: draft.effectiveBlobatarSeed.isEmpty
                          ? 'kuroyomi'
                          : draft.effectiveBlobatarSeed,
                      size: 46,
                      options: buildBlobatarOptionsForProfile(
                        previewProfile,
                        adaptiveHue: _livePalette.hue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: selected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 22),

        // Hue Picker
        const Text(
          'Cor do Mascote (Matiz)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Auto (Seed)'),
              selected: _blobatarHue == null,
              selectedColor: accent.withValues(alpha: 0.28),
              onSelected: (_) {
                setState(() => _blobatarHue = null);
                _autoPersistDraft();
              },
            ),
            ChoiceChip(
              label: const Text('Cor da Foto'),
              selected: _blobatarHue != null && _blobatarHue! < 0,
              selectedColor: accent.withValues(alpha: 0.28),
              onSelected: (_) {
                setState(() => _blobatarHue = -1);
                _autoPersistDraft();
              },
            ),
            for (final double hue in kBlobatarHues)
              GestureDetector(
                onTap: () {
                  setState(() => _blobatarHue = hue);
                  _autoPersistDraft();
                },
                child: Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: _blobatarHue == hue
                        ? Border.all(color: Colors.white, width: 2.2)
                        : Border.all(color: Colors.white24),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blobatarHueColor(hue),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),

        // Backdrop & Motion
        const Text(
          'Moldura de Fundo do Mascote',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'circle', label: Text('Círculo')),
            ButtonSegment(value: 'squircle', label: Text('Squircle')),
            ButtonSegment(value: 'square', label: Text('Quadrado')),
            ButtonSegment(value: 'none', label: Text('Livre')),
          ],
          selected: {_blobatarBackground},
          showSelectedIcon: false,
          onSelectionChanged: (sel) {
            setState(() => _blobatarBackground = sel.first);
            _autoPersistDraft();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: accent,
          title: const Text(
            'Animação viva (respirar, piscar e olhar)',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          value: _blobatarAnimated,
          onChanged: (v) {
            setState(() => _blobatarAnimated = v);
            _autoPersistDraft();
          },
        ),
      ],
    );
  }

  Widget _buildPhotoAndBannerTab(UserProfile draft, Color accent) {
    final libraryCovers = _availableMangaCovers();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // 1. LIVE BANNER + AVATAR PREVIEW CARD
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 144,
            child: Stack(
              fit: StackFit.expand,
              children: [
                YomiBannerBackdrop(
                  bannerPath: draft.bannerImagePath,
                  palette: _livePalette,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        const Color(0xFF070709).withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Row(
                    children: [
                      YomiProfileAvatarView(
                        profile: draft,
                        size: 58,
                        borderColor: accent,
                        adaptiveHue: _livePalette.hue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              draft.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Prévia ao vivo do Banner, Foto e Tema Global',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _livePalette.soft,
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
        const SizedBox(height: 20),

        // 2. CURATED BANNER PRESETS (1-TAP RELIABLE BANNER SELECTION)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Banners Artísticos YOMI (1 toque)',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
            ),
            if (_bannerUrlCtrl.text.trim().isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() => _bannerUrlCtrl.clear());
                  _autoPersistDraft();
                },
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text('Padrão'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kYomiBannerPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final preset = kYomiBannerPresets[index];
              final isSelected = _bannerUrlCtrl.text.trim() == preset.id;
              return GestureDetector(
                onTap: () {
                  setState(() => _bannerUrlCtrl.text = preset.id);
                  _autoPersistDraft();
                },
                child: Container(
                  width: 142,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? Colors.white : preset.seedColor,
                      width: isSelected ? 2.2 : 1.0,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      YomiBannerBackdrop(
                        bannerPath: preset.id,
                        palette: ProfileAdaptivePalette.fromColor(
                          preset.seedColor,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.82),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 6,
                        child: Row(
                          children: [
                            if (isSelected) ...[
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                preset.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 22),

        // 3. CUSTOM BANNER FROM DEVICE OR URL
        const Text(
          'Adicionar Imagem Própria para o Banner',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            backgroundColor: accent.withValues(alpha: 0.24),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
          onPressed: () => _pickDeviceImage(isBanner: true),
          icon: const Icon(Icons.wallpaper_rounded, size: 18),
          label: const Text('Escolher Imagem de Banner do Dispositivo'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bannerUrlCtrl,
          onChanged: (_) {
            setState(() {});
            _autoPersistDraft();
          },
          decoration: InputDecoration(
            labelText: 'URL ou Caminho do Banner',
            hintText: 'Cole um link https://... ou caminho de arquivo de imagem',
            prefixIcon: Icon(Icons.panorama_outlined, color: accent),
            suffixIcon: _bannerUrlCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      setState(() => _bannerUrlCtrl.clear());
                      _autoPersistDraft();
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF070709),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),

        const SizedBox(height: 24),

        // 4. CUSTOM PROFILE PHOTO SECTION
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Foto de Perfil Personalizada',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
            if (_avatarUrlCtrl.text.trim().isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _avatarUrlCtrl.clear();
                    _useBlobatarAsAvatar = true;
                  });
                  _autoPersistDraft();
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Usar Blobatar'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            backgroundColor: accent.withValues(alpha: 0.22),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
          onPressed: () => _pickDeviceImage(isBanner: false),
          icon: const Icon(Icons.photo_library_rounded, size: 18),
          label: const Text('Escolher Foto de Perfil do Dispositivo'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _avatarUrlCtrl,
          onChanged: (val) {
            setState(() {
              if (val.trim().isNotEmpty) _useBlobatarAsAvatar = false;
            });
            _autoPersistDraft();
          },
          decoration: InputDecoration(
            labelText: 'URL ou Caminho da Foto de Perfil',
            hintText: 'https://... ou caminho local da imagem',
            prefixIcon: Icon(Icons.account_circle_outlined, color: accent),
            suffixIcon: _avatarUrlCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      setState(() {
                        _avatarUrlCtrl.clear();
                        _useBlobatarAsAvatar = true;
                      });
                      _autoPersistDraft();
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF070709),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),

        // 5. LIBRARY COVERS WITH EXPLICIT 1-TAP "Foto" & "Banner" BUTTONS
        if (libraryCovers.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Usar Arte da sua Biblioteca ou Leituras',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Escolha se deseja aplicar a capa na Foto de Perfil ou no Banner:',
            style: TextStyle(fontSize: 11.5, color: Colors.white60),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: libraryCovers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final m = libraryCovers[idx];
                final rawUrl = m.getRawCoverUrl(highRes: true);
                return Container(
                  width: 104,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Image.network(
                          yomiSafeImageUrl(rawUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFF1A1A24),
                            child: const Icon(Icons.image_outlined),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _avatarUrlCtrl.text = rawUrl;
                                  _useBlobatarAsAvatar = false;
                                });
                                _autoPersistDraft();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                alignment: Alignment.center,
                                color: accent.withValues(alpha: 0.22),
                                child: const Text(
                                  'Foto',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 24, color: Colors.white12),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _bannerUrlCtrl.text = rawUrl;
                                });
                                _autoPersistDraft();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                alignment: Alignment.center,
                                color: _livePalette.secondary.withValues(
                                  alpha: 0.22,
                                ),
                                child: const Text(
                                  'Banner',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
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
              },
            ),
          ),
        ],

        const SizedBox(height: 24),
        const Text(
          'Tema de Cores Global (Todas as Páginas + Logo YOMI)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Adaptar à Foto / Banner (Auto)'),
              selected: _customAccentColor == null,
              selectedColor: accent.withValues(alpha: 0.28),
              onSelected: (_) {
                setState(() => _customAccentColor = null);
                _autoPersistDraft();
              },
            ),
            for (final int colorValue in _accentSwatches)
              GestureDetector(
                onTap: () {
                  setState(() => _customAccentColor = colorValue);
                  _autoPersistDraft();
                },
                child: Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: _customAccentColor == colorValue
                        ? Border.all(color: Colors.white, width: 2.2)
                        : Border.all(color: Colors.white24),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(colorValue),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdentityTab(UserProfile draft, Color accent) {
    final activeGenres = _genreCtrl.text
        .split(RegExp(r'[,•·&/]'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        TextField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Nome / Codinome no YOMI',
            prefixIcon: Icon(Icons.person_rounded, color: accent),
            filled: true,
            fillColor: const Color(0xFF070709),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _bioCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Frase / Assinatura do Perfil',
            hintText: 'Mais histórias, menos realidade.',
            prefixIcon: Icon(Icons.format_quote_rounded, color: accent),
            filled: true,
            fillColor: const Color(0xFF070709),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _genreCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Gêneros Favoritos (separados por vírgula)',
            prefixIcon: Icon(Icons.local_offer_outlined, color: accent),
            filled: true,
            fillColor: const Color(0xFF070709),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Toque para adicionar ou remover gêneros favoritos:',
          style: TextStyle(fontSize: 12.5, color: Colors.white70),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _popularGenres.map((genre) {
            final isSelected = activeGenres.contains(genre.toLowerCase());
            return FilterChip(
              label: Text(genre),
              selected: isSelected,
              selectedColor: accent.withValues(alpha: 0.25),
              checkmarkColor: Colors.white,
              side: BorderSide(color: isSelected ? accent : Colors.white12),
              onSelected: (_) => _toggleGenreTag(genre),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// First-run Onboarding Screen where the user creates their profile, names their
/// Blobatar mascot, and configures their preferences (genres & privacy protection).
class FirstTimeProfileOnboardingScreen extends StatefulWidget {
  final VoidCallback? onCompleted;

  const FirstTimeProfileOnboardingScreen({super.key, this.onCompleted});

  @override
  State<FirstTimeProfileOnboardingScreen> createState() =>
      _FirstTimeProfileOnboardingScreenState();
}

class _FirstTimeProfileOnboardingScreenState
    extends State<FirstTimeProfileOnboardingScreen> {
  final TextEditingController _nameCtrl = TextEditingController(
    text: 'Kuroyomi',
  );
  final TextEditingController _bioCtrl = TextEditingController(
    text: 'Mais histórias, menos realidade.',
  );
  final TextEditingController _mascotNameCtrl = TextEditingController(
    text: 'Kuro',
  );

  final String _blobatarShape = 'round';
  String _blobatarExpression = 'happy';
  double? _blobatarHue;
  String? _avatarPath;
  final String _bannerPath = kYomiBannerPresets.first.id;
  final bool _useBlobatarAsAvatar = true;
  bool _privacyProtection = true;
  final Set<String> _selectedGenres = {'Ação', 'Fantasia', 'Romance', 'Seinen'};
  ProfileAdaptivePalette _palette = ProfileAdaptivePalette.defaultEnso;

  static const List<String> _genreOptions = [
    'Ação',
    'Fantasia',
    'Romance',
    'Seinen',
    'Shounen',
    'Sobrenatural',
    'Isekai',
    'Sci-Fi',
    'Esportes',
    'Mistério',
    'Terror',
    'Comédia',
  ];

  @override
  void initState() {
    super.initState();
    _updatePalette();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _mascotNameCtrl.dispose();
    super.dispose();
  }

  UserProfile _buildProfile() {
    final cleanName = _nameCtrl.text.trim().isEmpty
        ? 'Kuroyomi'
        : _nameCtrl.text.trim();
    final cleanMascot = _mascotNameCtrl.text.trim().isEmpty
        ? 'Kuro'
        : _mascotNameCtrl.text.trim();
    final genres = _selectedGenres.isEmpty
        ? 'Ação, Fantasia, Seinen'
        : _selectedGenres.join(', ');
    return UserProfile(
      name: cleanName,
      bio: _bioCtrl.text.trim().isEmpty
          ? 'Mais histórias, menos realidade.'
          : _bioCtrl.text.trim(),
      favoriteGenre: genres,
      isConfigured: true,
      avatarImagePath: _avatarPath,
      bannerImagePath: _bannerPath,
      useBlobatarAsAvatar: _useBlobatarAsAvatar,
      blobatarName: cleanMascot,
      blobatarSeed: '$cleanName-$cleanMascot',
      blobatarShape: _blobatarShape,
      blobatarExpression: _blobatarExpression,
      blobatarHue: _blobatarHue,
      blobatarBackground: 'circle',
      blobatarAnimated: true,
    );
  }

  Future<void> _updatePalette() async {
    final p = await ProfilePaletteService.resolveForProfile(_buildProfile());
    if (mounted) {
      setState(() => _palette = p);
    }
  }

  Future<void> _finishOnboarding() async {
    final profile = _buildProfile();
    await StorageService.setPrivacyProtectionEnabled(_privacyProtection);
    await StorageService.updateUserProfile(profile);
    await ProfilePaletteService.refreshGlobalPalette(profile);
    widget.onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _buildProfile();
    final accent = _palette.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF070709),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: accent, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Bem-vindo ao YOMI',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Configure seu perfil, dê um nome ao seu mascote Blobatar e defina suas preferências iniciais.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 18),

            // Live Banner & Mascot Preview
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 176,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    YomiBannerBackdrop(
                      bannerPath: _bannerPath,
                      palette: _palette,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.2),
                            const Color(0xFF070709).withValues(alpha: 0.92),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: Row(
                        children: [
                          YomiProfileAvatarView(
                            profile: draft,
                            size: 74,
                            borderColor: accent,
                            adaptiveHue: _palette.hue,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  draft.name,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Mascote: ${draft.effectiveBlobatarName}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _palette.soft,
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
            const SizedBox(height: 20),

            // 1. Perfil & Mascote Name
            const Text(
              '1. Seu Perfil & Nome do Mascote',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) {
                setState(() {});
                _updatePalette();
              },
              decoration: InputDecoration(
                labelText: 'Seu Nome ou Apelido',
                prefixIcon: Icon(Icons.person_rounded, color: accent),
                filled: true,
                fillColor: const Color(0xFF121217),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mascotNameCtrl,
              onChanged: (_) {
                setState(() {});
                _updatePalette();
              },
              decoration: InputDecoration(
                labelText: 'Nome do seu Mascote (Blobatar)',
                helperText:
                    'Seu companheiro acompanhará suas leituras e o fim dos capítulos',
                prefixIcon: Icon(Icons.pets_rounded, color: accent),
                filled: true,
                fillColor: const Color(0xFF121217),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Sua Frase / Bio do Perfil',
                prefixIcon: Icon(Icons.format_quote_rounded, color: accent),
                filled: true,
                fillColor: const Color(0xFF121217),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 2. Expressão e Estilo do Mascote
            const Text(
              '2. Personalize seu Blobatar',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 68,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kBlobatarExpressions.take(8).length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final expr = kBlobatarExpressions[index];
                  final selected = _blobatarExpression == expr.id;
                  return ChoiceChip(
                    label: Text(expr.label),
                    selected: selected,
                    selectedColor: accent.withValues(alpha: 0.26),
                    onSelected: (_) =>
                        setState(() => _blobatarExpression = expr.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),

            // 3. Gêneros Favoritos
            const Text(
              '3. Seus Gêneros Favoritos',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _genreOptions.map((g) {
                final selected = _selectedGenres.contains(g);
                return FilterChip(
                  label: Text(g),
                  selected: selected,
                  selectedColor: accent.withValues(alpha: 0.25),
                  checkmarkColor: Colors.white,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedGenres.add(g);
                      } else if (_selectedGenres.length > 1) {
                        _selectedGenres.remove(g);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            // 4. Proteção de Privacidade
            const Text(
              '4. Privacidade',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121217),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: SwitchListTile.adaptive(
                activeThumbColor: accent,
                title: const Text(
                  'Ativar Proteção de Privacidade',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                subtitle: const Text(
                  'Oculta a tela do aplicativo ao alternar entre apps. Você pode alterar isso depois nas Configurações.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                value: _privacyProtection,
                onChanged: (v) => setState(() => _privacyProtection = v),
              ),
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _finishOnboarding,
              icon: const Icon(Icons.rocket_launch_rounded),
              label: const Text(
                'Concluir e Entrar no YOMI',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog to create a new custom Reading List (or rename an existing one).
Future<UserReadingList?> showCreateOrEditReadingListDialog(
  BuildContext context, {
  UserReadingList? existing,
  Manga? initialManga,
}) async {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final descCtrl = TextEditingController(text: existing?.description ?? '');
  final selectedMangas = <String, Manga>{
    if (existing != null)
      for (final m in existing.mangas) m.id: m,
    ?initialManga?.id: ?initialManga,
  };

  final candidatePool = <String, Manga>{};
  for (final m in StorageService.getFavorites()) {
    candidatePool[m.id] = m;
  }
  for (final item in StorageService.getContinueReadingList()) {
    final m = item['manga'];
    if (m is Manga) candidatePool[m.id] = m;
  }
  if (initialManga != null) {
    candidatePool[initialManga.id] = initialManga;
  }

  final palette = ProfilePaletteService.paletteNotifier.value;

  return showDialog<UserReadingList>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setModalState) => AlertDialog(
        backgroundColor: const Color(0xFF14141C),
        title: Text(
          existing == null ? 'Nova Lista de Leitura' : 'Editar Lista',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nome da Lista',
                  hintText: 'Ex: Para Ler Depois, Melhores Seinen...',
                  prefixIcon: Icon(
                    Icons.playlist_add_rounded,
                    color: palette.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: 'Descrição (opcional)',
                  hintText: 'Suas notas sobre esta coleção',
                  prefixIcon: Icon(
                    Icons.notes_rounded,
                    color: palette.secondary,
                  ),
                ),
              ),
              if (candidatePool.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Selecionar obras para incluir na lista:',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: candidatePool.values.map((m) {
                    final isPicked = selectedMangas.containsKey(m.id);
                    return FilterChip(
                      label: Text(
                        m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: isPicked,
                      selectedColor: palette.primary.withValues(alpha: 0.25),
                      onSelected: (v) {
                        setModalState(() {
                          if (v) {
                            selectedMangas[m.id] = m;
                          } else {
                            selectedMangas.remove(m.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.primary),
            onPressed: () async {
              final name = nameCtrl.text.trim().isEmpty
                  ? 'Minha Lista'
                  : nameCtrl.text.trim();
              final desc = descCtrl.text.trim();
              UserReadingList saved;
              if (existing == null) {
                saved = await StorageService.createReadingList(
                  name,
                  description: desc,
                  initialMangas: selectedMangas.values.toList(),
                );
              } else {
                saved = existing.copyWith(
                  name: name,
                  description: desc,
                  mangas: selectedMangas.values.toList(),
                );
                await StorageService.saveReadingList(saved);
              }
              if (dialogCtx.mounted) Navigator.pop(dialogCtx, saved);
            },
            child: const Text('Salvar Lista'),
          ),
        ],
      ),
    ),
  );
}

/// Bottom sheet to add/remove a specific Manga across the user's Favorites and custom Reading Lists.
Future<void> showAddMangaToReadingListSheet(
  BuildContext context,
  Manga manga,
) async {
  final palette = ProfilePaletteService.paletteNotifier.value;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF14141C),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (context, setSheetState) {
        final isFav = StorageService.isFavorite(manga.id);
        final lists = StorageService.getReadingLists();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Salvar "${manga.title}" em...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: isFav,
                  activeColor: palette.primary,
                  secondary: Icon(
                    Icons.favorite_rounded,
                    color: isFav ? palette.primary : Colors.white54,
                  ),
                  title: const Text(
                    'Obras Favoritas',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Sua lista principal de favoritos no Perfil e Biblioteca',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  onChanged: (_) async {
                    await StorageService.toggleFavorite(manga);
                    setSheetState(() {});
                  },
                ),
                const Divider(color: Colors.white10),
                for (final list in lists)
                  CheckboxListTile(
                    value: StorageService.isMangaInReadingList(
                      list.id,
                      manga.id,
                    ),
                    activeColor: palette.primary,
                    secondary: Icon(
                      Icons.bookmarks_rounded,
                      color: palette.secondary,
                    ),
                    title: Text(
                      list.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${list.mangas.length} obra(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                    onChanged: (_) async {
                      await StorageService.toggleMangaInReadingList(
                        list.id,
                        manga,
                      );
                      setSheetState(() {});
                    },
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: palette.primary),
                  ),
                  onPressed: () async {
                    await showCreateOrEditReadingListDialog(
                      context,
                      initialManga: manga,
                    );
                    setSheetState(() {});
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar Nova Lista de Leitura'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
