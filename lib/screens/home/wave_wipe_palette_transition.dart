import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'featured_preload_controller.dart';

/// Desenha a transição "wave wipe": uma onda progressiva que revela a próxima paleta
/// em sincronia com o progresso [progress] (0.0 -> 1.0).
class WaveWipeClipper extends CustomClipper<Path> {
  final double progress;
  final double waveAmplitude;
  final double waveFrequency;
  final bool leftToRight;

  const WaveWipeClipper({
    required this.progress,
    this.waveAmplitude = 28.0,
    this.waveFrequency = 2.2,
    this.leftToRight = true,
  });

  @override
  Path getClip(Size size) {
    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0.0) return Path();
    if (clamped >= 1.0) {
      return Path()..addRect(Offset.zero & size);
    }
    final path = Path();
    final spread = size.width + waveAmplitude * 2;
    final baseX = leftToRight
        ? -waveAmplitude + spread * clamped
        : size.width + waveAmplitude - spread * clamped;

    if (leftToRight) {
      path.moveTo(0, 0);
      path.lineTo(baseX, 0);
      const steps = 32;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final y = size.height * t;
        final waveOffset = math.sin((t * waveFrequency + clamped) * math.pi * 2) *
            waveAmplitude *
            math.sin(clamped * math.pi);
        path.lineTo(baseX + waveOffset, y);
      }
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(baseX, 0);
      const steps = 32;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final y = size.height * t;
        final waveOffset = math.sin((t * waveFrequency + clamped) * math.pi * 2) *
            waveAmplitude *
            math.sin(clamped * math.pi);
        path.lineTo(baseX - waveOffset, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant WaveWipeClipper oldClipper) {
    return oldClipper.progress != progress || oldClipper.leftToRight != leftToRight;
  }
}

class WaveWipeBackground extends StatelessWidget {
  final FeaturedPalette previousPalette;
  final FeaturedPalette targetPalette;
  final Animation<double> animation;
  final bool reduceMotion;
  final bool leftToRight;

  const WaveWipeBackground({
    super.key,
    required this.previousPalette,
    required this.targetPalette,
    required this.animation,
    this.reduceMotion = false,
    this.leftToRight = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(animation.value);
        if (reduceMotion) {
          // Transição simples para economia de bateria / acessibilidade
          final blended = FeaturedPalette.lerp(previousPalette, targetPalette, t);
          return ColoredBox(color: blended.navBackground);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    previousPalette.primary.withOpacity(0.22),
                    previousPalette.navBackground,
                  ],
                ),
              ),
            ),
            ClipPath(
              clipper: WaveWipeClipper(
                progress: t,
                leftToRight: leftToRight,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      targetPalette.primary.withOpacity(0.22),
                      targetPalette.navBackground,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
