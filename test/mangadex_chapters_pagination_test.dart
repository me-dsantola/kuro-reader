import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/chapter_availability_cache.dart';
import 'package:kuro_reader/services/mangadex_service.dart';
import 'package:kuro_reader/services/storage_service.dart';

Map<String, dynamic> _rawChapterJson({
  required String id,
  required String? chapter,
  String? volume,
  required String lang,
  String title = '',
  int pages = 18,
  String scanlator = 'Scan YOMI',
  String publishAt = '2025-01-01T00:00:00+00:00',
}) {
  return {
    'id': id,
    'type': 'chapter',
    'attributes': {
      'volume': volume,
      'chapter': chapter,
      'title': title,
      'translatedLanguage': lang,
      'pages': pages,
      'publishAt': publishAt,
    },
    'relationships': [
      {
        'id': 'group_1',
        'type': 'scanlation_group',
        'attributes': {'name': scanlator},
      },
    ],
  };
}

Manga _buildTestManga(String id) {
  return Manga(
    id: id,
    title: 'Manga Teste $id',
    description: 'Sinopse teste',
    status: 'ONGOING',
    tags: const ['Ação'],
    source: MangaSourceType.mangadex,
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('yomi_mdx_pagination_');
    Hive.init(tempDir.path);
    await Hive.openBox(StorageService.settingsBoxName);
    await Hive.openBox(StorageService.historyBoxName);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    MangaDexService.httpRetryBaseDelay = const Duration(milliseconds: 5);
    await StorageService.settingsBox.clear();
    await StorageService.historyBox.clear();
  });

  tearDown(() {
    MangaDexService.httpRetryBaseDelay = const Duration(milliseconds: 300);
  });

  group('Chapter normalization & specials', () {
    test('preserves decimals, chapter 0, padded numbers and unnumbered specials without colliding with Ch. 1', () {
      final chZero = Chapter.fromJson(
        _rawChapterJson(id: 'c0', chapter: '0', lang: 'pt-br', title: 'Prólogo'),
      );
      final chPadded = Chapter.fromJson(
        _rawChapterJson(id: 'c01', chapter: '01', lang: 'pt-br'),
      );
      final chDecimal = Chapter.fromJson(
        _rawChapterJson(id: 'c10_5', chapter: '10.5', lang: 'en', title: 'Omake'),
      );
      final oneshot = Chapter.fromJson(
        _rawChapterJson(id: 'sp_one', chapter: null, lang: 'pt-br', title: 'Oneshot'),
      );
      final extra = Chapter.fromJson(
        _rawChapterJson(
          id: 'sp_ext',
          chapter: null,
          lang: 'en',
          title: 'Extra Especial',
        ),
      );

      expect(chZero.chapterNumber, '0');
      expect(chZero.isSpecial, isFalse);
      expect(chZero.canonicalKey, 'ch:0');
      expect(chZero.displayLabel, 'Cap. 0');

      expect(chPadded.chapterNumber, '1');
      expect(chPadded.canonicalKey, 'ch:1');

      expect(chDecimal.chapterNumber, '10.5');
      expect(chDecimal.numericChapter, 10.5);
      expect(chDecimal.canonicalKey, 'ch:10.5');

      expect(oneshot.isSpecial, isTrue);
      expect(oneshot.chapterNumber, 'Oneshot');
      expect(oneshot.canonicalKey, 'special:sp_one');
      expect(oneshot.canonicalKey, isNot(chPadded.canonicalKey));

      expect(extra.isSpecial, isTrue);
      expect(extra.chapterNumber, 'Extra');
      expect(extra.canonicalKey, 'special:sp_ext');
      expect(extra.displayLabel, 'Extra');
    });
  });

  group('MangaDexService retry, >1500 pagination & gap filling', () {
    test('safeHttpGet retries on HTTP 429 and 503 before succeeding', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response('rate limited', 429, headers: {'retry-after': '0'});
        }
        if (calls == 2) {
          return http.Response('service unavailable', 503);
        }
        return http.Response('{"result":"ok"}', 200);
      });

      final res = await http.runWithClient(
        () => MangaDexService.safeHttpGet(
          'https://api.mangadex.org/manga/test-123/feed',
        ),
        () => client,
      );

      expect(calls, 3);
      expect(res.statusCode, 200);
    });

    test('paginates beyond 1500 chapters and returns all 1850 unique chapters', () async {
      const totalChapters = 1850;
      final requestedOffsets = <int>[];

      final client = MockClient((request) async {
        final langs = request.url.queryParametersAll['translatedLanguage[]'];
        final lang = (langs != null && langs.isNotEmpty) ? langs.first : '';
        final offset = int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
        final limit = int.tryParse(request.url.queryParameters['limit'] ?? '500') ?? 500;

        if (lang == 'pt-br') {
          requestedOffsets.add(offset);
          final end = (offset + limit).clamp(0, totalChapters);
          final items = <Map<String, dynamic>>[];
          for (var n = offset + 1; n <= end; n++) {
            items.add(
              _rawChapterJson(
                id: 'pt_ch_$n',
                chapter: '$n',
                lang: 'pt-br',
                title: 'Cap $n',
              ),
            );
          }
          return http.Response(
            jsonEncode({'result': 'ok', 'total': totalChapters, 'data': items}),
            200,
          );
        }

        return http.Response(
          jsonEncode({'result': 'ok', 'total': 0, 'data': const []}),
          200,
        );
      });

      final manga = _buildTestManga('11111111-2222-3333-4444-555555555555');
      final sources = await http.runWithClient(
        () => MangaDexService.discoverAllSourcesForManga(
          manga,
          includeSpanishFallback: false,
        ),
        () => client,
      );

      final chapters = sources[MangaSourceType.mangadex] ?? const <Chapter>[];
      expect(requestedOffsets, containsAll(<int>[0, 500, 1000, 1500]));
      expect(chapters.length, totalChapters);
      expect(chapters.first.chapterNumber, '$totalChapters');
      expect(chapters.last.chapterNumber, '1');
    });

    test('fills chapter gaps following PT-BR > EN > ES priority', () async {
      final client = MockClient((request) async {
        final langs = request.url.queryParametersAll['translatedLanguage[]'];
        final lang = (langs != null && langs.isNotEmpty) ? langs.first : '';

        if (lang == 'pt-br') {
          return http.Response(
            jsonEncode({
              'result': 'ok',
              'total': 1,
              'data': [
                _rawChapterJson(id: 'pt_1', chapter: '1', lang: 'pt-br', title: 'PT 1'),
              ],
            }),
            200,
          );
        }
        if (lang == 'en') {
          return http.Response(
            jsonEncode({
              'result': 'ok',
              'total': 2,
              'data': [
                _rawChapterJson(id: 'en_1', chapter: '1', lang: 'en', title: 'EN 1'),
                _rawChapterJson(id: 'en_2', chapter: '2', lang: 'en', title: 'EN 2'),
              ],
            }),
            200,
          );
        }
        if (lang == 'es') {
          return http.Response(
            jsonEncode({
              'result': 'ok',
              'total': 2,
              'data': [
                _rawChapterJson(id: 'es_2', chapter: '2', lang: 'es', title: 'ES 2'),
                _rawChapterJson(id: 'es_3', chapter: '3', lang: 'es', title: 'ES 3'),
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'result': 'ok', 'total': 0, 'data': []}), 200);
      });

      final manga = _buildTestManga('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      final sources = await http.runWithClient(
        () => MangaDexService.discoverAllSourcesForManga(
          manga,
          includeSpanishFallback: true,
        ),
        () => client,
      );

      final chapters = sources[MangaSourceType.mangadex] ?? const <Chapter>[];
      expect(chapters.map((c) => '${c.chapterNumber}:${c.language}').toList(), [
        '3:ES',
        '2:EN',
        '1:PT-BR',
      ]);
      expect(chapters.map((c) => c.id).toList(), ['es_3', 'en_2', 'pt_1']);
    });

    test('network failure preserves cached chapters when present and throws without confirmedZero when uncached', () async {
      const cachedMangaId = '99999999-8888-7777-6666-555555555555';
      final cachedManga = _buildTestManga(cachedMangaId);

      await StorageService.cacheMangaChapters(cachedMangaId, [
        Chapter(
          id: 'cached_1',
          chapterNumber: '1',
          title: 'Em cache',
          language: 'PT-BR',
          pages: 20,
          scanlator: 'Scan',
        ),
      ]);

      final failingClient = MockClient((request) async {
        return http.Response('upstream down', 503);
      });

      final fallbackResult = await http.runWithClient(
        () => MangaDexService.discoverAllSourcesForManga(cachedManga),
        () => failingClient,
      );
      expect(
        fallbackResult[MangaSourceType.mangadex]?.map((c) => c.id).toList(),
        ['cached_1'],
      );

      final preservedCache = StorageService.getCachedMangaChapters(cachedMangaId);
      expect(preservedCache.length, 1);
      expect(preservedCache.first.id, 'cached_1');
      expect(StorageService.isConfirmedZeroChapters(cachedManga), isFalse);

      // Quando não há cache anterior, falha HTTP não deve gravar 0 capítulos confirmados
      const uncachedMangaId = '77777777-6666-5555-4444-333333333333';
      final uncachedManga = _buildTestManga(uncachedMangaId);

      await expectLater(
        () => http.runWithClient(
          () => MangaDexService.discoverAllSourcesForManga(uncachedManga),
          () => failingClient,
        ),
        throwsException,
      );
      expect(StorageService.isConfirmedZeroChapters(uncachedManga), isFalse);
    });
  });

  group('ChapterAvailabilityCache error vs confirmedZero distinction', () {
    test('distinguishes temporary network failure from confirmed 0 chapters', () async {
      final cache = ChapterAvailabilityCache(maxConcurrentFetches: 2);

      await cache.ensureResolved('m_err', (_) async {
        throw Exception('Erro de conexão 503');
      });
      final errState = cache.watch('m_err').value;
      expect(errState.status, ChapterCountStatus.temporaryError);
      expect(errState.isTemporaryError, isTrue);
      expect(errState.isConfirmedZero, isFalse);

      await cache.ensureResolved('m_zero', (_) async => 0);
      final zeroState = cache.watch('m_zero').value;
      expect(zeroState.isConfirmedZero, isTrue);
      expect(zeroState.isTemporaryError, isFalse);
      expect(zeroState.status, isNot(ChapterCountStatus.temporaryError));
    });
  });
}
