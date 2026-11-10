import 'backup_codec.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';

class StorageService {
  static const String favBoxName = 'favorites_box';
  static const String historyBoxName = 'history_box';
  static const String downloadsBoxName = 'downloads_box';
  static const String settingsBoxName = 'settings_box';

  /// Por exigência estrita, o modo NSFW SEMPRE inicia como `hidden` (Desligado)
  static final ValueNotifier<NsfwDisplayMode> nsfwModeNotifier =
      ValueNotifier(NsfwDisplayMode.hidden);

  static final ValueNotifier<UserProfile> profileNotifier =
      ValueNotifier(const UserProfile());

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(favBoxName);
    await Hive.openBox(historyBoxName);
    await Hive.openBox(downloadsBoxName);
    final settings = await Hive.openBox(settingsBoxName);

    // 1. Conteúdo Adulto: Oculto de cara na primeira abertura e sempre desligado por padrão.
    // Só carrega outro modo se o usuário tiver ativado explicitamente "persist_nsfw" nas configurações,
    // ou se o usuário quiser manter sempre desligado ao abrir o app.
    final bool keepNsfwLockedOnStartup =
        settings.get('lock_nsfw_on_startup', defaultValue: true) == true;

    if (keepNsfwLockedOnStartup) {
      await settings.put('nsfw_mode', NsfwDisplayMode.hidden.name);
      nsfwModeNotifier.value = NsfwDisplayMode.hidden;
    } else {
      final savedMode = settings.get('nsfw_mode', defaultValue: 'hidden');
      nsfwModeNotifier.value = NsfwDisplayMode.fromName(savedMode?.toString());
    }

