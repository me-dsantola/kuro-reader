import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/manga_models.dart';
import 'mangadex_service.dart';
import 'storage_service.dart';

class DownloadManager {
  static final ValueNotifier<Map<String, double>> activeDownloads =
      ValueNotifier({});

  static bool isDownloading(String chapterId) =>
      activeDownloads.value.containsKey(chapterId);

  /// A Hive index alone does not prove every offline page still exists.
  static Future<bool> hasCompleteDownload(String chapterId) async {
    if (!StorageService.isChapterDownloaded(chapterId)) return false;
    final paths = StorageService.getDownloadedChapterPaths(chapterId);
    if (paths.isEmpty || paths.any((path) => path.isEmpty)) return false;
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) return false;
    }
    return true;
  }

  static Future<void> downloadChapter({
    required Manga manga,
    required Chapter chapter,
    bool useDataSaver = false,
  }) async {
    if (isDownloading(chapter.id)) return;
    if (StorageService.isChapterDownloaded(chapter.id)) {
      if (await hasCompleteDownload(chapter.id)) return;
      // Metadata was stale. Reuse valid partial page files on the next pass.
      await StorageService.downloadsBox.delete(chapter.id);
    }

    _updateProgress(chapter.id, 0.01);

    try {
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
        final end =
            (i + batchSize < urls.length) ? i + batchSize : urls.length;
        final batchIndices = List.generate(end - i, (index) => i + index);

        await Future.wait(batchIndices.map((pageIndex) async {
          final url = urls[pageIndex];
          String ext = 'jpg';
          final rawExt = url.split('.').last.split('?').first.toLowerCase();
          if (rawExt == 'png' || rawExt == 'webp' || rawExt == 'jpg' || rawExt == 'jpeg') {
            ext = rawExt;
          }
          final fileName = '${pageIndex.toString().padLeft(3, '0')}.$ext';
          final file = File('${chapterDir.path}/$fileName');

          // Reaproveita páginas completas de uma tentativa anterior.
          if (await file.exists() && await file.length() > 0) {
            savedPaths[pageIndex] = file.path;
          } else {
            final response = await http.get(
              Uri.parse(url),
              headers: manga.customHeaders,
            ).timeout(const Duration(seconds: 30));
            if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
              throw Exception('Falha ao baixar página ${pageIndex + 1}');
            }
            // A gravação temporária evita tratar arquivos incompletos como válidos.
            final temporary = File('${file.path}.part');
            await temporary.writeAsBytes(response.bodyBytes, flush: true);
            await temporary.rename(file.path);
            savedPaths[pageIndex] = file.path;
          }

          completed++;
          _updateProgress(chapter.id, completed / urls.length);
        }));
      }

      await StorageService.downloadsBox.put(chapter.id, {
        'chapter': chapter.toMap(),
        'manga': manga.toMap(),
        'paths': savedPaths,
        'downloadedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Preserva as páginas já concluídas para retomar na próxima tentativa.
      rethrow;
    } finally {
      _removeProgress(chapter.id);
    }
  }

  static Future<void> deleteChapter(String chapterId) async {
    final baseDir = await getApplicationSupportDirectory();
    final safeChapterId = chapterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final chapterDir = Directory('${baseDir.path}/chapters/$safeChapterId');
    if (await chapterDir.exists()) {
      await chapterDir.delete(recursive: true);
    }
    await StorageService.downloadsBox.delete(chapterId);
  }

  static Future<void> deleteAllDownloads() async {
    final baseDir = await getApplicationSupportDirectory();
    final rootChaptersDir = Directory('${baseDir.path}/chapters');
    if (await rootChaptersDir.exists()) {
      await rootChaptersDir.delete(recursive: true);
    }
    await StorageService.downloadsBox.clear();
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
