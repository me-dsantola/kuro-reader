import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Centralized service to manage visible and private app file storage.
/// On Android, prioritizes accessible external storage (`Android/data/.../files/KuroReader`)
/// so that users can view, backup, or transfer downloaded chapters and covers via USB/Files app,
/// while providing transparent fallback to internal sandbox storage.
class AppDirectoryService {
  static Directory? _cachedDownloadsDir;

  /// Root directory for user-accessible data (chapters, covers, backups).
  static Future<Directory> getDownloadsDirectory() async {
    if (_cachedDownloadsDir != null && _cachedDownloadsDir!.existsSync()) {
      return _cachedDownloadsDir!;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final kuroDir = Directory('${ext.path}/KuroReader');
          if (!await kuroDir.exists()) {
            await kuroDir.create(recursive: true);
          }
          _cachedDownloadsDir = kuroDir;
          return kuroDir;
        }
      } catch (_) {}
    }

    final support = await getApplicationSupportDirectory();
    final kuroDir = Directory('${support.path}/KuroReader');
    if (!await kuroDir.exists()) {
      await kuroDir.create(recursive: true);
    }
    _cachedDownloadsDir = kuroDir;
    return kuroDir;
  }

  /// Directory where downloaded manga chapters are stored.
  static Future<Directory> getChaptersDirectory() async {
    final base = await getDownloadsDirectory();
    final chaptersDir = Directory('${base.path}/chapters');
    if (!await chaptersDir.exists()) {
      await chaptersDir.create(recursive: true);
    }
    return chaptersDir;
  }

  /// Directory where offline covers are saved.
  static Future<Directory> getCoversDirectory() async {
    final base = await getDownloadsDirectory();
    final coversDir = Directory('${base.path}/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    return coversDir;
  }

  /// Directory where user custom profile photos and banners are stored.
  static Future<Directory> getProfileMediaDirectory() async {
    final base = await getDownloadsDirectory();
    final mediaDir = Directory('${base.path}/profile_media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  /// List of candidate directories that may contain downloaded files
  /// (both modern external directory and legacy internal sandbox directory).
  static Future<List<Directory>> getAllCandidateBaseDirectories() async {
    final candidates = <Directory>[];
    try {
      final modern = await getDownloadsDirectory();
      candidates.add(modern);
    } catch (_) {}
    try {
      final legacy = await getApplicationSupportDirectory();
      candidates.add(legacy);
    } catch (_) {}
    return candidates;
  }
}
