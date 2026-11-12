import 'dart:io';
import 'dart:convert';

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

  test('bundled catalog loads chapters without a project directory', () async {
    final catalog = await TelegramVaultService.loadCatalog();
    expect(catalog, isNotEmpty);
    final manga = catalog.firstWhere(
      (m) => m.title == 'Vingadores Costa Oeste',
    );
    expect(manga.preloadedChapters, isNotEmpty);
    expect(
      StorageService.getCachedMangaChapters(manga.id),
      hasLength(manga.preloadedChapters!.length),
    );
  });

  test('detail discovery recovers Vault chapters for saved manga', () async {
    final catalog = await TelegramVaultService.loadCatalog();
    final original = catalog.first;
    final saved = Manga(
      id: original.id,
      source: MangaSourceType.comicsHq,
      title: original.title,
      description: '',
      status: 'COMPLETED',
      tags: const [],
    );
    final result = await MangaDexService.discoverAllSourcesForManga(saved);
    expect(result[saved.source], hasLength(original.preloadedChapters!.length));
    expect(result[saved.source]!.first.id, startsWith('tg_ch_'));
    expect(MangaDexService.hasOlderChapters(saved.id), isFalse);
    final older = await MangaDexService.discoverAllSourcesForManga(
      saved,
      offset: 100,
    );
    expect(older[saved.source], isEmpty);
  });

  test('a damaged local catalog falls back to the bundled catalog', () async {
    await File(
      '${testDir.path}/yomi_hqs_catalog.json',
    ).writeAsString('{broken');
    expect(await TelegramVaultService.loadCatalog(), isNotEmpty);
  });

  test('document chapters do not request a MangaDex image endpoint', () async {
    final catalog = await TelegramVaultService.loadCatalog();
    final chapter = catalog.first.preloadedChapters!.first;
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

  test('HQ catalog survives a MangaDex outage', () async {
    await http.runWithClient(() async {
      final result = await WesternComicsHqAdapter().fetchCatalog(
        filter: YomiSearchFilter(query: 'Vingadores Costa Oeste'),
        cursor: 0,
      );
      expect(result.items, isNotEmpty);
      expect(result.items.first.id, startsWith('tg_'));
      expect(result.items.first.preloadedChapters, isNotEmpty);
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
