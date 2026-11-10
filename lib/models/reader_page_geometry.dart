/// Page extents belong to the chapter, not to recycled image widgets.
class ReaderPageGeometry {
  final int pageCount;
  final Map<int, double> _ratios = {};
  static const double fallbackRatio = 1 / 1.42;

  ReaderPageGeometry(this.pageCount);

  double ratioAt(int index) => _ratios[index] ?? fallbackRatio;
  bool hasRatio(int index) => _ratios.containsKey(index);
  double extentAt(int index, double width) => width / ratioAt(index);

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
