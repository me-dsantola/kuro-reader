import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Only our dedicated temporary sessions are removed after a process restart.
class ReaderCacheDirectory {
  static Future<Directory>? _root;
  static Future<Directory> create() async {
    final root = await (_root ??= _prepare());
    return root.createTemp('session_');
  }

  static Future<Directory> _prepare() async {
    final temporary = await getTemporaryDirectory();
    final root = await Directory(
      '${temporary.path}/yomi_reader',
    ).create(recursive: true);
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory &&
          entity.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('session_')) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          /* Optional cache. */
        }
      }
    }
    return root;
  }
}
