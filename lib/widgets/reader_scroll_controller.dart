import 'package:flutter/widgets.dart';

/// Applies a reading anchor during layout, before a frame can paint the wrong
/// page. Unlike jumpTo this does not end the current scroll activity.
class ReaderScrollController extends ScrollController {
  double? _nextOffset;

  ReaderScrollController({super.initialScrollOffset})
    : super(keepScrollOffset: false);

  void correctLayoutOffset(double offset) {
    if (!offset.isFinite || offset < 0) return;
    if (!hasClients) {
      _nextOffset = offset;
      return;
    }
    final current = position as _ReaderScrollPosition;
    current.pendingOffset = offset;
    // Request correctForNewDimensions even if several extent changes cancel
    // each other and the total scroll extent happens to remain unchanged.
    current.correctBy(0);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    final initial = _nextOffset ?? initialScrollOffset;
    _nextOffset = null;
    return _ReaderScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initial,
      oldPosition: oldPosition,
    );
  }
}

class _ReaderScrollPosition extends ScrollPositionWithSingleContext {
  double? pendingOffset;

  _ReaderScrollPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    super.oldPosition,
  }) : super(keepScrollOffset: false);

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) {
    final target = pendingOffset;
    if (target == null) {
      return super.correctForNewDimensions(oldPosition, newPosition);
    }
    pendingOffset = null;
    final corrected = target
        .clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent)
        .toDouble();
    if ((corrected - pixels).abs() > 0.001) {
      correctPixels(corrected);
      return false;
    }
    return true;
  }
}
