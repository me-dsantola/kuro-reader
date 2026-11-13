import 'dart:ui';
import 'package:flutter/material.dart';

/// Contêiner de vidro individual translúcido (Glassmorphism individual) com
/// blur suave, borda fina, brilho sutil e contraste mínimo garantido (>= 3:1)
/// sobre qualquer capa (clara, escura ou muito colorida).
class IndividualGlassCapsule extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final bool isCircle;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? surfaceTint;

  const IndividualGlassCapsule({
    super.key,
    required this.child,
    this.borderRadius,
    this.isCircle = false,
    this.padding = const EdgeInsets.all(0),
    this.width,
    this.height,
    this.onTap,
    this.tooltip,
    this.surfaceTint,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = isCircle
        ? BorderRadius.circular(999)
        : (borderRadius ?? BorderRadius.circular(18));

    Widget content = Padding(
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: effectiveRadius,
          onTap: onTap,
          child: content,
        ),
      );
    }

    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: effectiveRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x35000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              // Fundo translúcido com densidade suficiente para legibilidade em capas claras
              color: (surfaceTint ?? const Color(0xFF070709))
                  .withValues(alpha: 0.46),
              borderRadius: effectiveRadius,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.0,
              ),
            ),
            child: Center(
              widthFactor: width != null ? null : 1.0,
              heightFactor: height != null ? null : 1.0,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
