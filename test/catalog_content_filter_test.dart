import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/mangadex_service.dart';

void main() {
  test(
    'Jikan adapter hides unknown and explicit works but retains their classification when enabled',
    () async {
      final payload = {
        'data': [
          {'title': 'Safe', 'genres': [], 'explicit_genres': []},
          {
            'title': 'Mature',
            'genres': [],
            'explicit_genres': [
              {'mal_id': 49, 'name': 'Erotica'},
            ],
          },
          {'title': 'Unknown', 'genres': []},
        ],
        'pagination': {'has_next_page': true},
      };
      Future<PaginatedSourceResponse> fetch(bool allow) => http.runWithClient(
        () => JikanMalAdapter().fetchCatalog(
          filter: YomiSearchFilter(allowNsfw: allow),
          cursor: 0,
        ),
        () => MockClient((request) async {
          expect(request.url.queryParameters['sfw'], (!allow).toString());
          return http.Response(jsonEncode(payload), 200);
        }),
      );
      final safe = await fetch(false);
      expect(safe.items.map((m) => m.title), ['Safe']);
      final all = await fetch(true);
      expect(all.items, hasLength(3));
      expect(all.items.map((m) => m.isNsfw), [false, true, true]);
      expect(Manga.fromMap(all.items[1].toMap()).isNsfw, isTrue);
    },
  );

  test(
    'Kitsu adapter filters by age and retains pagination on a fully hidden page',
    () async {
      final payload = {
        'data': [
          {
            'attributes': {'canonicalTitle': 'Mature', 'ageRating': 'R18'},
          },
          {
            'attributes': {'canonicalTitle': 'Unknown'},
          },
        ],
        'links': {'next': 'https://kitsu.io/api/edge/manga?page[offset]=20'},
      };
      Future<PaginatedSourceResponse> fetch(bool allow) => http.runWithClient(
        () => ComicKPlusAdapter().fetchCatalog(
          filter: YomiSearchFilter(allowNsfw: allow),
          cursor: 0,
        ),
        () => MockClient((_) async => http.Response(jsonEncode(payload), 200)),
      );
      final safe = await fetch(false);
      expect(safe.items, isEmpty);
      expect(safe.hasMore, isTrue);
      expect(safe.nextCursor, 20);
      final all = await fetch(true);
      expect(all.items.map((m) => m.isNsfw), [true, true]);
      expect(all.items.last.contentRatingKnown, isFalse);
    },
  );
}
