import '../models/manga_models.dart';
import 'mangadex_service.dart';
import 'storage_service.dart';

/// Local, opt-in chapter update tracking. Does not schedule background work
/// or request Android notification permissions.
class FavoriteUpdatesService {
  static const _prefix = 'favorite_updates_v1_';

  static List<Chapter> allPending(List<Manga> favorites) {
    final result = <Chapter>[];
    for (final manga in favorites) {
      result.addAll(pendingFor(manga));
    }
    return result;
  }

  static List<Chapter> pendingFor(Manga manga) {
    if (manga.isNsfw && !StorageService.nsfwMode.allowNsfwFetch) {
      return const [];
    }
    final raw = StorageService.settingsBox.get('$_prefix${manga.id}');
    if (raw is! Map) return const [];
    final pending = raw['pending'];
    if (pending is! List) return const [];
    return pending
        .whereType<Map>()
        .map((entry) => Chapter.fromMap(Map<String, dynamic>.from(entry)))
        .toList();
  }

  static Future<int> checkAllFavorites(List<Manga> favorites) async {
    int totalFound = 0;
    for (final manga in favorites) {
      try {
        totalFound += await checkFavorite(manga);
      } catch (_) {}
    }
    return totalFound;
  }

  static Future<int> checkFavorite(Manga manga) async {
    if (!StorageService.isFavorite(manga.id)) return 0;
    if (manga.isNsfw && !StorageService.nsfwMode.allowNsfwFetch) return 0;

    final chaptersBySource = await MangaDexService.discoverAllSourcesForManga(
      manga,
    );
    List<Chapter> chapters =
        chaptersBySource[MangaSourceType.mangadex] ??
        chaptersBySource[manga.source] ??
        const <Chapter>[];
    if (chapters.isEmpty) {
      for (final list in chaptersBySource.values) {
        if (list.length > chapters.length) {
          chapters = list;
        }
      }
    }
    if (chapters.isEmpty) return 0;

    final sortedDesc = List<Chapter>.from(chapters)
      ..sort((a, b) => b.numericChapter.compareTo(a.numericChapter));

    final key = '$_prefix${manga.id}';
    final previous = StorageService.settingsBox.get(key);
    final known = <String>{};
    final pending = <Chapter>[];
    if (previous is Map) {
      final oldIds = previous['known'];
      if (oldIds is List) known.addAll(oldIds.whereType<String>());
      final oldPending = previous['pending'];
      if (oldPending is List) {
        pending.addAll(
          oldPending.whereType<Map>().map(
            (entry) => Chapter.fromMap(Map<String, dynamic>.from(entry)),
          ),
        );
      }
    }

    final List<Chapter> fresh;
    if (previous is Map) {
      fresh = sortedDesc
          .where((chapter) => !known.contains(chapter.id))
          .toList();
    } else {
      // Na primeira verificação, destaca capítulos posteriores ao último lido
      // ou o capítulo mais recente disponível da obra favorita.
      final lastRead = StorageService.getLastReadChapter(manga.id);
      if (lastRead != null) {
        fresh = sortedDesc
            .where(
              (ch) =>
                  ch.numericChapter > lastRead.numericChapter &&
                  !StorageService.isChapterRead(ch.id),
            )
            .take(10)
            .toList();
      } else {
        fresh = sortedDesc
            .where((ch) => !StorageService.isChapterRead(ch.id))
            .take(1)
            .toList();
      }
    }

    final pendingIds = pending.map((chapter) => chapter.id).toSet();
    for (final chapter in fresh) {
      if (pendingIds.add(chapter.id)) pending.add(chapter);
    }
    // Retain the most recent notifications, not the oldest 100.
    pending.sort((a, b) => b.numericChapter.compareTo(a.numericChapter));

    // Bounded local state. Do not rely on chapter counts or estimated totals.
    final updatedKnown = <String>{
      ...known,
      ...sortedDesc.map((chapter) => chapter.id),
    }.toList();
    await StorageService.settingsBox.put(key, {
      'known': updatedKnown.length > 3000
          ? updatedKnown.sublist(updatedKnown.length - 3000)
          : updatedKnown,
      'pending': pending.take(100).map((chapter) => chapter.toMap()).toList(),
      'checkedAt': DateTime.now().toIso8601String(),
    });
    return fresh.length;
  }

  static Future<void> markSeen(Manga manga) async {
    final key = '$_prefix${manga.id}';
    final previous = StorageService.settingsBox.get(key);
    if (previous is! Map) return;
    await StorageService.settingsBox.put(key, {
      ...Map<String, dynamic>.from(previous),
      'pending': <Map<String, dynamic>>[],
    });
  }

  static Future<void> markAllSeen(List<Manga> favorites) async {
    for (final manga in favorites) {
      await markSeen(manga);
    }
  }
}
