import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/screens/home_tabs.dart';
import 'package:kuro_reader/services/mangadex_service.dart';
import 'package:kuro_reader/services/storage_service.dart';

http.Response catalog(String title) => http.Response(
  jsonEncode({
    'total': 3,
    'data': [
      for (var index = 0; index < 3; index++)
        {
          'id': '$title-$index',
          'attributes': {
            'title': {'en': '$title $index'},
            'description': {'en': ''},
            'contentRating': 'safe',
            'latestUploadedChapter': 'chapter',
          },
        },
    ],
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yomi_search_');
    Hive.init(directory.path);
    for (final name in [
      StorageService.favBoxName,
      StorageService.historyBoxName,
      StorageService.settingsBoxName,
      StorageService.downloadsBoxName,
    ]) {
      await Hive.openBox(name);
    }
    StorageService.nsfwModeNotifier.value = NsfwDisplayMode.hidden;
    MangaDexService.resetAggregator();
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'a changed query cannot inherit buffered titles or page offsets',
    () async {
      final requests = <Uri>[];
      await http.runWithClient(
        () async {
          final first = await MangaDexService.fetchMergedCatalog(
            filter: YomiSearchFilter(
              query: 'Alpha',
              enabledSources: {MangaSourceType.mangadex},
            ),
            reset: true,
            pageSize: 1,
          );
          expect(first.single.title, startsWith('Alpha '));
          final second = await MangaDexService.fetchMergedCatalog(
            filter: YomiSearchFilter(
              query: 'Beta',
              enabledSources: {MangaSourceType.mangadex},
            ),
            pageSize: 1,
          );
          expect(second.single.title, startsWith('Beta '));
        },
        () => MockClient((request) async {
          requests.add(request.url);
          return catalog(request.url.queryParameters['title']!);
        }),
      );
      expect(requests.map((url) => url.queryParameters['offset']), ['0', '0']);
    },
  );

  testWidgets(
    'typing invalidates an in-flight search before debounce finishes',
    (tester) async {
      final old = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: ExploreScreen()));
          await tester.pumpAndSettle();
          final input = find.byType(TextField).first;
          await tester.enterText(input, 'old');
          await tester.pump(const Duration(milliseconds: 451));
          await tester.enterText(input, 'new');
          old.complete(catalog('Old result'));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('Old result 0'), findsNothing);
          await tester.pump(const Duration(milliseconds: 251));
          await tester.pump(const Duration(seconds: 6));
          await tester.pumpAndSettle();
          expect(find.text('New result 0'), findsWidgets);
          expect(find.text('Old result 0'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 6));
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          if (request.url.host == 'api.mangadex.org') {
            return switch (request.url.queryParameters['title']) {
              'old' => old.future,
              'new' => catalog('New result'),
              _ => http.Response('{"data":[],"total":0}', 200),
            };
          }
          if (request.url.host == 'graphql.anilist.co') {
            return http.Response(
              '{"data":{"Page":{"media":[],"pageInfo":{"hasNextPage":false}}}}',
              200,
            );
          }
          return http.Response(
            '{"data":[],"links":{},"pagination":{"has_next_page":false}}',
            200,
          );
        }),
      );
    },
  );
}
