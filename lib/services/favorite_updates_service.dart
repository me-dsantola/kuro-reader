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

  static Future<int> checkFavorite(Manga manga) async {
    if (!StorageService.isFavorite(manga.id)) return 0;
    if (manga.isNsfw && !StorageService.nsfwMode.allowNsfwFetch) return 0;

    final chaptersBySource =
        await MangaDexService.discoverAllSourcesForManga(manga);
    final chapters = chaptersBySource[MangaSourceType.mangadex] ??
        chaptersBySource[manga.source] ??
        const <Chapter>[];
    if (chapters.isEmpty) return 0;

    final key = '$_prefix${manga.id}';
    final previous = StorageService.settingsBox.get(key);
    final known = <String>{};
    final pending = <Chapter>[];
    if (previous is Map) {
      final oldIds = previous['known'];
      if (oldIds is List) known.addAll(oldIds.whereType<String>());
      final oldPending = previous['pending'];
      if (oldPending is List) {
        pending.addAll(oldPending.whereType<Map>().map(
          (entry) => Chapter.fromMap(Map<String, dynamic>.from(entry)),
        ));
      }
    }

    // First check establishes a baseline; old chapters are not "new".
    final fresh = previous is Map
        ? chapters.where((chapter) => !known.contains(chapter.id)).toList()
        : <Chapter>[];
    final pendingIds = pending.map((chapter) => chapter.id).toSet();
    for (final chapter in fresh) {
      if (pendingIds.add(chapter.id)) pending.add(chapter);
    }
    // Retain the most recent notifications, not the oldest 100.
    pending.sort((a, b) => b.numericChapter.compareTo(a.numericChapter));

    // Bounded local state. Do not rely on chapter counts or estimated totals.
    final updatedKnown = <String>{
      ...known,
      ...chapters.map((chapter) => chapter.id),
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
}
