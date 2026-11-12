import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'reader_image_session.dart';

import 'package:path_provider/path_provider.dart';

import '../models/manga_models.dart';
import 'mangadex_service.dart';
import 'storage_service.dart';
import 'image_file_validator.dart';

class DownloadManager {
  static final ValueNotifier<Map<String, double>> activeDownloads =
      ValueNotifier({});

  /// Rastreia downloads de obras inteiras em lote: `mangaId -> (concluídos, total)`
  static final ValueNotifier<Map<String, ({int completed, int total})>>
  activeMangaDownloads = ValueNotifier({});

  static final _inFlight = <String, Future<void>>{};
  static final Map<String, Future<String?>> _inFlightCovers = {};
  static final _deletingChapters = <String>{};
  static bool _deletingAll = false;

  static bool isDownloading(String chapterId) =>
      _inFlight.containsKey(chapterId);

  static bool isDownloadingManga(String mangaId) =>
      activeMangaDownloads.value.containsKey(mangaId);

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

  /// Seleciona uma lista limpa de capítulos únicos por número para download da obra inteira,
  /// priorizando PT-BR quando houver múltiplas traduções do mesmo número.
  static List<Chapter> deduplicateForBatchDownload(List<Chapter> chapters) {
    final byNum = <String, Chapter>{};
    for (final ch in chapters) {
      final key = ch.chapterNumber.trim().isEmpty
          ? ch.id
          : ch.chapterNumber.trim();
      final existing = byNum[key];
      if (existing == null) {
        byNum[key] = ch;
      } else {
        final existingPt = existing.language.toUpperCase().contains('PT');
        final newPt = ch.language.toUpperCase().contains('PT');
        if (!existingPt && newPt) {
          byNum[key] = ch;
        }
      }
    }
    final list = byNum.values.toList()
      ..sort((a, b) => a.numericChapter.compareTo(b.numericChapter));
    return list;
  }

  /// Baixa uma obra inteira (todos os capítulos fornecidos) e garante que ela
  /// seja automaticamente adicionada à Biblioteca e fique disponível offline.
  static Future<int> downloadManga({
    required Manga manga,
    required List<Chapter> chapters,
    bool useDataSaver = false,
  }) async {
    final uniqueChapters = deduplicateForBatchDownload(chapters);
    if (uniqueChapters.isEmpty) return 0;

    // Adiciona imediatamente à Biblioteca e salva o índice de capítulos para leitura offline
    await StorageService.ensureInLibrary(manga, chapters: uniqueChapters);

    final total = uniqueChapters.length;
    int completedCount = 0;
    _updateMangaProgress(manga.id, completed: 0, total: total);

    try {
      for (final chapter in uniqueChapters) {
        try {
          await downloadChapter(
            manga: manga,
            chapter: chapter,
            useDataSaver: useDataSaver,
          );
          completedCount++;
        } catch (_) {
          // Continua com os próximos capítulos caso um capítulo específico falhe
        }
        _updateMangaProgress(
          manga.id,
          completed: completedCount,
          total: total,
        );
      }
      return completedCount;
    } finally {
      _removeMangaProgress(manga.id);
    }
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
      if (await hasCompleteDownload(chapter.id)) {
        await StorageService.ensureInLibrary(manga, chapters: [chapter]);
        return;
      }
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

    final session = ReaderImageSession(
      urls: urls,
      headers: manga.customHeaders,
      maxCacheBytes: 0,
      reloadUrls: () async =>
          (await MangaDexService.fetchChapterPages(chapter))
              .getUrls(useDataSaver: useDataSaver),
    );
    try {
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
              final bytes = await session.pageBytes(pageIndex);
              // A gravação temporária evita tratar arquivos incompletos como válidos.
              final temporary = File('${file.path}.part');
              await temporary.writeAsBytes(bytes, flush: true);
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
    } finally {
      session.close();
    }

    final coverPath = await ensureOfflineCover(manga);
    await StorageService.downloadsBox.put(chapter.id, {
      'chapter': chapter.toMap(),
      'manga': manga.toMap(),
      'paths': savedPaths,
      'coverPath': ?coverPath,
      'downloadedAt': DateTime.now().toIso8601String(),
    });

    // Garante que toda obra baixada entre automaticamente para a Biblioteca e funcione offline
    await StorageService.ensureInLibrary(manga, chapters: [chapter]);
  }

