/// Device-independent position within a chapter. Stored as a plain Hive map.
class ReaderAnchor {
  final int page;
  final double fraction;
  const ReaderAnchor(this.page, this.fraction);

  Map<String, dynamic> toMap() => {'page': page, 'fraction': fraction};

  static ReaderAnchor? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final page = raw['page'];
    final fraction = raw['fraction'];
    if (page is! int ||
        page < 0 ||
        fraction is! num ||
        !fraction.isFinite ||
        fraction < 0 ||
        fraction > 1) {
      return null;
    }
    return ReaderAnchor(page, fraction.toDouble());
  }
}
