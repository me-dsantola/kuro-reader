import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'backup_codec.dart';
import 'cloud_sync_service.dart';
import 'device_state_service.dart';
import '../models/manga_models.dart';
import '../models/reader_anchor.dart';

class StorageService {
  static const String favBoxName = 'favorites_box';
  static const String historyBoxName = 'history_box';
  static const String downloadsBoxName = 'downloads_box';
  static const String settingsBoxName = 'settings_box';
  static const String restoreJournalKey = 'backup_restore_journal_v1';
  static Future<void> _restoreTail = Future<void>.value();
  static Future<void> _readingTail = Future<void>.value();

  static Future<void> _serializeReading(Future<void> Function() write) {
    final result = _readingTail.then((_) => write());
    // A disk failure is still returned to its caller, but must not prevent a
    // later independent write from being attempted.
    _readingTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static Manga? _storedManga(Object? raw) {
    if (raw is! Map) return null;
    if (raw['tags'] != null && raw['tags'] is! List) return null;
    if (raw['customHeaders'] != null && raw['customHeaders'] is! Map) {
      return null;
    }
    try {
      final manga = Manga.fromMap(Map<String, dynamic>.from(raw));
      return manga.id.isEmpty ? null : manga;
    } catch (_) {
      // Preserve damaged legacy entries in Hive for export/recovery. A single
      // entry must not make the rest of a library inaccessible.
      return null;
    }
  }

  static Chapter? _storedChapter(Object? raw) {
    if (raw is! Map) return null;
    if (raw['pages'] != null && raw['pages'] is! num) return null;
    if (raw['directPageUrls'] != null && raw['directPageUrls'] is! List) {
      return null;
    }
    try {
      final chapter = Chapter.fromMap(Map<String, dynamic>.from(raw));
      return chapter.id.isEmpty ? null : chapter;
    } catch (_) {
      return null;
    }
  }

  static String? _eventChapterId(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['chapterId'];
    if (id is String && id.isNotEmpty) return id;
    final chapter = raw['chapterMap'];
    return chapter is Map && chapter['id'] is String
        ? chapter['id'] as String
        : null;
  }

  /// Por exigência estrita, o modo NSFW SEMPRE inicia como `hidden` (Desligado)
  static final ValueNotifier<NsfwDisplayMode> nsfwModeNotifier = ValueNotifier(
    NsfwDisplayMode.hidden,
  );

  static final ValueNotifier<UserProfile> profileNotifier = ValueNotifier(
    const UserProfile(),
  );

  static final ValueNotifier<bool> privacyProtectionNotifier =
      ValueNotifier<bool>(true);

  static const String readingListsKey = 'user_reading_lists';
  static const String lastAutoBackupAtKey = 'last_auto_backup_at';
  static const MethodChannel _autoBackupChannel = MethodChannel(
    'yomi/auto_backup',
  );
  static Timer? _autoBackupDebounce;
  static final List<StreamSubscription<BoxEvent>> _autoBackupSubscriptions = [];
  static bool _restoringAutoBackup = false;

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(favBoxName);
    await Hive.openBox(historyBoxName);
    await Hive.openBox(downloadsBoxName);
    final settings = await Hive.openBox(settingsBoxName);
    await recoverInterruptedRestore();

    // 0. Restauração Automática pós-reinstalação:
    // Se esta instalação estiver limpa (sem favoritos, histórico ou perfil configurado),
    // consulta o backup automático persistido no aparelho/OS e restaura sem depender de código manual.
    final isFreshInstall =
        favBox.isEmpty &&
        historyBox.isEmpty &&
        settings.get('user_profile') == null;
    if (isFreshInstall) {
      await tryRestoreFromDeviceAutoBackup();
    }

    // 1. Conteúdo Adulto: Oculto de cara na primeira abertura e sempre desligado por padrão.
    final bool keepNsfwLockedOnStartup =
        settings.get('lock_nsfw_on_startup', defaultValue: true) == true;

    if (keepNsfwLockedOnStartup) {
      await settings.put('nsfw_mode', NsfwDisplayMode.hidden.name);
      nsfwModeNotifier.value = NsfwDisplayMode.hidden;
    } else {
      final savedMode = settings.get('nsfw_mode', defaultValue: 'hidden');
      nsfwModeNotifier.value = NsfwDisplayMode.fromName(savedMode?.toString());
    }

    // 2. Proteção de Privacidade (ativada por padrão, configurável pelo usuário)
    privacyProtectionNotifier.value =
        settings.get('privacy_protection_enabled', defaultValue: true) != false;

    // 3. Carrega Perfil Personalizado (no primeiro uso, isConfigured = false para exibir o Onboarding)
    final rawProfile = settings.get('user_profile');
    if (rawProfile != null && rawProfile is Map) {
      profileNotifier.value = UserProfile.fromMap(
        Map<String, dynamic>.from(rawProfile),
      );
    } else {
      const firstRunProfile = UserProfile(isConfigured: false);
      await settings.put('user_profile', firstRunProfile.toMap());
      profileNotifier.value = firstRunProfile;
    }

    // 4. Ativa observadores de backup automático contínuo no dispositivo
    _attachAutoBackupWatchers();
    if (!isFreshInstall) {
      unawaited(syncAutoBackupNow());
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

  static bool get privacyProtectionEnabled => Hive.isBoxOpen(settingsBoxName)
      ? settingsBox.get('privacy_protection_enabled', defaultValue: true) !=
            false
      : privacyProtectionNotifier.value;

  static Future<void> setPrivacyProtectionEnabled(bool value) async {
    privacyProtectionNotifier.value = value;
    if (Hive.isBoxOpen(settingsBoxName)) {
      await settingsBox.put('privacy_protection_enabled', value);
    }
  }

  // --- PERFIL PERSONALIZADO ---
  static UserProfile get userProfile => profileNotifier.value;

  static Future<void> updateUserProfile(UserProfile profile) async {
    profileNotifier.value = profile;
    await settingsBox.put('user_profile', profile.toMap());
  }

  // --- LISTAS DE LEITURA PERSONALIZADAS PELO USUÁRIO ---
  static List<UserReadingList> _rawReadingLists() {
    if (!Hive.isBoxOpen(settingsBoxName)) return const [];
    final raw = settingsBox.get(readingListsKey);
    if (raw is! List) return const [];
    final lists = <UserReadingList>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          final parsed = UserReadingList.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (parsed.id.isNotEmpty) {
            lists.add(parsed);
          }
        } catch (_) {}
      }
    }
    return lists;
  }

  static List<UserReadingList> getReadingLists() {
    final allowNsfw = nsfwMode.allowNsfwFetch;
    return _rawReadingLists()
        .map(
          (list) => list.copyWith(
            mangas: list.mangas.where((m) => allowNsfw || !m.isNsfw).toList(),
          ),
        )
        .toList();
  }

  static Future<UserReadingList> createReadingList(
    String name, {
    String description = '',
    List<Manga> initialMangas = const [],
  }) async {
    final cleanName = name.trim().isEmpty ? 'Minha Lista' : name.trim();
    final newList = UserReadingList(
      id: 'list_${DateTime.now().microsecondsSinceEpoch}',
      name: cleanName,
      description: description.trim(),
      mangas: List<Manga>.from(initialMangas),
    );
    final current = List<UserReadingList>.from(_rawReadingLists())
      ..insert(0, newList);
    await settingsBox.put(
      readingListsKey,
      current.map((l) => l.toMap()).toList(),
    );
    return newList;
  }

  static Future<void> saveReadingList(UserReadingList updated) async {
    final current = List<UserReadingList>.from(_rawReadingLists());
    final idx = current.indexWhere((l) => l.id == updated.id);
    if (idx >= 0) {
      current[idx] = updated;
    } else {
      current.insert(0, updated);
    }
    await settingsBox.put(
      readingListsKey,
      current.map((l) => l.toMap()).toList(),
    );
  }

  static Future<void> deleteReadingList(String listId) async {
    final current = List<UserReadingList>.from(_rawReadingLists())
      ..removeWhere((l) => l.id == listId);
    await settingsBox.put(
      readingListsKey,
      current.map((l) => l.toMap()).toList(),
    );
  }

  static bool isMangaInReadingList(String listId, String mangaId) {
    for (final list in _rawReadingLists()) {
      if (list.id == listId) {
        return list.mangas.any((m) => m.id == mangaId);
      }
    }
    return false;
  }

  static Future<bool> toggleMangaInReadingList(
    String listId,
    Manga manga,
  ) async {
    final current = List<UserReadingList>.from(_rawReadingLists());
    final idx = current.indexWhere((l) => l.id == listId);
    if (idx < 0) return false;
    final list = current[idx];
    final mangas = List<Manga>.from(list.mangas);
    final existingIdx = mangas.indexWhere((m) => m.id == manga.id);
    final bool added;
    if (existingIdx >= 0) {
      mangas.removeAt(existingIdx);
      added = false;
    } else {
      mangas.insert(0, manga);
      added = true;
    }
    current[idx] = list.copyWith(mangas: mangas);
    await settingsBox.put(
      readingListsKey,
      current.map((l) => l.toMap()).toList(),
    );
    return added;
  }

  static const String readLaterListId = 'read_later_default_list';
  static const String readLaterListName = 'Ler mais tarde';

  static UserReadingList getOrCreateReadLaterList() {
    final lists = _rawReadingLists();
    final existing = lists.firstWhere(
      (l) => l.id == readLaterListId,
      orElse: () => UserReadingList(
        id: readLaterListId,
        name: readLaterListName,
        description: 'Obras salvas para ler depois',
      ),
    );
    return existing;
  }

  static bool isMangaInReadLater(String mangaId) {
    return isMangaInReadingList(readLaterListId, mangaId);
  }

  static Future<bool> toggleReadLater(Manga manga) async {
    final current = List<UserReadingList>.from(_rawReadingLists());
    var idx = current.indexWhere((l) => l.id == readLaterListId);
    if (idx < 0) {
      final newList = UserReadingList(
        id: readLaterListId,
        name: readLaterListName,
        description: 'Obras salvas para ler depois',
        mangas: [manga],
      );
      current.insert(0, newList);
      await settingsBox.put(
        readingListsKey,
        current.map((l) => l.toMap()).toList(),
      );
      return true;
    }

    final list = current[idx];
    final mangas = List<Manga>.from(list.mangas);
    final existingIdx = mangas.indexWhere((m) => m.id == manga.id);
    final bool added;
    if (existingIdx >= 0) {
      mangas.removeAt(existingIdx);
      added = false;
    } else {
      mangas.insert(0, manga);
      added = true;
    }
    current[idx] = list.copyWith(mangas: mangas);
    await settingsBox.put(
      readingListsKey,
      current.map((l) => l.toMap()).toList(),
    );
    return added;
  }

  // --- FAVORITOS (COM COFRE INCÓGNITO QUANDO NSFW = HIDDEN) ---
  static bool isFavorite(String mangaId) =>
      Hive.isBoxOpen(favBoxName) && favBox.containsKey(mangaId);

  static Future<void> toggleFavorite(Manga manga) async {
    if (isFavorite(manga.id)) {
      await favBox.delete(manga.id);
    } else {
      await favBox.put(manga.id, manga.toMap());
    }
  }

  /// Garante que o título esteja salvo na Biblioteca (favoritos) e que seus capítulos
  /// estejam em cache para navegação offline na Biblioteca.
  static Future<void> ensureInLibrary(
    Manga manga, {
    List<Chapter>? chapters,
  }) async {
    if (Hive.isBoxOpen(favBoxName) && !favBox.containsKey(manga.id)) {
      await favBox.put(manga.id, manga.toMap());
    }
    if (Hive.isBoxOpen(historyBoxName) &&
        chapters != null &&
        chapters.isNotEmpty) {
      final existing = getCachedMangaChapters(manga.id);
      final seen = <String>{};
      final merged = <Chapter>[
        for (final ch in [...chapters, ...existing])
          if (seen.add(ch.id)) ch,
      ];
      await cacheMangaChapters(
        manga.id,
        merged,
        titleKey: manga.normalizedTitleKey,
      );
    }
  }

  static List<Manga> getFavorites() {
    final all = <Manga>[];
    final seen = <String>{};
    for (final raw in favBox.values) {
      final manga = _storedManga(raw);
      if (manga != null &&
          (nsfwMode.allowNsfwFetch || !manga.isNsfw) &&
          seen.add(manga.id)) {
        all.add(manga);
      }
    }
    return all;
  }

  // --- CACHE DE CAPÍTULOS PARA MODO OFFLINE & DETECÇÃO DE 0 CAPÍTULOS ---
  static Future<void> cacheMangaChapters(
    String mangaId,
    List<Chapter> chapters, {
    String? titleKey,
  }) async {
    if (chapters.isEmpty) {
      final existing = getCachedMangaChapters(mangaId);
      if (existing.isEmpty) {
        await recordKnownChaptersCount(mangaId, 0, titleKey: titleKey);
      }
      return;
    }
    await historyBox.put(
      'chapters_$mangaId',
      chapters.map((c) => c.toMap()).toList(),
    );
    await recordKnownChaptersCount(
      mangaId,
      chapters.length,
      titleKey: titleKey,
    );
  }

  static Future<void> recordKnownChaptersCount(
    String mangaId,
    int count, {
    String? titleKey,
  }) async {
    if (!Hive.isBoxOpen(historyBoxName)) return;
    await historyBox.put('chapters_count_$mangaId', count);
    final cleanTitle = titleKey?.trim() ?? '';
    if (cleanTitle.length >= 3) {
      await historyBox.put('chapters_count_title_$cleanTitle', count);
    }
  }

  static final Set<String> _inFlightAvailabilityChecks = <String>{};
  static final Set<String> _completedAvailabilityChecks = <String>{};
  static int _activeAvailabilityJobs = 0;
  static const int _maxConcurrentAvailabilityJobs = 2;

  /// Diferencia explicitamente:
  /// - 0 capítulos confirmados (retorna true)
  /// - contagem desconhecida (-1) ou carregando (retorna false)
  static bool isConfirmedZeroChapters(Manga manga) {
    final known = getKnownChaptersCount(
      manga.id,
      manga.availableChaptersCount,
      titleKey: manga.normalizedTitleKey,
    );
    return known == 0;
  }

  /// Agenda verificação única e limitada com cache para obras com contagem desconhecida (-1).
  static void requestLimitedAvailabilityCheck(
    Manga manga,
    Future<List<Chapter>> Function(Manga) fetcher,
  ) {
    if (DeviceStateService.instance.isOffline) return;
    final known = getKnownChaptersCount(
      manga.id,
      manga.availableChaptersCount,
      titleKey: manga.normalizedTitleKey,
    );
    if (known >= 0) return; // Já conhecido (0 ou > 0)
    if (_completedAvailabilityChecks.contains(manga.id) ||
        _inFlightAvailabilityChecks.contains(manga.id) ||
        _activeAvailabilityJobs >= _maxConcurrentAvailabilityJobs) {
      return;
    }

    _inFlightAvailabilityChecks.add(manga.id);
    _activeAvailabilityJobs++;
    fetcher(manga).then((chapters) async {
      _completedAvailabilityChecks.add(manga.id);
      await recordKnownChaptersCount(
        manga.id,
        chapters.length,
        titleKey: manga.normalizedTitleKey,
      );
      if (chapters.isNotEmpty) {
        await cacheMangaChapters(
          manga.id,
          chapters,
          titleKey: manga.normalizedTitleKey,
        );
      }
    }).catchError((Object _) {
      // Em falha de rede, mantém como desconhecido (-1), nunca marcando como 0.
    }).whenComplete(() {
      _inFlightAvailabilityChecks.remove(manga.id);
      _activeAvailabilityJobs--;
    });
  }

  static int getKnownChaptersCount(
    String mangaId,
    int fallback, {
    String? titleKey,
  }) {
    if (!Hive.isBoxOpen(historyBoxName)) return fallback;
    final cached = historyBox.get('chapters_count_$mangaId');
    if (cached is int && cached >= 0) return cached;
    final cleanTitle = titleKey?.trim() ?? '';
    if (cleanTitle.length >= 3) {
      final byTitle = historyBox.get('chapters_count_title_$cleanTitle');
      if (byTitle is int && byTitle >= 0) return byTitle;
    }
    return fallback;
  }

  static List<Chapter> getCachedMangaChapters(String mangaId) {
    final raw = historyBox.get('chapters_$mangaId');
    if (raw is! List) return [];
    return [
      for (final value in raw)
        if (_storedChapter(value) case final Chapter chapter) chapter,
    ];
  }

  // --- HISTÓRICO DE LEITURA, "CONTINUAR LENDO" E MÉTRICAS DO PERFIL ---
  static bool isChapterRead(String chapterId) {
    return historyBox.get('read_$chapterId', defaultValue: false) == true;
  }

  /// Opening a chapter resumes it, but never marks it completed.
  /// Existing read flags remain untouched for backwards compatibility.
  static Future<void> recordChapterOpened(Manga manga, Chapter chapter) =>
      _serializeReading(() => _recordChapterOpened(manga, chapter));

  static Future<void> _recordChapterOpened(Manga manga, Chapter chapter) async {
    await historyBox.put('last_${manga.id}', chapter.toMap());
    await historyBox.put('manga_meta_${manga.id}', manga.toMap());

    final stored = historyBox.get('recent_reading_list');
    final List rawRecent = stored is List ? List.from(stored) : [];
    rawRecent.removeWhere(
      (item) =>
          item is Map &&
          item['manga'] is Map &&
          item['manga']['id'] == manga.id,
    );
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
  }) => _serializeReading(() => _markChapterAsRead(manga, chapter, read: read));

  static Future<void> _markChapterAsRead(
    Manga manga,
    Chapter chapter, {
    required bool read,
  }) async {
    final wasRead = isChapterRead(chapter.id);
    final storedEvents = historyBox.get('reading_events_log');
    final List rawEvents = storedEvents is List ? List.from(storedEvents) : [];
    if (read) {
      await _recordChapterOpened(manga, chapter);
      if (!wasRead &&
          !rawEvents.any((event) => _eventChapterId(event) == chapter.id)) {
        rawEvents.add({
          'chapterId': chapter.id,
          'mangaId': manga.id,
          'mangaTitle': manga.title,
          'pages': chapter.pages > 0 ? chapter.pages : 0,
          'chapterMap': chapter.toMap(),
          'mangaMap': manga.toMap(),
          'readAt': DateTime.now().toIso8601String(),
        });
        await historyBox.put('reading_events_log', rawEvents);
      }
    } else {
      rawEvents.removeWhere((event) => _eventChapterId(event) == chapter.id);
      await historyBox.put('reading_events_log', rawEvents);
    }
    // Commit the flag last. Retrying after a failed write cannot duplicate
    // the event already saved above.
    await historyBox.put('read_${chapter.id}', read);
  }

  static List<Map<String, dynamic>> getContinueReadingList() {
    final raw = historyBox.get('recent_reading_list');
    if (raw is! List) return [];
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final manga = _storedManga(item['manga']);
      final chapter = _storedChapter(item['chapter']);
      if (manga == null ||
          chapter == null ||
          (!nsfwMode.allowNsfwFetch && manga.isNsfw)) {
        continue;
      }
      result.add({
        'manga': manga,
        'chapter': chapter,
        'timestamp':
            DateTime.tryParse(item['timestamp']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      });
    }
    return result;
  }

  static Chapter? getLastReadChapter(String mangaId) =>
      _storedChapter(historyBox.get('last_$mangaId'));

  static Future<void> saveLastPageIndex(String chapterId, int pageIndex) async {
    if (pageIndex < 0 || getSavedPageIndex(chapterId) == pageIndex) return;
    await historyBox.put('page_$chapterId', pageIndex);
  }

  static int getSavedPageIndex(String chapterId) {
    final stored = historyBox.get('page_$chapterId');
    return stored is int && stored >= 0 ? stored : 0;
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

  static ReaderAnchor? getWebtoonAnchor(String chapterId) =>
      ReaderAnchor.fromMap(historyBox.get('webtoon_anchor_$chapterId'));

  static Future<void> saveWebtoonAnchor(
    String chapterId,
    ReaderAnchor anchor,
  ) async {
    if (ReaderAnchor.fromMap(anchor.toMap()) == null) return;
    await historyBox.put('webtoon_anchor_$chapterId', anchor.toMap());
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
    final seenChapters = <String>{};

    for (final raw in rawEvents) {
      if (raw is! Map) continue;
      final manga = _storedManga(raw['mangaMap']);
      final savedChapter = _storedChapter(raw['chapterMap']);
      if (manga == null ||
          savedChapter == null ||
          (!allowNsfw && manga.isNsfw)) {
        continue;
      }
      if (!seenChapters.add(savedChapter.id)) continue;
      final readAt = DateTime.tryParse(raw['readAt']?.toString() ?? '');
      final storedPages = raw['pages'];
      final pages = storedPages is int && storedPages >= 0
          ? storedPages
          : (savedChapter.pages > 0 ? savedChapter.pages : 0);
      final chapter = Chapter(
        id: savedChapter.id,
        source: savedChapter.source,
        chapterNumber: savedChapter.chapterNumber,
        title: savedChapter.title,
        language: savedChapter.language,
        pages: pages,
        scanlator: savedChapter.scanlator,
        directPageUrls: savedChapter.directPageUrls,
        externalArchiveId: savedChapter.externalArchiveId,
      );
      totalCount++;
      totalPages += pages;
      if (readAt != null && !readAt.isAfter(now)) {
        if (!readAt.isBefore(startOfToday)) todayCount++;
        if (!readAt.isBefore(startOfWeek)) weekCount++;
      }

      mangaCounts[manga.id] = (mangaCounts[manga.id] ?? 0) + 1;
      mangaObjects[manga.id] = manga;

      if (pages > 0 && (longestCh == null || pages > longestCh.pages)) {
        longestCh = chapter;
      }
      if (pages > 0 && (shortestCh == null || pages < shortestCh.pages)) {
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
        'privacy_protection_enabled': privacyProtectionEnabled,
        'interface_style': settingsBox.get(
          'interface_style',
          defaultValue: 'glass',
        ),
        'auto_hide_menus': settingsBox.get(
          'auto_hide_menus',
          defaultValue: true,
        ),
        'tab_transitions': settingsBox.get(
          'tab_transitions',
          defaultValue: true,
        ),
        'reactive_reader': settingsBox.get(
          'reactive_reader',
          defaultValue: true,
        ),
        if (settingsBox.get(readingListsKey) is List)
          readingListsKey: settingsBox.get(readingListsKey),
      },
    };
    // Offline image files are not embedded. Never report an unbundled
    // downloaded chapter as restored offline content.
    return BackupCodec.encode(payload);
  }

  static Future<bool> importFullBackupJson(String rawInput) {
    // A second restore must not replace the first restore's recovery journal.
    final result = _restoreTail.then((_) => _importBackup(rawInput));
    _restoreTail = result.then<void>((_) {});
    return result;
  }

  static Future<bool> _importBackup(String rawInput) async {
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

      final settingChanges = <String, dynamic>{};
      for (final key in [
        'lock_nsfw_on_startup',
        'hide_zero_chapters',
        'data_saver_mode',
        'auto_hide_menus',
        'tab_transitions',
        'reactive_reader',
        'privacy_protection_enabled',
      ]) {
        final value = settings[key];
        if (value is bool) settingChanges[key] = value;
      }
      final style = settings['interface_style'];
      if (style is String) settingChanges['interface_style'] = style;
      final lists = settings[readingListsKey];
      if (lists is List) settingChanges[readingListsKey] = lists;
      if (profile != null) settingChanges['user_profile'] = profile.toMap();

      // Persist original values first. A failed write or an interrupted app
      // can roll back only the keys touched by this restore on the next launch.
      await recoverInterruptedRestore();
      await settingsBox.put(restoreJournalKey, {
        'favorites': _snapshot(favBox, favs.keys),
        'history': _snapshot(historyBox, hist.keys),
        'settings': _snapshot(settingsBox, settingChanges.keys),
      });
      if (favs.isNotEmpty) await favBox.putAll(favs);
      if (hist.isNotEmpty) await historyBox.putAll(hist);
      if (settingChanges.isNotEmpty) await settingsBox.putAll(settingChanges);
      await settingsBox.delete(restoreJournalKey);
      if (profile != null) profileNotifier.value = profile;
      if (settingChanges['privacy_protection_enabled'] is bool) {
        privacyProtectionNotifier.value =
            settingChanges['privacy_protection_enabled'] as bool;
      }
      return true;
    } catch (_) {
      try {
        await recoverInterruptedRestore();
      } catch (_) {
        // Keep the journal for startup recovery; do not log library contents.
        debugPrint('Restauração interrompida; recuperação local pendente.');
      }
      return false;
    }
  }

  static Map<String, dynamic> _snapshot(Box box, Iterable<String> keys) => {
    for (final key in keys)
      key: {'exists': box.containsKey(key), 'value': box.get(key)},
  };

  /// Called before exposing storage to the app, and before a new restore.
  static Future<void> recoverInterruptedRestore() async {
    final journal = settingsBox.get(restoreJournalKey);
    if (journal == null) return;
    if (journal is! Map) {
      throw const FormatException('Registro de recuperação inválido');
    }
    final sections = [
      ('favorites', favBox),
      ('history', historyBox),
      ('settings', settingsBox),
    ];
    for (final section in sections) {
      final entries = journal[section.$1];
      if (entries is! Map) {
        throw const FormatException('Registro de recuperação incompleto');
      }
      for (final entry in entries.entries) {
        final record = entry.value;
        if (entry.key is! String ||
            record is! Map ||
            record['exists'] is! bool) {
          throw const FormatException('Registro de recuperação inválido');
        }
      }
    }
    for (final section in sections) {
      for (final entry in (journal[section.$1] as Map).entries) {
        final record = entry.value as Map;
        if (record['exists'] == true) {
          await section.$2.put(entry.key, record['value']);
        } else {
          await section.$2.delete(entry.key);
        }
      }
    }
    await settingsBox.delete(restoreJournalKey);
  }

  // --- DOWNLOADS OFFLINE ---
  static const String offlineCoverPrefix = 'offline_cover_';

  static String? getOfflineCoverPath(String mangaId) {
    if (!Hive.isBoxOpen(settingsBoxName)) return null;
    final stored = settingsBox.get('$offlineCoverPrefix$mangaId');
    if (stored is String && stored.isNotEmpty && !kIsWeb) {
      final f = File(stored);
      if (f.existsSync() && f.lengthSync() > 0) return stored;
    }
    // Compatibilidade com registros em downloadsBox que salvaram coverPath diretamente
    if (Hive.isBoxOpen(downloadsBoxName)) {
      for (final raw in downloadsBox.values) {
        if (raw is! Map) continue;
        final manga = _storedManga(raw['manga']);
        final coverPath = raw['coverPath'];
        if (manga?.id == mangaId &&
            coverPath is String &&
            coverPath.isNotEmpty &&
            !kIsWeb &&
            File(coverPath).existsSync()) {
          return coverPath;
        }
      }
    }
    return null;
  }

  static Future<void> setOfflineCoverPath(String mangaId, String path) async {
    if (Hive.isBoxOpen(settingsBoxName)) {
      await settingsBox.put('$offlineCoverPrefix$mangaId', path);
    }
  }

  static Future<void> removeOfflineCoverMetadata(String mangaId) async {
    if (Hive.isBoxOpen(settingsBoxName)) {
      await settingsBox.delete('$offlineCoverPrefix$mangaId');
    }
  }

  /// Agrupa os downloads existentes e novos por obra, ordenando capítulos por número.
  static List<({Manga manga, List<Chapter> chapters, String? coverPath})>
      getGroupedDownloadedMangas() {
    final flat = getAllDownloadedChapters();
    final byMangaId = <String, ({
      Manga manga,
      Map<String, Chapter> chapters,
      String? coverPath
    })>{};

    for (final entry in flat) {
      final manga = _storedManga(entry['manga']);
      final chapter = _storedChapter(entry['chapter']);
      if (manga == null || chapter == null) continue;
      final entryCover = entry['coverPath'] is String ? entry['coverPath'] as String : null;
      final existing = byMangaId[manga.id];
      if (existing == null) {
        byMangaId[manga.id] = (
          manga: manga,
          chapters: {chapter.id: chapter},
          coverPath: entryCover ?? getOfflineCoverPath(manga.id),
        );
      } else {
        existing.chapters[chapter.id] = chapter;
      }
    }

    final groups = <({Manga manga, List<Chapter> chapters, String? coverPath})>[];
    for (final item in byMangaId.values) {
      final sortedChapters = item.chapters.values.toList()
        ..sort((a, b) => a.numericChapter.compareTo(b.numericChapter));
      groups.add((
        manga: item.manga,
        chapters: sortedChapters,
        coverPath: getOfflineCoverPath(item.manga.id) ?? item.coverPath,
      ));
    }

    groups.sort((a, b) =>
        a.manga.title.toLowerCase().compareTo(b.manga.title.toLowerCase()));
    return groups;
  }

  static bool isChapterDownloaded(String chapterId) {
    return downloadsBox.containsKey(chapterId);
  }

  static Future<void> deleteDownloadedChapter(String chapterId) async {
    if (!Hive.isBoxOpen(downloadsBoxName)) return;
    final paths = getDownloadedChapterPaths(chapterId);
    for (final p in paths) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await downloadsBox.delete(chapterId);
  }

  static List<String> getDownloadedChapterPaths(String chapterId) {
    final raw = downloadsBox.get(chapterId);
    if (raw is! Map) return [];
    final paths = raw['paths'];
    if (paths is! List ||
        paths.any((path) => path is! String || path.isEmpty)) {
      return [];
    }
    return List<String>.from(paths);
  }

  static List<Map<String, dynamic>> getAllDownloadedChapters() {
    final result = <Map<String, dynamic>>[];
    for (final raw in downloadsBox.values) {
      if (raw is! Map || raw.keys.any((key) => key is! String)) continue;
      final manga = _storedManga(raw['manga']);
      if (manga == null ||
          _storedChapter(raw['chapter']) == null ||
          (!nsfwMode.allowNsfwFetch && manga.isNsfw)) {
        continue;
      }
      result.add(Map<String, dynamic>.from(raw));
    }
    return result;
  }

  /// Retorna todos os capítulos baixados offline para uma obra específica,
  /// permitindo abrir e ler a obra pela Biblioteca mesmo sem internet.
  static List<Chapter> getDownloadedChaptersForManga(String mangaId) {
    if (!Hive.isBoxOpen(downloadsBoxName)) return const [];
    final chapters = <Chapter>[];
    final seen = <String>{};
    for (final raw in downloadsBox.values) {
      if (raw is! Map) continue;
      final manga = _storedManga(raw['manga']);
      final chapter = _storedChapter(raw['chapter']);
      if (manga == null || chapter == null) continue;
      if (manga.id == mangaId && seen.add(chapter.id)) {
        chapters.add(chapter);
      }
    }
    chapters.sort((a, b) => b.numericChapter.compareTo(a.numericChapter));
    return chapters;
  }

  static int countDownloadedChaptersForManga(String mangaId) =>
      getDownloadedChaptersForManga(mangaId).length;

  /// Combina capítulos baixados offline com o cache de capítulos da obra,
  /// garantindo que a página do mangá funcione 100% offline na Biblioteca.
  static List<Chapter> getOfflineOrCachedChapters(String mangaId) {
    final downloaded = getDownloadedChaptersForManga(mangaId);
    if (DeviceStateService.instance.isOffline) return downloaded;
    final cached = Hive.isBoxOpen(historyBoxName)
        ? getCachedMangaChapters(mangaId)
        : const <Chapter>[];
    if (downloaded.isEmpty) return cached;
    if (cached.isEmpty) return downloaded;
    final seen = <String>{};
    return [
      for (final ch in [...downloaded, ...cached])
        if (seen.add(ch.id)) ch,
    ];
  }

  // --- BACKUP AUTOMÁTICO PERSISTENTE NO DISPOSITIVO (SOBREVIVE À REINSTALAÇÃO) ---
  static bool get _isTestEnv =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static List<File> _desktopAutoBackupFiles() {
    if (kIsWeb || _isTestEnv) return [];
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.trim().isEmpty) return [];
    return [
      File('$home/.kuro_backup/kuro_auto_backup.json'),
      File('$home/.yomi_backup/yomi_auto_backup.txt'),
    ];
  }

  static void _attachAutoBackupWatchers() {
    for (final sub in _autoBackupSubscriptions) {
      sub.cancel();
    }
    _autoBackupSubscriptions.clear();
    if (!Hive.isBoxOpen(favBoxName) ||
        !Hive.isBoxOpen(historyBoxName) ||
        !Hive.isBoxOpen(settingsBoxName)) {
      return;
    }
    _autoBackupSubscriptions.addAll([
      favBox.watch().listen((_) => _scheduleAutoBackup()),
      historyBox.watch().listen((_) => _scheduleAutoBackup()),
      settingsBox.watch().listen((event) {
        if (event.key == lastAutoBackupAtKey ||
            event.key == restoreJournalKey) {
          return;
        }
        _scheduleAutoBackup();
      }),
    ]);
  }

  static void _scheduleAutoBackup() {
    if (_restoringAutoBackup) return;
    _autoBackupDebounce?.cancel();
    _autoBackupDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(syncAutoBackupNow());
      CloudSyncService.scheduleAutoCloudSync();
    });
  }

  /// Salva imediatamente o estado completo do usuário no armazenamento persistente
  /// do dispositivo e no agente de backup do sistema operacional.
  static Future<bool> syncAutoBackupNow() async {
    if (_restoringAutoBackup ||
        !Hive.isBoxOpen(favBoxName) ||
        !Hive.isBoxOpen(historyBoxName) ||
        !Hive.isBoxOpen(settingsBoxName)) {
      return false;
    }
    try {
      final hasUserData =
          favBox.isNotEmpty ||
          historyBox.isNotEmpty ||
          userProfile.isConfigured ||
          getReadingLists().isNotEmpty;
      if (!hasUserData) return false;

      final payload = exportFullBackupJson();
      bool savedAny = false;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final ok = await _autoBackupChannel.invokeMethod<bool>(
            'saveAutoBackup',
            {'payload': payload},
          );
          if (ok == true) savedAny = true;
        } catch (_) {}
      }

      final files = _desktopAutoBackupFiles();
      for (final file in files) {
        try {
          if (!file.parent.existsSync()) {
            await file.parent.create(recursive: true);
          }
          await file.writeAsString(payload, flush: true);
          savedAny = true;
        } catch (_) {}
      }

      if (savedAny && Hive.isBoxOpen(settingsBoxName)) {
        await settingsBox.put(
          lastAutoBackupAtKey,
          DateTime.now().toIso8601String(),
        );
      }
      return savedAny;
    } catch (_) {
      return false;
    }
  }

  /// Tenta localizar e restaurar automaticamente o backup salvo no aparelho
  /// (por exemplo, logo após desinstalar e reinstalar o aplicativo).
  static Future<bool> tryRestoreFromDeviceAutoBackup() async {
    if (_restoringAutoBackup) return false;
    _restoringAutoBackup = true;
    try {
      String? payload;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          payload = await _autoBackupChannel.invokeMethod<String>(
            'loadAutoBackup',
          );
        } catch (_) {}
      }
      if (payload == null || payload.trim().isEmpty) {
        final files = _desktopAutoBackupFiles();
        for (final file in files) {
          if (file.existsSync()) {
            try {
              final text = await file.readAsString();
              if (text.trim().isNotEmpty) {
                payload = text;
                break;
              }
            } catch (_) {}
          }
        }
      }
      if (payload == null || payload.trim().isEmpty) return false;
      final restored = await importFullBackupJson(payload.trim());
      if (restored && Hive.isBoxOpen(settingsBoxName)) {
        await settingsBox.put(
          lastAutoBackupAtKey,
          DateTime.now().toIso8601String(),
        );
      }
      return restored;
    } catch (_) {
      return false;
    } finally {
      _restoringAutoBackup = false;
    }
  }

  /// Exports full backup as a `.kuro` file and invokes the native system share sheet
  /// (permitting direct save to Google Drive, Telegram, WhatsApp, Local Downloads, etc.).
  static Future<bool> exportBackupToFile() async {
    try {
      final payload = exportFullBackupJson();
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final file = File('${tempDir.path}/kuro_backup_$dateStr.kuro');
      await file.writeAsString(payload, flush: true);
      final result = await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'application/json',
            name: 'kuro_backup_$dateStr.kuro',
          ),
        ],
        subject: 'Backup Kuro Reader ($dateStr)',
      );
      return result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.dismissed;
    } catch (e) {
      debugPrint('Erro ao exportar backup para arquivo: $e');
      return false;
    }
  }

  /// Opens the system file picker to select a `.kuro` or `.json` backup file
  /// from local storage, Google Drive, SD Card, etc. and restores it safely.
  static Future<bool> importBackupFromFile() async {
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null) return false;
      final path = picked.path;
      String? content;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          content = await file.readAsString();
        }
      }
      if (content == null || content.trim().isEmpty) {
        final bytes = await picked.readAsBytes();
        if (bytes.isNotEmpty) {
          content = utf8.decode(bytes);
        }
      }
      if (content == null || content.trim().isEmpty) return false;
      return await importFullBackupJson(content.trim());
    } catch (e) {
      debugPrint('Erro ao importar backup de arquivo: $e');
      return false;
    }
  }
}
