import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'observed_http.dart';
import 'package:path_provider/path_provider.dart';
import '../models/manga_models.dart';
import 'mangadex_service.dart';
import 'storage_service.dart';
import 'image_file_validator.dart';

class DownloadManager {
  static final ValueNotifier<Map<String, double>> activeDownloads =
      ValueNotifier({});

  static final _inFlight = <String, Future<void>>{};
  static final _deletingChapters = <String>{};
  static bool _deletingAll = false;

  static bool isDownloading(String chapterId) =>
      _inFlight.containsKey(chapterId);

  /// A Hive index alone does not prove every offline page still exists.
  static Future<bool> hasCompleteDownload(String chapterId) async {
    if (!StorageService.isChapterDownloaded(chapterId)) return false;
    final paths = StorageService.getDownloadedChapterPaths(chapterId);
    if (paths.isEmpty || paths.any((path) => path.isEmpty)) return false;
    for (final path in paths) {
      final file = File(path);
      if (!await ImageFileValidator.isCompleteImage(file)) return false;
    }
    return true;
  }

  static Future<void> downloadChapter({
    required Manga manga,
    required Chapter chapter,
    bool useDataSaver = false,
  }) {
    final pending = _inFlight[chapter.id];
    if (pending != null) return pending;
    if (_deletingAll || _deletingChapters.contains(chapter.id)) {
      return Future.error(StateError('Aguarde a limpeza dos downloads.'));
    }
    final result = Completer<void>();
    _inFlight[chapter.id] = result.future;
    _updateProgress(chapter.id, 0.01);
    () async {
      try {
        await _downloadChapter(manga, chapter, useDataSaver);
        result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _inFlight.remove(chapter.id);
        _removeProgress(chapter.id);
      }
    }();
    return result.future;
  }

  static Future<void> _downloadChapter(
    Manga manga,
    Chapter chapter,
    bool useDataSaver,
  ) async {
    if (StorageService.isChapterDownloaded(chapter.id)) {
      if (await hasCompleteDownload(chapter.id)) return;
      // Reuse only verified page files from an interrupted attempt.
      await StorageService.downloadsBox.delete(chapter.id);
    }

    final pagesData = await MangaDexService.fetchChapterPages(chapter);
    final urls = pagesData.getUrls(useDataSaver: useDataSaver);

    if (urls.isEmpty) throw Exception('Capítulo sem páginas disponíveis.');

    final baseDir = await getApplicationSupportDirectory();
    final safeChapterId = chapter.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final chapterDir = Directory('${baseDir.path}/chapters/$safeChapterId');
    if (!await chapterDir.exists()) {
      await chapterDir.create(recursive: true);
    }

    final List<String> savedPaths = List.filled(urls.length, '');
    int completed = 0;
    const int batchSize = 3;

    for (int i = 0; i < urls.length; i += batchSize) {
      final end = (i + batchSize < urls.length) ? i + batchSize : urls.length;
      final batchIndices = List.generate(end - i, (index) => i + index);

      await Future.wait(
        batchIndices.map((pageIndex) async {
          final url = urls[pageIndex];
          String ext = 'jpg';
          final rawExt = url.split('.').last.split('?').first.toLowerCase();
          if (rawExt == 'png' ||
              rawExt == 'webp' ||
              rawExt == 'jpg' ||
              rawExt == 'jpeg') {
            ext = rawExt;
          }
          final fileName = '${pageIndex.toString().padLeft(3, '0')}.$ext';
          final file = File('${chapterDir.path}/$fileName');

          // Reaproveita páginas completas de uma tentativa anterior.
          if (await ImageFileValidator.isCompleteImage(file)) {
            savedPaths[pageIndex] = file.path;
          } else {
            final response = await ObservedHttp.get(
              Uri.parse(url),
              headers: manga.customHeaders,
              timeout: const Duration(seconds: 30),
            ).timeout(const Duration(seconds: 30));
            if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
              throw Exception('Falha ao baixar página ${pageIndex + 1}');
            }
            // A gravação temporária evita tratar arquivos incompletos como válidos.
            final temporary = File('${file.path}.part');
            await temporary.writeAsBytes(response.bodyBytes, flush: true);
            if (!await ImageFileValidator.isCompleteImage(temporary)) {
              await temporary.delete();
              throw FormatException(
                'Imagem inválida na página ${pageIndex + 1}',
              );
            }
            if (await file.exists()) await file.delete();
            await temporary.rename(file.path);
            savedPaths[pageIndex] = file.path;
          }

          completed++;
          _updateProgress(chapter.id, completed / urls.length);
        }),
      );
    }

    await StorageService.downloadsBox.put(chapter.id, {
      'chapter': chapter.toMap(),
      'manga': manga.toMap(),
      'paths': savedPaths,
      'downloadedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteChapter(String chapterId) async {
    if (_deletingAll ||
        isDownloading(chapterId) ||
        !_deletingChapters.add(chapterId)) {
      throw StateError('Aguarde o download ou a limpeza em andamento.');
    }
    try {
      final baseDir = await getApplicationSupportDirectory();
      final safeChapterId = chapterId.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final chapterDir = Directory('${baseDir.path}/chapters/$safeChapterId');
      if (await chapterDir.exists()) await chapterDir.delete(recursive: true);
      await StorageService.downloadsBox.delete(chapterId);
    } finally {
      _deletingChapters.remove(chapterId);
    }
  }

  static Future<void> deleteAllDownloads() async {
    if (_deletingAll || _inFlight.isNotEmpty || _deletingChapters.isNotEmpty) {
      throw StateError('Aguarde os downloads ou a limpeza em andamento.');
    }
    _deletingAll = true;
    try {
      final baseDir = await getApplicationSupportDirectory();
      final rootChaptersDir = Directory('${baseDir.path}/chapters');
      if (await rootChaptersDir.exists()) {
        await rootChaptersDir.delete(recursive: true);
      }
      await StorageService.downloadsBox.clear();
    } finally {
      _deletingAll = false;
    }
  }

  static void _updateProgress(String chapterId, double progress) {
    final current = Map<String, double>.from(activeDownloads.value);
    current[chapterId] = progress;
    activeDownloads.value = current;
  }

  static void _removeProgress(String chapterId) {
    final current = Map<String, double>.from(activeDownloads.value);
    current.remove(chapterId);
    activeDownloads.value = current;
  }
}