    // 2. Carrega Perfil Personalizado
    final rawProfile = settings.get('user_profile');
    if (rawProfile != null && rawProfile is Map) {
      profileNotifier.value =
          UserProfile.fromMap(Map<String, dynamic>.from(rawProfile));
    } else {
      const defaultProfile = UserProfile(isConfigured: true);
      await settings.put('user_profile', defaultProfile.toMap());
      profileNotifier.value = defaultProfile;
    }
  }

  static Box get favBox => Hive.box(favBoxName);
  static Box get historyBox => Hive.box(historyBoxName);
  static Box get downloadsBox => Hive.box(downloadsBoxName);
  static Box get settingsBox => Hive.box(settingsBoxName);

  // --- CONFIGURAÇÕES GERAIS E NSFW ---
  static NsfwDisplayMode get nsfwMode => nsfwModeNotifier.value;

  static Future<void> setNsfwMode(NsfwDisplayMode mode) async {
    nsfwModeNotifier.value = mode;
    await settingsBox.put('nsfw_mode', mode.name);
  }

  static bool get lockNsfwOnStartup =>
      settingsBox.get('lock_nsfw_on_startup', defaultValue: true) == true;

  static Future<void> setLockNsfwOnStartup(bool value) async {
    await settingsBox.put('lock_nsfw_on_startup', value);
  }

  static bool get hideZeroChapterTitles =>
      settingsBox.get('hide_zero_chapters', defaultValue: false) == true;

  static Future<void> setHideZeroChapterTitles(bool value) async {
    await settingsBox.put('hide_zero_chapters', value);
  }

  static bool get dataSaverEnabled =>
      settingsBox.get('data_saver_mode', defaultValue: false) == true;

  static Future<void> setDataSaverEnabled(bool value) async {
    await settingsBox.put('data_saver_mode', value);
  }

  // --- PERFIL PERSONALIZADO ---
  static UserProfile get userProfile => profileNotifier.value;

  static Future<void> updateUserProfile(UserProfile profile) async {
    profileNotifier.value = profile;
    await settingsBox.put('user_profile', profile.toMap());
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
        .whereType<Map>()
        .map((e) => Manga.fromMap(Map<String, dynamic>.from(e)))
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
    if (chapters.isEmpty) return;
    await historyBox.put(
      'chapters_$mangaId',
      chapters.map((c) => c.toMap()).toList(),
    );
    await historyBox.put('chapters_count_$mangaId', chapters.length);
  }

  static int getKnownChaptersCount(String mangaId, int fallback) {
    final cached = historyBox.get('chapters_count_$mangaId');
    if (cached is int && cached > 0) return cached;
    return fallback;
  }

  static List<Chapter> getCachedMangaChapters(String mangaId) {
    final raw = historyBox.get('chapters_$mangaId');
    if (raw == null || raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Chapter.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  // --- HISTÓRICO DE LEITURA, "CONTINUAR LENDO" E MÉTRICAS DO PERFIL ---
  static bool isChapterRead(String chapterId) {
    return historyBox.get('read_$chapterId', defaultValue: false) == true;
  }

  /// Opening a chapter resumes it, but never marks it completed.
  /// Existing read flags remain untouched for backwards compatibility.
  static Future<void> recordChapterOpened(Manga manga, Chapter chapter) async {
    await historyBox.put('last_${manga.id}', chapter.toMap());
    await historyBox.put('manga_meta_${manga.id}', manga.toMap());

    final List rawRecent =
        List.from(historyBox.get('recent_reading_list', defaultValue: []));
    rawRecent.removeWhere((item) =>
        item is Map && item['manga'] is Map && item['manga']['id'] == manga.id);
    rawRecent.insert(0, {
      'manga': manga.toMap(),
      'chapter': chapter.toMap(),
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (rawRecent.length > 25) rawRecent.removeRange(25, rawRecent.length);
    await historyBox.put('recent_reading_list', rawRecent);
  }

  static Future<void> markChapterAsRead(
    Manga manga,
    Chapter chapter, {
    bool read = true,
  }) async {
    final wasRead = isChapterRead(chapter.id);
    await historyBox.put('read_${chapter.id}', read);

    if (read) {
      await recordChapterOpened(manga, chapter);

      // Only completed chapters count in reading statistics.
      if (!wasRead) {
        final List rawEvents =
            List.from(historyBox.get('reading_events_log', defaultValue: []));
        rawEvents.add({
          'chapterId': chapter.id,
          'mangaId': manga.id,
          'mangaTitle': manga.title,
          'pages': chapter.pages > 0 ? chapter.pages : 22,
          'chapterMap': chapter.toMap(),
          'mangaMap': manga.toMap(),
          'readAt': DateTime.now().toIso8601String(),
        });
        await historyBox.put('reading_events_log', rawEvents);
      }
    }
  }

  static List<Map<String, dynamic>> getContinueReadingList() {
    final raw = historyBox.get('recent_reading_list', defaultValue: []);
    if (raw is! List) return [];
    final allowNsfw = nsfwMode.allowNsfwFetch;
    final result = <Map<String, dynamic>>[];

    for (final item in raw) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final manga = Manga.fromMap(Map<String, dynamic>.from(map['manga'] ?? {}));
        final chapter =
            Chapter.fromMap(Map<String, dynamic>.from(map['chapter'] ?? {}));
        if (!allowNsfw && manga.isNsfw) continue;
        result.add({
          'manga': manga,
          'chapter': chapter,
          'timestamp': DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
              DateTime.now(),
        });
      }
    }
    return result;
  }

  static Chapter? getLastReadChapter(String mangaId) {
    final raw = historyBox.get('last_$mangaId');
    if (raw == null || raw is! Map) return null;
    return Chapter.fromMap(Map<String, dynamic>.from(raw));
  }

  static Future<void> saveLastPageIndex(String chapterId, int pageIndex) async {
    if (getSavedPageIndex(chapterId) == pageIndex) return;
    await historyBox.put('page_$chapterId', pageIndex);
  }

  static int getSavedPageIndex(String chapterId) {
    return (historyBox.get('page_$chapterId', defaultValue: 0) as int?) ?? 0;
  }

  /// Pixel offset is kept separately so old page-index saves still work.
  static double getSavedWebtoonOffset(String chapterId) {
    final stored = historyBox.get('webtoon_offset_$chapterId');
    if (stored is! num || !stored.isFinite || stored < 0) return 0;
    return stored.toDouble();
  }

  static Future<void> saveWebtoonOffset(String chapterId, double offset) async {
    if (!offset.isFinite || offset < 0) return;
    await historyBox.put('webtoon_offset_$chapterId', offset);
  }

  /// Calcula todas as métricas de leitura em tempo real (Dia, Semana, Mais Lido, Menos Lido, Maior e Menor Capítulo)
  static ReadingMetricsSummary computeReadingMetrics() {
    final rawEvents = historyBox.get('reading_events_log', defaultValue: []);
    if (rawEvents is! List || rawEvents.isEmpty) {
      return const ReadingMetricsSummary(
        chaptersReadToday: 0,
        chaptersReadThisWeek: 0,
        totalChaptersRead: 0,
        totalPagesRead: 0,
      );
    }

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = now.subtract(const Duration(days: 7));
    final allowNsfw = nsfwMode.allowNsfwFetch;

    int todayCount = 0;
    int weekCount = 0;
    int totalCount = 0;
    int totalPages = 0;

    final Map<String, int> mangaCounts = {};
    final Map<String, Manga> mangaObjects = {};
    Chapter? longestCh;
    Chapter? shortestCh;

    for (final raw in rawEvents) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final mangaMap = Map<String, dynamic>.from(map['mangaMap'] ?? {});
      final manga = Manga.fromMap(mangaMap);
      if (!allowNsfw && manga.isNsfw) continue;

      final chapterMap = Map<String, dynamic>.from(map['chapterMap'] ?? {});
      final chapter = Chapter.fromMap(chapterMap);
      final readAt =
          DateTime.tryParse(map['readAt']?.toString() ?? '') ?? DateTime.now();
      final int pages = (map['pages'] as int?) ?? chapter.pages;

      totalCount++;
      totalPages += pages;

      if (readAt.isAfter(startOfToday)) {
        todayCount++;
      }
      if (readAt.isAfter(startOfWeek)) {
        weekCount++;
      }

      mangaCounts[manga.id] = (mangaCounts[manga.id] ?? 0) + 1;
      mangaObjects[manga.id] = manga;

      if (longestCh == null || pages > longestCh.pages) {
        longestCh = chapter;
      }
      if (shortestCh == null || (pages > 0 && pages < shortestCh.pages)) {
        shortestCh = chapter;
      }
    }

    final sortedEntries = mangaCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Manga? mostRead;
    int mostCount = 0;
    Manga? leastRead;
    int leastCount = 0;
    final List<MapEntry<Manga, int>> ranked = [];

    for (final e in sortedEntries) {
      final m = mangaObjects[e.key];
      if (m != null) {
        ranked.add(MapEntry(m, e.value));
      }
    }

    if (ranked.isNotEmpty) {
      mostRead = ranked.first.key;
      mostCount = ranked.first.value;
      leastRead = ranked.last.key;
      leastCount = ranked.last.value;
    }

    return ReadingMetricsSummary(
      chaptersReadToday: todayCount,
      chaptersReadThisWeek: weekCount,
      totalChaptersRead: totalCount,
      totalPagesRead: totalPages,
      mostReadManga: mostRead,
      mostReadCount: mostCount,
      leastReadManga: leastRead,
      leastReadCount: leastCount,
      longestChapterRead: longestCh,
      shortestChapterRead: shortestCh,
      rankedMangas: ranked,
    );
  }

  // --- BACKUP LOCAL. Base64 is a transport format, not encryption. ---
  static String exportFullBackupJson() {
    final payload = {
      'format': 'yomi-local-backup',
      'version': BackupCodec.currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': userProfile.toMap(),
      'favorites': favBox.toMap(),
      'history': historyBox.toMap(),
      'settings': {
        'lock_nsfw_on_startup': lockNsfwOnStartup,
        'hide_zero_chapters': hideZeroChapterTitles,
        'data_saver_mode': dataSaverEnabled,
      },
    };
    // Offline image files are not embedded. Never report an unbundled
    // downloaded chapter as restored offline content.
    return BackupCodec.encode(payload);
  }

  static Future<bool> importFullBackupJson(String rawInput) async {
    try {
      // Parse and validate every section before mutating any Hive box.
      // Older backups without a version number remain supported.
      final data = BackupCodec.decode(rawInput);
      final favs = data['favorites'] is Map
          ? Map<String, dynamic>.from(data['favorites'] as Map)
          : <String, dynamic>{};
      final hist = data['history'] is Map
          ? Map<String, dynamic>.from(data['history'] as Map)
          : <String, dynamic>{};
      final settings = data['settings'] is Map
          ? Map<String, dynamic>.from(data['settings'] as Map)
          : <String, dynamic>{};
      final profile = data['profile'] is Map
          ? UserProfile.fromMap(
              Map<String, dynamic>.from(data['profile'] as Map),
            )
          : null;

      // Verify serializable map values before writing; otherwise malformed
      // imports can leave a partially restored user profile.
      for (final entry in hist.entries) {
        if (entry.key.isEmpty) throw const FormatException('Histórico inválido');
      }

      if (favs.isNotEmpty) await favBox.putAll(favs);
      if (hist.isNotEmpty) await historyBox.putAll(hist);
      for (final key in [
        'lock_nsfw_on_startup',
        'hide_zero_chapters',
        'data_saver_mode',
      ]) {
        final value = settings[key];
        if (value is bool) await settingsBox.put(key, value);
      }
      if (profile != null) await updateUserProfile(profile);
      return true;
    } catch (e) {
      debugPrint('Erro ao restaurar backup: $e');
      return false;
    }
  }

  // --- DOWNLOADS OFFLINE ---
  static bool isChapterDownloaded(String chapterId) {
    return downloadsBox.containsKey(chapterId);
  }

  static List<String> getDownloadedChapterPaths(String chapterId) {
    final raw = downloadsBox.get(chapterId);
    if (raw == null || raw is! Map) return [];
    final map = Map<String, dynamic>.from(raw);
    return List<String>.from(map['paths'] ?? []);
  }

  static List<Map<String, dynamic>> getAllDownloadedChapters() {
    final all = downloadsBox.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
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
