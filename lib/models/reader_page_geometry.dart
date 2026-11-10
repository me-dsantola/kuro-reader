import 'reader_anchor.dart';

/// Page extents belong to the chapter, not to recycled image widgets.
class ReaderPageGeometry {
  final int pageCount;
  final Map<int, double> _ratios = {};
  static const double fallbackRatio = 1 / 1.42;

  ReaderPageGeometry(this.pageCount);

  double ratioAt(int index) => _ratios[index] ?? fallbackRatio;
  bool hasRatio(int index) => _ratios.containsKey(index);
  double extentAt(int index, double width) => width / ratioAt(index);

  ReaderAnchor anchorAt(double offset, double width) {
    if (pageCount == 0 || width <= 0) return const ReaderAnchor(0, 0);
    final page = pageAt(offset, width).clamp(0, pageCount - 1);
    final fraction = ((offset - offsetOf(page, width)) / extentAt(page, width))
        .clamp(0.0, 1.0)
        .toDouble();
    return ReaderAnchor(page, fraction);
  }

  double offsetFor(ReaderAnchor anchor, double width) {
    if (pageCount == 0) return 0;
    final page = anchor.page.clamp(0, pageCount - 1);
    return offsetOf(page, width) + extentAt(page, width) * anchor.fraction;
  }

  double offsetOf(int index, double width) {
    double offset = 0;
    for (var i = 0; i < index && i < pageCount; i++) {
      offset += extentAt(i, width);
    }
    return offset;
  }

  int pageAt(double offset, double width) {
    double end = 0;
    for (var i = 0; i < pageCount; i++) {
      end += extentAt(i, width);
      if (offset < end) return i;
    }
    return pageCount;
  }

  double reflowOffset(double offset, double oldWidth, double newWidth) {
    if (oldWidth <= 0 || newWidth <= 0 || !offset.isFinite) return 0;
    final page = pageAt(offset, oldWidth);
    final within = offset - offsetOf(page, oldWidth);
    return offsetOf(page, newWidth) +
        (page < pageCount ? within * newWidth / oldWidth : within);
  }

  /// Retains the page and relative position at the top of the viewport when
  /// newly decoded online images replace estimated extents.
  double updateRatios(Map<int, double> changes, double width, double offset) {
    final anchor = pageAt(offset, width);
    final start = offsetOf(anchor, width);
    final within = offset - start;
    final fraction = anchor < pageCount
        ? within / extentAt(anchor, width)
        : 0.0;
    for (final entry in changes.entries) {
      if (entry.key >= 0 &&
          entry.key < pageCount &&
          entry.value.isFinite &&
          entry.value > 0) {
        _ratios[entry.key] = entry.value;
      }
    }
    return offsetOf(anchor, width) +
        (anchor < pageCount ? fraction * extentAt(anchor, width) : within);
  }
}
