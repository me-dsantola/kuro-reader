import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/download_manager.dart';
import 'package:kuro_reader/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAgCAIAAACU62+bAAAAHElEQVR4nGN4KOtBEmIY1TCqYVTDqIZRDSNBAwBtMowfZv2fjwAAAABJRU5ErkJggg==',
  );
  final manga = Manga(
    id: 'manga',
    title: 'Teste',
    description: '',
    status: 'ONGOING',
    tags: const [],
  );
  final chapter = Chapter(
    id: 'chapter',
    chapterNumber: '1',
    title: '',
    language: 'PT-BR',
    pages: 1,
    directPageUrls: const ['https://pages.example/0.png'],
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('yomi_downloads_');
    Hive.init(root.path);
    await Hive.openBox(StorageService.downloadsBoxName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await Hive.close();
    await root.delete(recursive: true);
  });

  test(
    'HTML is rejected, partial metadata is absent and a retry repairs the file',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            DownloadManager.downloadChapter(manga: manga, chapter: chapter),
            throwsFormatException,
          );
          expect(StorageService.isChapterDownloaded(chapter.id), isFalse);
          expect(DownloadManager.isDownloading(chapter.id), isFalse);
        },
        () => MockClient((_) async => http.Response('<html>error</html>', 200)),
      );
      await http.runWithClient(() async {
        await DownloadManager.downloadChapter(manga: manga, chapter: chapter);
        expect(await DownloadManager.hasCompleteDownload(chapter.id), isTrue);
        final path = StorageService.getDownloadedChapterPaths(
          chapter.id,
        ).single;
        await File(path).writeAsString('corrupt image');
        expect(await DownloadManager.hasCompleteDownload(chapter.id), isFalse);
        await DownloadManager.downloadChapter(manga: manga, chapter: chapter);
        expect(await DownloadManager.hasCompleteDownload(chapter.id), isTrue);
      }, () => MockClient((_) async => http.Response.bytes(png, 200)));
    },
  );

  test(
    'concurrent downloads share completion and cannot race with deletion',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      await http.runWithClient(
        () async {
          final first = DownloadManager.downloadChapter(
            manga: manga,
            chapter: chapter,
          );
          final second = DownloadManager.downloadChapter(
            manga: manga,
            chapter: chapter,
          );
          expect(identical(first, second), isTrue);
          await started.future;
          await expectLater(
            DownloadManager.deleteChapter(chapter.id),
            throwsStateError,
          );
          await expectLater(
            DownloadManager.deleteAllDownloads(),
            throwsStateError,
          );
          release.complete();
          await Future.wait([first, second]);
          expect(calls, 1);
          expect(await DownloadManager.hasCompleteDownload(chapter.id), isTrue);
          await DownloadManager.deleteChapter(chapter.id);
          expect(StorageService.isChapterDownloaded(chapter.id), isFalse);
        },
        () => MockClient((_) async {
          calls++;
          started.complete();
          await release.future;
          return http.Response.bytes(png, 200);
        }),
      );
    },
  );
}
