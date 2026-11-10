enum CatalogSort {
  latest('Recentes'),
  popular('Populares'),
  title('Título A–Z');

  final String label;
  const CatalogSort(this.label);

  String get mangaDexOrder => switch (this) {
    latest => '&order[latestUploadedChapter]=desc',
    popular => '&order[followedCount]=desc',
    title => '&order[title]=asc',
  };

  String get aniListOrder => switch (this) {
    latest => 'UPDATED_AT_DESC',
    popular => 'POPULARITY_DESC',
    title => 'TITLE_ENGLISH',
  };

  String get jikanOrder => switch (this) {
    latest => '&order_by=start_date&sort=desc',
    popular => '&order_by=popularity&sort=asc',
    title => '&order_by=title&sort=asc',
  };

  String get kitsuOrder => switch (this) {
    latest => '-updatedAt',
    popular => '-userCount',
    title => 'canonicalTitle',
  };
}
