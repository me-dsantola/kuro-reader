import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/content_rating.dart';
import 'package:kuro_reader/models/manga_models.dart';

void main() {
  test('Kitsu distinguishes safe, mature and missing ratings', () {
    expect(ContentRating.fromKitsu({'ageRating': 'PG'}), ContentRating.safe);
    expect(
      ContentRating.fromKitsu({'ageRating': 'R18'}),
      ContentRating.sensitive,
    );
    expect(
      ContentRating.fromKitsu({'ageRating': 'G', 'nsfw': true}),
      ContentRating.sensitive,
    );
    expect(ContentRating.fromKitsu({}).needsSensitiveMode, isTrue);
  });

  test(
    'Jikan preserves explicit classification even after safe mode is enabled',
    () {
      expect(
        ContentRating.fromJikan({
          'genres': [],
          'explicit_genres': [
            {'mal_id': 49, 'name': 'Erotica'},
          ],
        }),
        ContentRating.sensitive,
      );
      expect(
        ContentRating.fromJikan({
          'genres': [
            {'mal_id': 1, 'name': 'Action'},
          ],
          'explicit_genres': [],
        }),
        ContentRating.safe,
      );
      expect(ContentRating.fromJikan({'genres': []}), ContentRating.unknown);
      expect(
        ContentRating.fromJikan({
          'genres': [],
          'explicit_genres': [{}],
        }),
        ContentRating.unknown,
      );
    },
  );

  test('legacy metadata is retained but not implicitly trusted as safe', () {
    for (final source in ['jikanMal', 'comick']) {
      final legacy = Manga.fromMap({
        'id': 'saved-id',
        'title': 'Obra salva',
        'source': source,
        'isNsfw': false,
      });
      expect(legacy.id, 'saved-id');
      expect(legacy.isNsfw, isTrue);
      expect(legacy.contentRatingKnown, isFalse);
      expect(Manga.fromMap(legacy.toMap()).isNsfw, isTrue);
    }
    final verified = Manga.fromMap({
      'id': 'saved-id',
      'title': 'Obra segura',
      'source': 'comick',
      'isNsfw': false,
      'contentRatingKnown': true,
    });
    expect(verified.isNsfw, isFalse);
  });
}
