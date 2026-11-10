import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/services/backup_codec.dart';
import 'package:kuro_reader/models/reader_anchor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('yomi_hive_test_');
    Hive.init(testDir.path);
    await Hive.openBox(StorageService.favBoxName);
    await Hive.openBox(StorageService.historyBoxName);
    await Hive.openBox(StorageService.downloadsBoxName);
    await Hive.openBox(StorageService.settingsBoxName);
    StorageService.nsfwModeNotifier.value = NsfwDisplayMode.hidden;
  });

  tearDown(() async {
    await Hive.close();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  final manga = Manga(
    id: 'test-manga',
    title: 'Obra de teste',
    description: 'Sinopse',
    status: 'ONGOING',
    tags: const ['Aventura'],
  );
  final chapter = Chapter(
    id: 'test-chapter',
    chapterNumber: '1',
    title: 'Início',
    language: 'PT-BR',
    pages: 15,
  );

  test('opening a chapter keeps it in progress and not completed', () async {
    await StorageService.recordChapterOpened(manga, chapter);
    expect(StorageService.isChapterRead(chapter.id), isFalse);
    expect(StorageService.getLastReadChapter(manga.id)?.id, chapter.id);
    expect(StorageService.getContinueReadingList(), hasLength(1));
    expect(StorageService.computeReadingMetrics().totalChaptersRead, 0);
  });

  test('completing a chapter counts once, even after reopening', () async {
    await StorageService.recordChapterOpened(manga, chapter);
    await StorageService.markChapterAsRead(manga, chapter);
    await StorageService.recordChapterOpened(manga, chapter);
    await StorageService.markChapterAsRead(manga, chapter);
    expect(StorageService.isChapterRead(chapter.id), isTrue);
    expect(StorageService.computeReadingMetrics().totalChaptersRead, 1);
    expect(StorageService.computeReadingMetrics().totalPagesRead, 15);
  });

  test('marking a completed chapter unread also corrects statistics', () async {
    await StorageService.markChapterAsRead(manga, chapter);
    expect(StorageService.computeReadingMetrics().totalChaptersRead, 1);
    await StorageService.markChapterAsRead(manga, chapter, read: false);
    expect(StorageService.isChapterRead(chapter.id), isFalse);
    expect(StorageService.computeReadingMetrics().totalChaptersRead, 0);
    await StorageService.markChapterAsRead(manga, chapter);
    expect(StorageService.computeReadingMetrics().totalChaptersRead, 1);
  });

  test('webtoon position coexists with legacy page index', () async {
    await StorageService.saveLastPageIndex(chapter.id, 4);
    await StorageService.saveWebtoonOffset(chapter.id, 1850.5);
    expect(StorageService.getSavedPageIndex(chapter.id), 4);
    expect(StorageService.getSavedWebtoonOffset(chapter.id), 1850.5);
    await StorageService.saveWebtoonOffset(chapter.id, -2);
    expect(StorageService.getSavedWebtoonOffset(chapter.id), 1850.5);
  });

  test('backup restore keeps profile, settings and chapters', () async {
    await StorageService.favBox.put(manga.id, manga.toMap());
    await StorageService.recordChapterOpened(manga, chapter);
    await StorageService.setDataSaverEnabled(true);
    final backup = StorageService.exportFullBackupJson();
    await StorageService.favBox.clear();
    await StorageService.historyBox.clear();
    await StorageService.setDataSaverEnabled(false);

    expect(await StorageService.importFullBackupJson(backup), isTrue);
    expect(StorageService.isFavorite(manga.id), isTrue);
    expect(StorageService.getLastReadChapter(manga.id)?.id, chapter.id);
    expect(StorageService.dataSaverEnabled, isTrue);
  });

  test('malformed backups do not clear local favorites', () async {
    await StorageService.favBox.put(manga.id, manga.toMap());
    expect(
      await StorageService.importFullBackupJson('{"favorites":{"bad":42}}'),
      isFalse,
    );
    expect(StorageService.isFavorite(manga.id), isTrue);
  });

  test('nested invalid history does not overwrite any section', () async {
    await StorageService.favBox.put(manga.id, manga.toMap());
    await StorageService.saveLastPageIndex(chapter.id, 4);
    final invalid = BackupCodec.encode({
      'favorites': {
        'new': {...manga.toMap(), 'id': 'new'},
      },
      'history': {'page_${chapter.id}': 'broken'},
      'profile': {'name': 'Changed'},
    });
    expect(await StorageService.importFullBackupJson(invalid), isFalse);
    expect(StorageService.favBox.containsKey('new'), isFalse);
    expect(StorageService.getSavedPageIndex(chapter.id), 4);
    expect(
      StorageService.settingsBox.containsKey(StorageService.restoreJournalKey),
      isFalse,
    );
  });

  test(
    'an interrupted restore rolls back overwritten and newly inserted keys',
    () async {
      await StorageService.favBox.put(manga.id, {
        ...manga.toMap(),
        'title': 'Partial',
      });
      await StorageService.favBox.put('new', {...manga.toMap(), 'id': 'new'});
      await StorageService.saveLastPageIndex(chapter.id, 9);
      await StorageService.setDataSaverEnabled(true);
      await StorageService.settingsBox.put(StorageService.restoreJournalKey, {
        'favorites': {
          manga.id: {'exists': true, 'value': manga.toMap()},
          'new': {'exists': false, 'value': null},
        },
        'history': {
          'page_${chapter.id}': {'exists': true, 'value': 4},
        },
        'settings': {
          'data_saver_mode': {'exists': false, 'value': null},
        },
      });
      await StorageService.recoverInterruptedRestore();
      await StorageService.recoverInterruptedRestore();
      expect(StorageService.getFavorites().single.title, manga.title);
      expect(StorageService.getSavedPageIndex(chapter.id), 4);
      expect(StorageService.dataSaverEnabled, isFalse);
      expect(
        StorageService.settingsBox.containsKey(
          StorageService.restoreJournalKey,
        ),
        isFalse,
      );
    },
  );

  test(
    'concurrent restore requests are serialized without a leftover journal',
    () async {
      final results = await Future.wait([
        StorageService.importFullBackupJson(
          BackupCodec.encode({
            'history': {'page_${chapter.id}': 3},
          }),
        ),
        StorageService.importFullBackupJson(
          BackupCodec.encode({
            'history': {'page_${chapter.id}': 8},
          }),
        ),
      ]);
      expect(results, [true, true]);
      expect(StorageService.getSavedPageIndex(chapter.id), 8);
      expect(
        StorageService.settingsBox.containsKey(
          StorageService.restoreJournalKey,
        ),
        isFalse,
      );
    },
  );

  test(
    'unknown legacy metadata is hidden across all local reading surfaces',
    () async {
      final legacy = {...manga.toMap(), 'source': 'comick'}
        ..remove('contentRatingKnown');
      await StorageService.favBox.put(manga.id, legacy);
      await StorageService.historyBox.put('recent_reading_list', [
        {'manga': legacy, 'chapter': chapter.toMap()},
      ]);
      await StorageService.downloadsBox.put(chapter.id, {
        'manga': legacy,
        'chapter': chapter.toMap(),
        'paths': <String>[],
      });
      expect(StorageService.getFavorites(), isEmpty);
      expect(StorageService.getContinueReadingList(), isEmpty);
      expect(StorageService.getAllDownloadedChapters(), isEmpty);
      StorageService.nsfwModeNotifier.value = NsfwDisplayMode.visible;
      expect(StorageService.getFavorites(), hasLength(1));
      expect(StorageService.getContinueReadingList(), hasLength(1));
      expect(StorageService.getAllDownloadedChapters(), hasLength(1));
    },
  );

  test(
    'reading anchor survives backup without losing legacy positions',
    () async {
      await StorageService.saveWebtoonAnchor(
        chapter.id,
        const ReaderAnchor(4, 0.65),
      );
      await StorageService.saveLastPageIndex(chapter.id, 4);
      await StorageService.saveWebtoonOffset(chapter.id, 1850);
      final backup = StorageService.exportFullBackupJson();
      await StorageService.historyBox.clear();
      expect(await StorageService.importFullBackupJson(backup), isTrue);
      expect(StorageService.getWebtoonAnchor(chapter.id)?.page, 4);
      expect(StorageService.getWebtoonAnchor(chapter.id)?.fraction, 0.65);
      expect(StorageService.getSavedPageIndex(chapter.id), 4);
      expect(StorageService.getSavedWebtoonOffset(chapter.id), 1850);
    },
  );

  test(
    'simultaneous completion and recent-history writes are serialized',
    () async {
      await Future.wait([
        for (var i = 0; i < 8; i++)
          StorageService.markChapterAsRead(manga, chapter),
      ]);
      expect(StorageService.computeReadingMetrics().totalChaptersRead, 1);
      expect(StorageService.historyBox.get('reading_events_log'), hasLength(1));
      final other = Manga(
        id: 'second-manga',
        title: 'Outra obra',
        description: '',
        status: 'ONGOING',
        tags: const [],
      );
      await Future.wait([
        StorageService.recordChapterOpened(manga, chapter),
        StorageService.recordChapterOpened(other, chapter),
      ]);
      expect(
        StorageService.getContinueReadingList()
            .map((item) => (item['manga'] as Manga).id)
            .toSet(),
        {manga.id, other.id},
      );
    },
  );

  test(
    'corrupt legacy records do not hide valid library data or get deleted',
    () async {
      final broken = {...manga.toMap(), 'tags': 'not-a-list'};
      await StorageService.favBox.put('broken', broken);
      await StorageService.favBox.put(manga.id, manga.toMap());
      await StorageService.historyBox.put('recent_reading_list', [
        {'manga': 42, 'chapter': chapter.toMap()},
        {
          'manga': manga.toMap(),
          'chapter': {...chapter.toMap(), 'pages': 'broken'},
        },
        {'manga': manga.toMap(), 'chapter': chapter.toMap()},
      ]);
      await StorageService.historyBox.put('chapters_${manga.id}', [
        42,
        {...chapter.toMap(), 'pages': 'bad'},
        chapter.toMap(),
      ]);
      await StorageService.downloadsBox.put('broken', {
        'manga': 42,
        'chapter': chapter.toMap(),
      });
      await StorageService.downloadsBox.put(chapter.id, {
        'manga': manga.toMap(),
        'chapter': chapter.toMap(),
        'paths': ['valid-path'],
      });
      expect(StorageService.getFavorites().map((item) => item.id), [manga.id]);
      expect(StorageService.getContinueReadingList(), hasLength(1));
      expect(StorageService.getCachedMangaChapters(manga.id), hasLength(1));
      expect(StorageService.getAllDownloadedChapters(), hasLength(1));
      expect(StorageService.favBox.get('broken'), broken);
      expect(StorageService.downloadsBox.containsKey('broken'), isTrue);
    },
  );

  test(
    'invalid saved positions and incomplete path lists are rejected safely',
    () async {
      for (final value in <Object>[-1, '4', 3.5, false]) {
        await StorageService.historyBox.put('page_${chapter.id}', value);
        expect(StorageService.getSavedPageIndex(chapter.id), 0);
      }
      await StorageService.saveLastPageIndex(chapter.id, 4);
      await StorageService.saveLastPageIndex(chapter.id, -2);
      expect(StorageService.getSavedPageIndex(chapter.id), 4);
      for (final paths in <Object>[
        'path',
        ['valid', 42],
        ['valid', ''],
      ]) {
        await StorageService.downloadsBox.put(chapter.id, {'paths': paths});
        expect(StorageService.getDownloadedChapterPaths(chapter.id), isEmpty);
      }
    },
  );

  test('unknown chapter lengths never fabricate read pages', () async {
    final unknown = Chapter(
      id: 'unknown',
      chapterNumber: '2',
      title: '',
      language: 'PT-BR',
      pages: 0,
    );
    await StorageService.markChapterAsRead(manga, unknown);
    final metrics = StorageService.computeReadingMetrics();
    expect(metrics.totalChaptersRead, 1);
    expect(metrics.totalPagesRead, 0);
    expect(metrics.longestChapterRead, isNull);
    expect(metrics.shortestChapterRead, isNull);
  });

  test(
    'legacy duplicate events and unknown dates do not inflate daily metrics',
    () async {
      final event = {
        'chapterId': chapter.id,
        'mangaMap': manga.toMap(),
        'chapterMap': chapter.toMap(),
        'pages': chapter.pages,
        'readAt': 'unknown',
      };
      await StorageService.historyBox.put('reading_events_log', [
        event,
        event,
        {'mangaMap': 42},
      ]);
      final metrics = StorageService.computeReadingMetrics();
      expect(metrics.totalChaptersRead, 1);
      expect(metrics.totalPagesRead, chapter.pages);
      expect(metrics.chaptersReadToday, 0);
      expect(metrics.chaptersReadThisWeek, 0);
      final now = DateTime.now();
      await StorageService.historyBox.put('reading_events_log', [
        {
          ...event,
          'readAt': DateTime(now.year, now.month, now.day).toIso8601String(),
        },
      ]);
      expect(StorageService.computeReadingMetrics().chaptersReadToday, 1);
    },
  );

  test(
    'an invalid recovery journal cannot partially roll back good sections',
    () async {
      final current = {...manga.toMap(), 'title': 'Current data'};
      await StorageService.favBox.put(manga.id, current);
      await StorageService.settingsBox.put(StorageService.restoreJournalKey, {
        'favorites': {
          manga.id: {'exists': true, 'value': manga.toMap()},
        },
        'history': 'broken section',
        'settings': {},
      });
      await expectLater(
        StorageService.recoverInterruptedRestore(),
        throwsFormatException,
      );
      expect(StorageService.favBox.get(manga.id), current);
      expect(
        StorageService.settingsBox.containsKey(
          StorageService.restoreJournalKey,
        ),
        isTrue,
      );
    },
  );
}