  /// Baixa e armazena a capa da obra de forma persistente uma única vez.
  /// Falhas na capa nunca invalidam os capítulos já baixados.
  static Future<String?> ensureOfflineCover(Manga manga) {
    final existing = StorageService.getOfflineCoverPath(manga.id);
    if (existing != null) return Future.value(existing);
    final pending = _inFlightCovers[manga.id];
    if (pending != null) return pending;
    final future = _downloadAndPersistCover(manga);
    _inFlightCovers[manga.id] = future;
    return future.whenComplete(() => _inFlightCovers.remove(manga.id));
  }

  static Future<String?> _downloadAndPersistCover(Manga manga) async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final coversDir = Directory('${baseDir.path}/covers');
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      final safeMangaId = manga.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFile = File('${coversDir.path}/cover_$safeMangaId.img');
      if (await ImageFileValidator.isCompleteImage(targetFile)) {
        await StorageService.setOfflineCoverPath(manga.id, targetFile.path);
        return targetFile.path;
      }
      final candidates = manga.getAllCandidateCoverUrls(highRes: false);
      if (candidates.isEmpty) return null;
      final session = ReaderImageSession(
        urls: [candidates.first],
        headers: manga.customHeaders,
        maxCacheBytes: 0,
      );
      try {
        final bytes = await session.pageBytes(0);
        final partFile = File('${targetFile.path}.part');
        await partFile.writeAsBytes(bytes, flush: true);
        if (!await ImageFileValidator.isCompleteImage(partFile)) {
          await partFile.delete();
          return null;
        }
        if (await targetFile.exists()) await targetFile.delete();
        await partFile.rename(targetFile.path);
        await StorageService.setOfflineCoverPath(manga.id, targetFile.path);
        return targetFile.path;
      } finally {
        session.close();
      }
    } catch (_) {
      // Falha na capa não invalida capítulos baixados
      return null;
    }
  }

  static Future<void> deleteChapter(String chapterId) async {
    if (_deletingAll ||
        isDownloading(chapterId) ||
        !_deletingChapters.add(chapterId)) {
      throw StateError('Aguarde o download ou a limpeza em andamento.');
    }
    try {
      final raw = StorageService.downloadsBox.get(chapterId);
      String? mangaId;
      if (raw is Map && raw['manga'] is Map) {
        mangaId = raw['manga']['id']?.toString();
      }
      final baseDir = await getApplicationSupportDirectory();
      final safeChapterId = chapterId.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final chapterDir = Directory('${baseDir.path}/chapters/$safeChapterId');
      if (await chapterDir.exists()) await chapterDir.delete(recursive: true);
      await StorageService.downloadsBox.delete(chapterId);
      if (mangaId != null && mangaId.isNotEmpty) {
        final remaining = StorageService.countDownloadedChaptersForManga(mangaId);
        if (remaining == 0) {
          await _deleteCoverIfUnreferenced(mangaId, baseDir);
        }
      }
    } finally {
      _deletingChapters.remove(chapterId);
    }
  }

  static Future<void> deleteMangaDownloads(String mangaId) async {
    final chapters = StorageService.getDownloadedChaptersForManga(mangaId);
    for (final ch in chapters) {
      await deleteChapter(ch.id);
    }
  }

  static Future<void> _deleteCoverIfUnreferenced(
    String mangaId,
    Directory baseDir,
  ) async {
    final storedPath = StorageService.getOfflineCoverPath(mangaId);
    await StorageService.removeOfflineCoverMetadata(mangaId);
    final safeMangaId = mangaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    for (final path in <String>{
      ?storedPath,
      '${baseDir.path}/covers/cover_$safeMangaId.img',
    }) {
      final stillUsed = StorageService.downloadsBox.values.any(
        (v) => v is Map && v['coverPath'] == path,
      );
      if (!stillUsed) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
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
      final coversDir = Directory('${baseDir.path}/covers');
      if (await coversDir.exists()) {
        await coversDir.delete(recursive: true);
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

  static void _updateMangaProgress(
    String mangaId, {
    required int completed,
    required int total,
  }) {
    final current = Map<String, ({int completed, int total})>.from(
      activeMangaDownloads.value,
    );
    current[mangaId] = (completed: completed, total: total);
    activeMangaDownloads.value = current;
  }

  static void _removeMangaProgress(String mangaId) {
    final current = Map<String, ({int completed, int total})>.from(
      activeMangaDownloads.value,
    );
    current.remove(mangaId);
    activeMangaDownloads.value = current;
  }
}
