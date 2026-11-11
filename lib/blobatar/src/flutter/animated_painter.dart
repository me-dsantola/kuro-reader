/// Custom painter for animated blobatar frames.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter/rendering.dart' show CustomPainter;

import 'animated_renderer.dart';

typedef AnimatedBlobatarFrameBuilder = AnimatedBlobatarFrame Function();

/// Paints elapsed-time frames from a cached [AnimatedBlobatarRenderer].
class AnimatedBlobatarPainter extends CustomPainter {
  /// The cached renderer whose paths are reused across frames.
  final AnimatedBlobatarRenderer renderer;

  /// Produces the current pose, colors, and motion values for each repaint.
  final AnimatedBlobatarFrameBuilder frameBuilder;

  /// Creates an animated painter driven by [repaint].
  AnimatedBlobatarPainter({
    required this.renderer,
    required this.frameBuilder,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// Evaluates and returns the frame that would be painted now.
  AnimatedBlobatarFrame get currentFrame => frameBuilder();

  @override
  void paint(ui.Canvas canvas, ui.Size size) =>
      renderer.paint(canvas, size, currentFrame);

  @override
  bool shouldRepaint(covariant AnimatedBlobatarPainter oldDelegate) =>
      oldDelegate.renderer != renderer;
}
