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
}
