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
}
