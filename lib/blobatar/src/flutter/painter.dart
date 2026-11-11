/// The [CustomPainter] that backs the [Blobatar] widget.
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show CustomPainter;

import '../../blobatar.dart' show BlobatarOptions;

import 'renderer.dart';

/// Paints a static blobatar through [BlobatarRenderer].
///
/// The painter owns the repaint decision ([shouldRepaint] compares the seed
/// and the options by value), not the sizing — the enclosing widget owns the
/// constraints. Sizing changes alone never repaint, since the renderer maps
/// the viewBox onto whatever canvas it is given.
class BlobatarPainter extends CustomPainter {
  /// The name resolved by this painter.
  final String name;

  /// The immutable core options resolved by this painter.
  final BlobatarOptions options;

  /// The wrapped renderer, kept so tests and the widget can share one
  /// resolution instead of resolving twice.
  final BlobatarRenderer renderer;

  /// Creates a static painter and resolves its renderer immediately.
  BlobatarPainter({required this.name, this.options = const BlobatarOptions()})
      : renderer = BlobatarRenderer(name: name, options: options);

  @override
  void paint(ui.Canvas canvas, ui.Size size) => renderer.paint(canvas, size);

  @override
  bool shouldRepaint(covariant BlobatarPainter oldDelegate) =>
      oldDelegate.name != name || oldDelegate.options != options;
}
