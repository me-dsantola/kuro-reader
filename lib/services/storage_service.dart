import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';

class StorageService {
  static const String favBoxName = 'favorites_box';
  static const String historyBoxName = 'history_box';
  static const String downloadsBoxName = 'downloads_box';
  static const String settingsBoxName = 'settings_box';

  static final ValueNotifier<NsfwDisplayMode> nsfwModeNotifier =
      ValueNotifier(NsfwDisplayMode.blurred);

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(favBoxName);
    await Hive.openBox(historyBoxName);
    await Hive.openBox(downloadsBoxName);
    final settings = await Hive.openBox(settingsBoxName);
    final savedMode = settings.get('nsfw_mode', defaultValue: 'blurred');
    nsfwModeNotifier.value = NsfwDisplayMode.fromName(savedMode?.toString());
  }

  static Box get favBox => Hive.box(favBoxName);
  static Box get historyBox => Hive.box(historyBoxName);
  static Box get downloadsBox => Hive.box(downloadsBoxName);
  static Box get settingsBox => Hive.box(settingsBoxName);

  // --- CONFIGURAÇÃO NSFW ---
  static NsfwDisplayMode get nsfwMode => nsfwModeNotifier.value;

  static Future<void> setNsfwMode(NsfwDisplayMode mode) async {
    nsfwModeNotifier.value = mode;
    await settingsBox.put('nsfw_mode', mode.name);
  }

  static Future<void> cycleNsfwMode() async {
    final nextIndex =
        (nsfwMode.index + 1) % NsfwDisplayMode.values.length;
    await setNsfwMode(NsfwDisplayMode.values[nextIndex]);
  }

  // --- FAVORITOS (COM COFRE INCÓGNITO QUANDO NSFW = HIDDEN) ---
  static bool isFavorite(String mangaId) => favBox.containsKey(mangaId);

  static Future<void> toggleFavorite(Manga manga) async {
    if (isFavorite(manga.id)) {
      await favBox.delete(manga.id);
    } else {
      await favBox.put(manga.id, manga.toMap());
    }
  }

  static List<Manga> getFavorites() {
    final all = favBox.values
        .map((e) => Manga.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (!nsfwMode.allowNsfwFetch) {
      return all.where((m) => !m.isNsfw).toList();
    }
    return all;
  }

  // --- CACHE DE CAPÍTULOS PARA MODO OFFLINE ---
  static Future<void> cacheMangaChapters(
    String mangaId,
    List<Chapter> chapters,
  ) async {
    await historyBox.put(
      'chapters_$mangaId',
      chapters.map((c) => c.toMap()).toList(),
    );
  }

  static List<Chapter> getCachedMangaChapters(String mangaId) {
    final raw = historyBox.get('chapters_$mangaId');
    if (raw == null) return [];
    return (raw as List)
        .map((e) => Chapter.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // --- HISTÓRICO DE CAPÍTULOS E PÁGINA EXATA ---
  static bool isChapterRead(String chapterId) {
    return historyBox.get('read_$chapterId', defaultValue: false) == true;
  }

  static Future<void> markChapterAsRead(
    String mangaId,
    Chapter chapter, {
    bool read = true,
  }) async {
    await historyBox.put('read_${chapter.id}', read);
    if (read) {
      await historyBox.put('last_$mangaId', chapter.toMap());
    }
  }

  static Chapter? getLastReadChapter(String mangaId) {
    final raw = historyBox.get('last_$mangaId');
    if (raw == null) return null;
    return Chapter.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  static Future<void> saveLastPageIndex(String chapterId, int pageIndex) async {
    await historyBox.put('page_$chapterId', pageIndex);
  }

  static int getSavedPageIndex(String chapterId) {
    return historyBox.get('page_$chapterId', defaultValue: 0) as int;
  }

  // --- DOWNLOADS OFFLINE ---
  static bool isChapterDownloaded(String chapterId) {
    return downloadsBox.containsKey(chapterId);
  }

  static List<String> getDownloadedChapterPaths(String chapterId) {
    final raw = downloadsBox.get(chapterId);
    if (raw == null) return [];
    final map = Map<String, dynamic>.from(raw as Map);
    return List<String>.from(map['paths'] ?? []);
  }

  static List<Map<String, dynamic>> getAllDownloadedChapters() {
    final all = downloadsBox.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!nsfwMode.allowNsfwFetch) {
      return all.where((entry) {
        final mangaMap = Map<String, dynamic>.from(entry['manga'] ?? {});
        return mangaMap['isNsfw'] != true;
      }).toList();
    }
    return all;
  }
}
