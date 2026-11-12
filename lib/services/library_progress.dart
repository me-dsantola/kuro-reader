import 'dart:math' as math;
import '../models/manga_models.dart';
import 'storage_service.dart';
import 'mangadex_service.dart';

class LibraryProgress {
  final double? fraction;
  final bool started;
  final bool completed;
  const LibraryProgress({
    this.fraction,
    this.started = false,
    this.completed = false,
  });

  String get label =>
      fraction == null ? 'Em leitura' : '${(fraction! * 100).round()}% lido';

  static LibraryProgress forManga(Manga manga) {
    final chapters = <String, List<Chapter>>{};
    for (final chapter in [
      ...StorageService.getCachedMangaChapters(manga.id),
      ...StorageService.getDownloadedChaptersForManga(manga.id),
      ...?manga.preloadedChapters,
    ]) {
      final key =
          double.tryParse(chapter.chapterNumber)?.toString() ?? chapter.id;
      chapters.putIfAbsent(key, () => []).add(chapter);
    }
    final last = StorageService.getLastReadChapter(manga.id);
    final read = chapters.values
        .where(
          (group) => group.any((ch) => StorageService.isChapterRead(ch.id)),
        )
        .length;
    final known = StorageService.getKnownChaptersCount(
      manga.id,
      manga.availableChaptersCount,
    );
    final total = math.max(
      manga.availableChaptersCount,
      math.max(known, chapters.length),
    );
    var partial = 0.0;
    if (last != null &&
        !StorageService.isChapterRead(last.id) &&
        last.pages > 0) {
      final key = double.tryParse(last.chapterNumber)?.toString() ?? last.id;
      final alreadyRead =
          chapters[key]?.any((ch) => StorageService.isChapterRead(ch.id)) ??
          false;
      if (!alreadyRead) {
        partial = ((StorageService.getSavedPageIndex(last.id) + 1) / last.pages)
            .clamp(0, 1);
      }
    }
    return LibraryProgress(
      fraction: total > 0
          ? ((read + partial) / total).clamp(0, 1)
          : last == null
          ? 0
          : null,
      started: last != null || read > 0,
      completed:
          total > 0 &&
          read >= total &&
          !MangaDexService.hasOlderChapters(manga.id),
    );
  }
}
