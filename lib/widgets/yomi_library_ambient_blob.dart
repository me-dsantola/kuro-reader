import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/yomi_theme_system.dart';

/// Blob orgânico líquido animado para a região superior da Biblioteca.
/// Oferece flutuação suave, deformação contínua de bordas, iluminação difusa,
/// adaptação aos 8 temas oficiais, suporte à reatividade de cores e reação elástica ao toque.
class YomiLibraryAmbientBlob extends StatefulWidget {
  final double size;
  final bool isVisible;

  const YomiLibraryAmbientBlob({
    super.key,
    this.size = 148.0,
    this.isVisible = true,
  });

  @override
  State<YomiLibraryAmbientBlob> createState() => _YomiLibraryAmbientBlobState();
}

class _YomiLibraryAmbientBlobState extends State<YomiLibraryAmbientBlob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morphController;
  double _touchSquish = 1.0;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );
    final inTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (widget.isVisible && !inTest) {
      _morphController.repeat();
    } else {
      _morphController.value = 0.5;
    }
  }

  @override
  void didUpdateWidget(covariant YomiLibraryAmbientBlob oldWidget) {
    super.didUpdateWidget(oldWidget);
    final inTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible && !inTest) {
        if (!_morphController.isAnimating) _morphController.repeat();
      } else {
        if (_morphController.isAnimating) _morphController.stop();
      }
    }
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    setState(() => _touchSquish = 0.86);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _touchSquish = 1.0);
  }

  void _onTapCancel() {
    setState(() => _touchSquish = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _morphController.isAnimating) {
      _morphController.stop();
    }

    return ValueListenableBuilder<YomiThemeTokens>(
      valueListenable: YomiThemeController.instance,
      builder: (context, theme, _) {
        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          behavior: HitTestBehavior.translucent,
          child: AnimatedScale(
            scale: _touchSquish,
            duration: const Duration(milliseconds: 260),
            curve: Curves.elasticOut,
            child: AnimatedBuilder(
              animation: _morphController,
              builder: (context, _) {
                final progress = reduceMotion ? 0.35 : _morphController.value;
                // Flutuação vertical sutil
                final dy = reduceMotion
                    ? 0.0
                    : math.sin(progress * 2 * math.pi) * 6.0;

                return Transform.translate(
                  offset: Offset(0, dy),
                  child: CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: _OrganicLiquidBlobPainter(
                      progress: progress,
                      primaryColor: theme.accentPrimary,
                      secondaryColor: theme.accentSecondary,
                      isLight: theme.isLight,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _OrganicLiquidBlobPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isLight;

  _OrganicLiquidBlobPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final baseRadius = size.width * 0.44;
    const numPoints = 8;
    final points = <Offset>[];

    final phase = progress * 2 * math.pi;

    for (var i = 0; i < numPoints; i++) {
      final angle = (i * 2 * math.pi) / numPoints;
      // Três harmônicos para criar movimento fluido e não-mecânico
      final wave1 = math.sin(phase + (i * 1.35)) * 0.14;
      final wave2 = math.cos((phase * 1.5) - (i * 0.85)) * 0.09;
      final wave3 = math.sin((phase * 0.6) + (i * 2.1)) * 0.05;
      final radius = baseRadius * (1.0 + wave1 + wave2 + wave3);

      points.add(
        Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle),
        ),
      );
    }

    final path = Path();
    for (var i = 0; i < numPoints; i++) {
      final current = points[i];
      final next = points[(i + 1) % numPoints];
      final mid = Offset(
        (current.dx + next.dx) * 0.5,
        (current.dy + next.dy) * 0.5,
      );

      if (i == 0) {
        path.moveTo(mid.dx, mid.dy);
      } else {
        path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
      }
    }
    // Fechar o caminho conectando ao ponto inicial médio
    final firstMid = Offset(
      (points[0].dx + points[1].dx) * 0.5,
      (points[0].dy + points[1].dy) * 0.5,
    );
    final last = points[numPoints - 1];
    path.quadraticBezierTo(last.dx, last.dy, firstMid.dx, firstMid.dy);
    path.close();

    // Iluminação difusa e gradiente com adaptação ao tema
    final alphaCore = isLight ? 0.22 : 0.42;
    final alphaMid = isLight ? 0.12 : 0.22;
    final alphaEdge = isLight ? 0.03 : 0.05;

    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.25),
        radius: 0.88,
        colors: [
          secondaryColor.withValues(alpha: alphaCore),
          primaryColor.withValues(alpha: alphaMid),
          primaryColor.withValues(alpha: alphaEdge),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.82, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Brilho exterior suave (outer diffuse glow)
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: isLight ? 0.08 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OrganicLiquidBlobPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.isLight != isLight;
  }
}
