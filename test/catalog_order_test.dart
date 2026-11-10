import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/models/catalog_sort.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/mangadex_service.dart';

void main() {
  for (final sort in CatalogSort.values) {
    test(
      'native provider requests honor ${sort.label}, including title searches',
      () async {
        final requests = <http.Request>[];
        await http.runWithClient(
          () async {
            final filter = YomiSearchFilter(
              query: 'One Piece',
              sort: sort,
              allowNsfw: true,
            );
            for (final adapter in <IMangaSourceAdapter>[
              MangaDexAdapter(),
              AniListGraphQLAdapter(),
              JikanMalAdapter(),
              ComicKPlusAdapter(),
              WesternComicsHqAdapter(),
              AdultVaultAdapter(),
            ]) {
              await adapter.fetchCatalog(filter: filter, cursor: 0);
            }
          },
          () => MockClient((request) async {
            requests.add(request);
            if (request.url.host == 'graphql.anilist.co') {
              return http.Response(
                jsonEncode({
                  'data': {
                    'Page': {
                      'media': [],
                      'pageInfo': {'hasNextPage': false},
                    },
                  },
                }),
                200,
              );
            }
            if (request.url.host == 'kitsu.io') {
              return http.Response(
                jsonEncode({
                  'data': [
                    {
                      'attributes': {
                        'canonicalTitle': 'One Piece',
                        'ageRating': 'G',
                      },
                    },
                  ],
                  'links': {},
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'data': [],
                'total': 0,
                'pagination': {'has_next_page': false},
              }),
              200,
            );
          }),
        );
        final mdx = requests
            .where((r) => r.url.host == 'api.mangadex.org')
            .toList();
        expect(mdx, hasLength(3));
        final key = switch (sort) {
          CatalogSort.latest => 'order[latestUploadedChapter]',
          CatalogSort.popular => 'order[followedCount]',
          CatalogSort.title => 'order[title]',
        };
        for (final request in mdx) {
          expect(
            request.url.queryParameters[key],
            sort == CatalogSort.title ? 'asc' : 'desc',
          );
        }
        final ani = requests.singleWhere(
          (r) => r.url.host == 'graphql.anilist.co',
        );
        expect(ani.body, contains('sort: [${sort.aniListOrder}]'));
        final mal = requests.singleWhere((r) => r.url.host == 'api.jikan.moe');
        expect(mal.url.queryParameters['order_by'], switch (sort) {
          CatalogSort.latest => 'start_date',
          CatalogSort.popular => 'popularity',
          CatalogSort.title => 'title',
        });
        final kitsu = requests.singleWhere((r) => r.url.host == 'kitsu.io');
        expect(kitsu.url.queryParameters['sort'], sort.kitsuOrder);
      },
    );
  }
}
