import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/services/backup_codec.dart';

void main() {
  final legacy = {
    'version': 3,
    'profile': {'name': 'Leitor'},
    'favorites': {
      'manga-id': {'id': 'manga-id', 'title': 'Minha obra'},
    },
    'history': {'page_chapter-id': 6},
    'settings': {'data_saver_mode': true},
  };

  test('accepts v3 backups and preserves history and favorites', () {
    final decoded = BackupCodec.decode(BackupCodec.encode(legacy));
    expect(decoded['version'], 3);
    expect((decoded['favorites'] as Map)['manga-id']['title'], 'Minha obra');
    expect((decoded['history'] as Map)['page_chapter-id'], 6);
  });

  test('accepts legacy JSON exports without a version', () {
    expect(
      BackupCodec.decode('{"profile":{"name":"Leitor antigo"}}')['profile'],
      {'name': 'Leitor antigo'},
    );
  });

  test('rejects unsupported backup versions', () {
    final newer = {...legacy, 'version': BackupCodec.currentVersion + 1};
    expect(
      () => BackupCodec.decode(BackupCodec.encode(newer)),
      throwsFormatException,
    );
  });

  test('rejects broken favorite data before any restore', () {
    final malformed = {
      ...legacy,
      'favorites': {'bad': 'not a manga object'},
    };
    expect(
      () => BackupCodec.decode(BackupCodec.encode(malformed)),
      throwsFormatException,
    );
  });

  test('rejects unknown and empty documents', () {
    expect(() => BackupCodec.decode('{}'), throwsFormatException);
    expect(() => BackupCodec.decode(''), throwsFormatException);
  });

  for (final bad in <String, Object>{
    'tags': 'Aventura',
    'availableChaptersCount': '30',
    'customHeaders': {'Accept': 42},
    'preloadedChapters': [false],
    'isNsfw': 'false',
  }.entries) {
    test('rejects malformed favorite ${bad.key}', () {
      expect(
        () => BackupCodec.decode(
          BackupCodec.encode({
            'favorites': {
              'manga-id': {
                'id': 'manga-id',
                'title': 'Obra',
                bad.key: bad.value,
              },
            },
          }),
        ),
        throwsFormatException,
      );
    });
  }

  for (final bad in <String, Object>{
    'page_chapter': '3',
    'read_chapter': 'true',
    'webtoon_offset_chapter': -1,
    'webtoon_anchor_chapter': {'page': 3, 'fraction': 1.5},
    'chapters_count_manga': 2.5,
    'last_manga': {'id': 'chapter', 'pages': '15'},
    'chapters_manga': [42],
    'recent_reading_list': [
      {'manga': {}, 'chapter': {}},
    ],
    'reading_events_log': [
      {'pages': '22'},
    ],
  }.entries) {
    test('rejects malformed history ${bad.key}', () {
      expect(
        () => BackupCodec.decode(
          BackupCodec.encode({
            'history': {bad.key: bad.value},
          }),
        ),
        throwsFormatException,
      );
    });
  }

  test('rejects invalid profile and settings types', () {
    expect(
      () => BackupCodec.decode('{"profile":{"avatarIndex":"2"}}'),
      throwsFormatException,
    );
    expect(
      () => BackupCodec.decode(
        '{"profile":{},"settings":{"data_saver_mode":"false"}}',
      ),
      throwsFormatException,
    );
  });

  test('preserves unknown legacy keys with valid JSON values', () {
    final decoded = BackupCodec.decode(
      '{"history":{"legacy_preference":{"enabled":true}}}',
    );
    expect(decoded['history']['legacy_preference']['enabled'], isTrue);
  });

  test(
    'stripEphemeralCacheForCloud removes chapter caches and caps history lists',
    () {
      final rawRecent = List.generate(
        40,
        (i) => {
          'manga': {'id': 'm-$i', 'title': 'Manga $i'},
          'chapter': {'id': 'c-$i'},
          'timestamp': '2026-11-15T00:${i.toString().padLeft(2, '0')}:00Z',
        },
      );
      final rawEvents = List.generate(
        180,
        (i) => {
          'mangaMap': {'id': 'm-$i', 'title': 'Manga $i'},
          'chapterMap': {'id': 'c-$i'},
          'chapterId': 'c-$i',
          'mangaId': 'm-$i',
          'mangaTitle': 'Manga $i',
          'readAt': '2026-11-15T00:00:00Z',
        },
      );

      final compacted = BackupCodec.stripEphemeralCacheForCloud({
        'version': 4,
        'history': {
          'chapters_manga-1': [
            {'id': 'ch-1', 'chapterNumber': '1'},
          ],
          'chapters_count_manga-1': 125,
          'page_ch-1': 7,
          'recent_reading_list': rawRecent,
          'reading_events_log': rawEvents,
        },
      });

      final history = compacted['history'] as Map<String, dynamic>;
      expect(history.containsKey('chapters_manga-1'), isFalse);
      expect(history['chapters_count_manga-1'], 125);
      expect(history['page_ch-1'], 7);
      expect((history['recent_reading_list'] as List).length, 30);
      final keptEvents = history['reading_events_log'] as List;
      expect(keptEvents.length, 150);
      expect((keptEvents.first as Map)['chapterId'], 'c-30');
      expect((keptEvents.last as Map)['chapterId'], 'c-179');
    },
  );

  test(
    'mergeCloudAndLocal preserves favorites, max pages, OR read flags, lists and newer profile',
    () {
      final cloud = <String, dynamic>{
        'version': 4,
        'profile': {'name': 'Nuvem', 'accentHex': '#38BDF8', 'isConfigured': true},
        'favorites': {
          'm-1': {'id': 'm-1', 'title': 'Manga 1', 'coverFileName': 'cloud.jpg'},
          'm-2': {'id': 'm-2', 'title': 'Manga 2'},
        },
        'history': {
          'read_c1': true,
          'read_c2': false,
          'page_c1': 12,
          'page_c2': 4,
        },
        'settings': {
          'user_reading_lists': [
            {
              'id': 'list-1',
              'name': 'Lendo',
              'mangas': [
                {'id': 'm-1', 'title': 'Manga 1'},
              ],
            },
          ],
        },
      };

      final local = <String, dynamic>{
        'version': 4,
        'profile': {'name': 'Local Antigo'},
        'favorites': {
          'm-1': {'id': 'm-1', 'title': 'Manga 1', 'coverFileName': ''},
          'm-3': {'id': 'm-3', 'title': 'Manga 3'},
        },
        'history': {
          'read_c1': false,
          'read_c2': true,
          'page_c1': 8,
          'page_c2': 19,
        },
        'settings': {
          'user_reading_lists': [
            {
              'id': 'list-1',
              'name': 'Lendo',
              'mangas': [
                {'id': 'm-1', 'title': 'Manga 1'},
                {'id': 'm-3', 'title': 'Manga 3'},
              ],
            },
          ],
        },
      };

      final merged = BackupCodec.mergeCloudAndLocal(
        cloud,
        local,
        cloudIsNewer: true,
      );

      final favs = merged['favorites'] as Map<String, dynamic>;
      expect(favs.keys, containsAll(['m-1', 'm-2', 'm-3']));
      expect((favs['m-1'] as Map)['coverFileName'], 'cloud.jpg');

      final history = merged['history'] as Map<String, dynamic>;
      expect(history['read_c1'], isTrue);
      expect(history['read_c2'], isTrue);
      expect(history['page_c1'], 12);
      expect(history['page_c2'], 19);

      final lists =
          (merged['settings'] as Map<String, dynamic>)['user_reading_lists']
              as List;
      expect(lists.length, 1);
      final listMangas = (lists.first as Map)['mangas'] as List;
      expect(listMangas.length, 2);
      expect(listMangas.map((m) => (m as Map)['id']), containsAll(['m-1', 'm-3']));

      final profile = merged['profile'] as Map<String, dynamic>;
      expect(profile['name'], 'Nuvem');
      expect(profile['isConfigured'], isTrue);
    },
  );
}
