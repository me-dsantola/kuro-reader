import 'dart:io';
import 'package:flutter/foundation.dart';

enum ChapterDownloadState {
  queued,
  downloading,
  completed,
  paused,
  failed,
}

class DownloadedChapterRecord {
  final String chapterId;
  final String mangaId;
  final String mangaTitle;
  final String chapterTitle;
  final double chapterNumber;
  final String localDirectoryPath;
  final ChapterDownloadState state;
  final double progress;
  final String? remoteCoverUrl;
  final String? localCoverPath;

  const DownloadedChapterRecord({
    required this.chapterId,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterTitle,
    required this.chapterNumber,
    required this.localDirectoryPath,
    required this.state,
    this.progress = 1.0,
    this.remoteCoverUrl,
    this.localCoverPath,
  });

  DownloadedChapterRecord copyWith({
    ChapterDownloadState? state,
    double? progress,
    String? localCoverPath,
  }) {
    return DownloadedChapterRecord(
      chapterId: chapterId,
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
      chapterNumber: chapterNumber,
      localDirectoryPath: localDirectoryPath,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      remoteCoverUrl: remoteCoverUrl,
      localCoverPath: localCoverPath ?? this.localCoverPath,
    );
  }

  /// Migra registros legados planos que não possuíam chapterNumber ou localCoverPath estruturados.
  factory DownloadedChapterRecord.fromLegacyMap(Map<String, dynamic> map) {
    final rawNumber = map['chapterNumber'];
    final parsedNumber = rawNumber is num
        ? rawNumber.toDouble()
        : double.tryParse(
            RegExp(r'(\d+(\.\d+)?)')
                    .firstMatch(map['chapterTitle']?.toString() ?? '')
                    ?.group(1) ??
                '0',
          ) ??
          0.0;
    return DownloadedChapterRecord(
      chapterId: map['chapterId'] as String,
      mangaId: (map['mangaId'] ?? map['seriesId'] ?? 'unknown_manga') as String,
      mangaTitle: (map['mangaTitle'] ?? map['seriesTitle'] ?? 'Obra') as String,
      chapterTitle: (map['chapterTitle'] ?? 'Capítulo') as String,
      chapterNumber: parsedNumber,
      localDirectoryPath: map['localDirectoryPath'] as String,
      state: ChapterDownloadState.values.firstWhere(
        (e) => e.name == (map['state'] ?? 'completed'),
        orElse: () => ChapterDownloadState.completed,
      ),
      progress: (map['progress'] as num?)?.toDouble() ?? 1.0,
      remoteCoverUrl: map['remoteCoverUrl'] as String?,
      localCoverPath: map['localCoverPath'] as String?,
    );
  }
}

class MangaDownloadGroup {
  final String mangaId;
  final String mangaTitle;
  final String? localCoverPath;
  final String? remoteCoverUrl;
  final List<DownloadedChapterRecord> chapters; // Ordenados por chapterNumber

  const MangaDownloadGroup({
    required this.mangaId,
    required this.mangaTitle,
    this.localCoverPath,
    this.remoteCoverUrl,
    required this.chapters,
  });

  int get completedCount =>
      chapters.where((c) => c.state == ChapterDownloadState.completed).length;

  bool get hasActiveDownloads => chapters.any(
        (c) =>
            c.state == ChapterDownloadState.downloading ||
            c.state == ChapterDownloadState.queued,
      );

  bool get hasFailures =>
      chapters.any((c) => c.state == ChapterDownloadState.failed);

  double get aggregateProgress {
    if (chapters.isEmpty) return 0.0;
    final total = chapters.fold<double>(0.0, (sum, c) => sum + c.progress);
    return (total / chapters.length).clamp(0.0, 1.0);
  }
}

class GroupedDownloadsManager extends ChangeNotifier {
  final Directory persistentCoversDir;
  final Future<Uint8List?> Function(String url) coverDownloader;
  final Map<String, DownloadedChapterRecord> _recordsByChapterId = {};
  final Map<String, String> _coverPathByMangaId = {};
  final Map<String, Future<String?>> _inFlightCoverDownloads = {};

  GroupedDownloadsManager({
    required this.persistentCoversDir,
    required this.coverDownloader,
  });

  /// Retorna os downloads agrupados por obra e com capítulos ordenados numericamente.
  List<MangaDownloadGroup> get groups {
    final grouped = <String, List<DownloadedChapterRecord>>{};
    for (final record in _recordsByChapterId.values) {
      grouped.putIfAbsent(record.mangaId, () => []).add(record);
    }
    final result = <MangaDownloadGroup>[];
    grouped.forEach((mangaId, list) {
      list.sort((a, b) {
        final cmp = a.chapterNumber.compareTo(b.chapterNumber);
        return cmp != 0 ? cmp : a.chapterTitle.compareTo(b.chapterTitle);
      });
      final first = list.first;
      final resolvedCover = _coverPathByMangaId[mangaId] ??
          list
              .map((c) => c.localCoverPath)
              .firstWhere(
                (p) => p != null && File(p).existsSync(),
                orElse: () => null,
              );
      result.add(
        MangaDownloadGroup(
          mangaId: mangaId,
          mangaTitle: first.mangaTitle,
          localCoverPath: resolvedCover,
          remoteCoverUrl: first.remoteCoverUrl,
          chapters: List.unmodifiable(list),
        ),
      );
    });
    result.sort((a, b) =>
        a.mangaTitle.toLowerCase().compareTo(b.mangaTitle.toLowerCase()));
    return result;
  }

