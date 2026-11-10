/// Provider classification is separate from whether the user allows it.
enum ContentRating {
  safe,
  sensitive,
  unknown;

  // Unknown metadata is never silently treated as safe.
  bool get needsSensitiveMode => this != safe;

  static ContentRating fromKitsu(Map attributes) {
    if (attributes['nsfw'] == true) return sensitive;
    final age = attributes['ageRating']?.toString().toUpperCase();
    return switch (age) {
      'G' || 'PG' => safe,
      'R' || 'R18' => sensitive,
      _ => unknown,
    };
  }

  static ContentRating fromJikan(Map entry) {
    final genres = entry['genres'];
    final explicit = entry['explicit_genres'];
    final categories = <Map>[
      if (genres is List) ...genres.whereType<Map>(),
      if (explicit is List) ...explicit.whereType<Map>(),
    ];
    if (categories.any(
      (genre) =>
          const {9, 12, 49}.contains(genre['mal_id']) ||
          const {
            'ecchi',
            'hentai',
            'erotica',
          }.contains(genre['name']?.toString().toLowerCase()),
    )) {
      return sensitive;
    }
    // Jikan supplies explicit_genres, including an empty list for safe works.
    // Missing or malformed classification remains unknown.
    if (genres is List &&
        explicit is List &&
        genres.every((g) => g is Map) &&
        explicit.isEmpty) {
      return safe;
    }
    return unknown;
  }
}
