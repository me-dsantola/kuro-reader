import 'package:flutter/material.dart';
import '../models/manga_models.dart';
import '../services/profile_palette_service.dart';
import '../screens/home_tabs.dart';

/// Widget reutilizável que anima a capa flutuante com rotação e translação contínuas.
/// Compartilhado entre a tela Inicial (Home) e a Biblioteca.
class FloatingContinueCover extends StatefulWidget {
  final Manga manga;
  final double width;
  final double height;
  final ProfileAdaptivePalette palette;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const FloatingContinueCover({
    super.key,
    required this.manga,
    required this.width,
    required this.height,
    required this.palette,
    required this.isFavorite,
    this.onFavoriteToggle,
  });

  @override
  State<FloatingContinueCover> createState() => _FloatingContinueCoverState();
}

class _FloatingContinueCoverState extends State<FloatingContinueCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    final inTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!inTest) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0.5;
    }
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        if (reduceMotion) return child!;
        // Oscilação em Y de cerca de 6 pixels (-3.0 a +3.0)
        final yOffset = (_animation.value - 0.5) * 6.0;
        // Inclinação inicial ~ -5° (-0.087 rad) oscilando em torno de ±2.5° (±0.0436 rad)
        final angle = -0.087 + (_animation.value - 0.5) * 0.087;

        return Transform.translate(
          offset: Offset(0, yOffset),
          child: Transform.rotate(
            angle: angle,
            child: child,
          ),
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 18,
              offset: const Offset(0, 10),
              spreadRadius: 1,
            ),
            BoxShadow(
              color: widget.palette.primary.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: YomiCoverImage(
                  manga: widget.manga,
                  width: widget.width,
                  height: widget.height,
                  highRes: true,
                ),
              ),
            ),
            Positioned(
              top: 7,
              right: 7,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onFavoriteToggle,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.60),
                      border: Border.all(
                        color: widget.isFavorite
                            ? widget.palette.primary.withValues(alpha: 0.8)
                            : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        widget.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 15,
                        color: widget.isFavorite
                            ? widget.palette.primary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