  /// Migra registros legados sem invalidar os capítulos já salvos e agenda persistência da capa.
  Future<void> migrateLegacyDownloads(
      List<Map<String, dynamic>> rawRecords) async {
    if (!persistentCoversDir.existsSync()) {
      await persistentCoversDir.create(recursive: true);
    }
    for (final raw in rawRecords) {
      final migrated = DownloadedChapterRecord.fromLegacyMap(raw);
      final existingCoverFile = _expectedCoverFile(migrated.mangaId);
      final validCoverPath = existingCoverFile.existsSync() &&
              existingCoverFile.lengthSync() > 0
          ? existingCoverFile.path
          : migrated.localCoverPath;
      if (validCoverPath != null && File(validCoverPath).existsSync()) {
        _coverPathByMangaId[migrated.mangaId] = validCoverPath;
      }
      _recordsByChapterId[migrated.chapterId] = migrated.copyWith(
        localCoverPath: _coverPathByMangaId[migrated.mangaId],
      );
    }
    notifyListeners();
    // Tenta baixar capas faltantes de forma oportunista sem falhar os capítulos
    for (final group in groups) {
      if (group.localCoverPath == null && group.remoteCoverUrl != null) {
        await ensureOfflineCover(
          mangaId: group.mangaId,
          remoteCoverUrl: group.remoteCoverUrl!,
        );
      }
    }
  }

  File _expectedCoverFile(String mangaId) {
    final safeId = mangaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${persistentCoversDir.path}/cover_$safeId.bin');
  }

  /// Baixa e persiste a capa uma única vez por obra.
  /// Falhas na capa NÃO invalidam capítulos baixados.
  Future<String?> ensureOfflineCover({
    required String mangaId,
    required String remoteCoverUrl,
  }) async {
    final existingPath = _coverPathByMangaId[mangaId];
    if (existingPath != null) {
      final f = File(existingPath);
      if (f.existsSync() && f.lengthSync() > 0) {
        return existingPath;
      }
    }
    final targetFile = _expectedCoverFile(mangaId);
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      _coverPathByMangaId[mangaId] = targetFile.path;
      _propagateCoverPath(mangaId, targetFile.path);
      return targetFile.path;
    }
    if (_inFlightCoverDownloads.containsKey(mangaId)) {
      return _inFlightCoverDownloads[mangaId];
    }
    final future = _downloadAndSaveCover(mangaId, remoteCoverUrl, targetFile);
    _inFlightCoverDownloads[mangaId] = future;
    try {
      return await future;
    } finally {
      _inFlightCoverDownloads.remove(mangaId);
    }
  }

  Future<String?> _downloadAndSaveCover(
    String mangaId,
    String url,
    File targetFile,
  ) async {
    try {
      if (!persistentCoversDir.existsSync()) {
        await persistentCoversDir.create(recursive: true);
      }
      final bytes = await coverDownloader(url);
      if (bytes == null || bytes.isEmpty) return null;
      final tempFile = File('${targetFile.path}.tmp');
      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(targetFile.path);
      _coverPathByMangaId[mangaId] = targetFile.path;
      _propagateCoverPath(mangaId, targetFile.path);
      notifyListeners();
      return targetFile.path;
    } catch (_) {
      // Falha silenciosa: preserva capítulos baixados intactos
      return null;
    }
  }

  void _propagateCoverPath(String mangaId, String coverPath) {
    for (final entry in _recordsByChapterId.entries.toList()) {
      if (entry.value.mangaId == mangaId) {
        _recordsByChapterId[entry.key] =
            entry.value.copyWith(localCoverPath: coverPath);
      }
    }
  }

  Future<void> addOrUpdateChapterDownload(
      DownloadedChapterRecord record) async {
    _recordsByChapterId[record.chapterId] = record;
    notifyListeners();
    if (record.remoteCoverUrl != null) {
      await ensureOfflineCover(
        mangaId: record.mangaId,
        remoteCoverUrl: record.remoteCoverUrl!,
      );
    }
  }

  /// Remove um capítulo baixado e só exclui a capa offline se nenhum outro capítulo
  /// da mesma obra continuar usando a capa. Não altera favoritos, histórico ou progresso.
  Future<void> deleteChapterDownload(String chapterId) async {
    final removed = _recordsByChapterId.remove(chapterId);
    if (removed == null) return;
    final chapterDir = Directory(removed.localDirectoryPath);
    if (chapterDir.existsSync()) {
      await chapterDir.delete(recursive: true);
    }
    final remainingForManga = _recordsByChapterId.values
        .where((c) => c.mangaId == removed.mangaId)
        .toList();
    if (remainingForManga.isEmpty) {
      await _removeCoverIfUnused(removed.mangaId, removed.localCoverPath);
    }
    notifyListeners();
  }

  /// Remove todos os capítulos baixados de uma obra e sua capa offline associada.
  Future<void> deleteMangaGroup(String mangaId) async {
    final chaptersToDelete = _recordsByChapterId.values
        .where((c) => c.mangaId == mangaId)
        .map((c) => c.chapterId)
        .toList();
    for (final chapterId in chaptersToDelete) {
      await deleteChapterDownload(chapterId);
    }
  }

  Future<void> _removeCoverIfUnused(String mangaId, String? coverPath) async {
    final pathToClean = coverPath ?? _coverPathByMangaId.remove(mangaId);
    if (pathToClean == null) return;
    // Verifica se algum outro grupo compartilha o mesmo caminho de arquivo
    final stillReferenced = _recordsByChapterId.values.any(
      (c) => c.localCoverPath == pathToClean,
    );
    if (!stillReferenced) {
      final file = File(pathToClean);
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }
}
