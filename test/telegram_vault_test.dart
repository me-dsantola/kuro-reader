import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/mangadex_service.dart';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/services/telegram_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testDir;
  late Directory previousDirectory;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('yomi_vault_test_');
    previousDirectory = Directory.current;
    Hive.init(testDir.path);
    for (final name in [
      StorageService.favBoxName,
      StorageService.historyBoxName,
      StorageService.downloadsBoxName,
      StorageService.settingsBoxName,
    ]) {
      await Hive.openBox(name);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => testDir.path);
    // Reproduz o APK: não há JSON na pasta de execução nem no suporte local.
    Directory.current = testDir;
  });

  tearDown(() async {
    Directory.current = previousDirectory;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await Hive.close();
    await testDir.delete(recursive: true);
  });

  test('bundled catalog is empty by default while Telegram works are removed', () async {
    final catalog = await TelegramVaultService.loadCatalog();
    expect(catalog, isEmpty);
  });

  test('detail discovery recovers preloaded or cached chapters for legacy saved Telegram manga', () async {
    final legacyChapter = Chapter(
      id: 'tg_ch_file_1',
      source: MangaSourceType.comicsHq,
      chapterNumber: '1',
      title: 'Edição #1',
      language: 'PT-BR',
      pages: 0,
      scanlator: 'Telegram Vault',
    );
    final saved = Manga(
      id: 'tg_vingadores_costa_oeste',
      source: MangaSourceType.comicsHq,
      title: 'Vingadores Costa Oeste',
      description: '',
      status: 'COMPLETED',
      tags: const ['HQ Ocidental'],
      preloadedChapters: [legacyChapter],
    );
    final result = await MangaDexService.discoverAllSourcesForManga(saved);
    expect(result[saved.source], hasLength(1));
    expect(result[saved.source]!.first.id, 'tg_ch_file_1');
    expect(MangaDexService.hasOlderChapters(saved.id), isFalse);
    final older = await MangaDexService.discoverAllSourcesForManga(
      saved,
      offset: 100,
    );
    expect(older[saved.source], isEmpty);
  });

  test('a damaged local catalog falls back safely to the bundled empty catalog without throwing', () async {
    await File('${testDir.path}/yomi_hqs_catalog.json').writeAsString('{broken');
    final catalog = await TelegramVaultService.loadCatalog();
    expect(catalog, isEmpty);
  });

  test('document chapters throw UnsupportedError and do not request MangaDex image endpoints', () async {
    final chapter = Chapter(
      id: 'tg_ch_doc_01',
      source: MangaSourceType.comicsHq,
      chapterNumber: '1',
      title: 'Capítulo 1',
      language: 'PT-BR',
      pages: 0,
    );
    var requests = 0;
    await http.runWithClient(
      () async {
        await expectLater(
          MangaDexService.fetchChapterPages(chapter),
          throwsA(isA<UnsupportedError>()),
        );
      },
      () => MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    expect(requests, 0);
  });

  test('public HQ catalog does not expose Telegram entries and surfaces MangaDex errors when offline', () async {
    await http.runWithClient(() async {
      await expectLater(
        WesternComicsHqAdapter().fetchCatalog(
          filter: const YomiSearchFilter(query: 'Vingadores Costa Oeste'),
          cursor: 0,
        ),
        throwsException,
      );
    }, () => MockClient((_) async => throw http.ClientException('offline')));
  });

  test('expanded EN feeds fill gaps without overriding PT-BR', () async {
    final requests = <Uri>[];
    await http.runWithClient(
      () async {
        final manga = Manga(
          id: '11111111-1111-1111-1111-111111111111',
          title: 'Series',
          description: '',
          status: 'ONGOING',
          tags: const [],
        );
        final result = await MangaDexService.discoverAllSourcesForManga(manga);
        final chapters = result[manga.source]!;
        expect(
          chapters.map((c) => c.chapterNumber),
          containsAll(['1', '501', '502', '1001']),
        );
        expect(
          chapters.singleWhere((c) => c.chapterNumber == '502').language,
          'PT-BR',
        );
        expect(
          chapters.singleWhere((c) => c.chapterNumber == '501').language,
          'EN',
        );
        expect(
          chapters.map((c) => c.chapterNumber).toSet(),
          hasLength(chapters.length),
        );
      },
      () => MockClient((request) async {
        requests.add(request.url);
        final lang = request.url.queryParameters['translatedLanguage[]']!;
        final offset = int.parse(request.url.queryParameters['offset']!);
        final numbers = lang == 'pt-br'
            ? (offset == 0
                  ? [1]
                  : offset == 500
                  ? [502]
                  : <int>[])
            : (offset == 0
                  ? [1]
                  : offset == 500
                  ? [501, 502]
                  : [1001]);
        return http.Response(
          jsonEncode({
            'total': 1001,
            'data': [
              for (final n in numbers)
                {
                  'id': '$lang-$n',
                  'attributes': {
                    'chapter': '$n',
                    'translatedLanguage': lang,
                    'pages': 20,
                  },
                },
            ],
          }),
          200,
        );
      }),
    );
    expect(
      requests.where(
        (url) => url.queryParameters['translatedLanguage[]'] == 'en',
      ),
      hasLength(3),
    );
  });
}
