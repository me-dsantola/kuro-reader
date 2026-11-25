import 'package:hive/hive.dart';
import '../models/manga_models.dart';

class ReaderMetrics {
  final int chapters, minutes, library, favorites, reading, completed;
  final int monthlyChapters, monthlyMinutes, streak;
  final List<MapEntry<Manga, int>> top;
  final List<String> genres;

  const ReaderMetrics({
    required this.chapters,
    required this.minutes,
    required this.library,
    required this.favorites,
    required this.reading,
    required this.completed,
    required this.monthlyChapters,
    required this.monthlyMinutes,
    required this.streak,
    required this.top,
    required this.genres,
  });

  String get rank => ReadingMetricsSummary(
    chaptersReadToday: 0,
    chaptersReadThisWeek: 0,
    totalChaptersRead: chapters,
    totalPagesRead: 0,
  ).rankTitle;

  static ReaderMetrics calculate(
    Box history,
    List<Manga> favorites,
    List<UserReadingList> lists, {
    required bool allowAdult,
    DateTime? clock,
  }) {
    final now = (clock ?? DateTime.now()).toLocal();
    final today = DateTime.utc(now.year, now.month, now.day);
    final works = <String, Manga>{};
    final library = <String>{};
    final favoriteIds = <String>{};
    final started = <String>{};
    final chaptersByWork = <String, Set<String>>{};
    final completedIds = <String>{};
    void add(Manga manga) {
      if (allowAdult || !manga.isNsfw) {
        works[manga.id] = manga;
        library.add(manga.id);
      }
    }

    for (final manga in favorites) {
      add(manga);
      if (works.containsKey(manga.id)) favoriteIds.add(manga.id);
    }
    for (final list in lists) {
      for (final manga in list.mangas) {
        add(manga);
      }
    }
    final recent = history.get('recent_reading_list');
    if (recent is List) {
      for (final item in recent.whereType<Map>()) {
        final raw = item['manga'];
        if (raw is! Map) continue;
        final manga = Manga.fromMap(Map<String, dynamic>.from(raw));
        add(manga);
        if (allowAdult || !manga.isNsfw) started.add(manga.id);
      }
    }
    final events = <String, Map>{};
    final oldEvents = history.get('reading_events_log');
    if (oldEvents is List) {
      for (final event in oldEvents.whereType<Map>()) {
        final chapter = event['chapterMap'];
        final manga = event['mangaMap'];
        final id =
            event['chapterId'] ?? (chapter is Map ? chapter['id'] : null);
        if (id is! String || manga is! Map) continue;
        final work = Manga.fromMap(Map<String, dynamic>.from(manga));
        add(work);
        events.putIfAbsent(
          id,
          () => {
            ...event,
            'mangaId': work.id,
            'number': chapter is Map ? chapter['chapterNumber'] : null,
          },
        );
      }
    }
    final ids = <String>{...events.keys};
    final blocked = <String>{};
    for (final key in history.keys.whereType<String>()) {
      if (key.startsWith('manga_meta_')) {
        final raw = history.get(key);
        if (raw is Map) {
          final manga = Manga.fromMap(Map<String, dynamic>.from(raw));
          if (!allowAdult && manga.isNsfw) {
            blocked.add(manga.id);
          } else if (history.containsKey('last_${manga.id}')) {
            add(manga);
            started.add(manga.id);
          }
        }
      } else if (key.startsWith('read_')) {
        ids.add(key.substring(5));
      } else if (key.startsWith('reading_metric_')) {
        final event = history.get(key);
        if (event is! Map || event['changedAt'] is! String) continue;
        final id = key.substring('reading_metric_'.length);
        ids.add(id);
        events[id] = event;
      }
    }
    var chapters = 0, seconds = 0, month = 0, monthSeconds = 0, streak = 0;
    final days = <int>{};
    final counts = <String, int>{};
    final genreCounts = <String, int>{};

    for (final id in ids) {
      final event = events[id];
      final dated = event?['changedAt'] is String;
      final flag = history.get('read_$id');
      final readAt = event?['readAt'];
      if (dated
          ? readAt is! String
          : flag == false || (event == null && flag != true)) {
        continue;
      }
      final workId = event?['mangaId'];
      if (blocked.contains(workId) ||
          (!allowAdult &&
              event?['mangaMap'] is Map &&
              event?['mangaMap']['isNsfw'] == true)) {
        continue;
      }
      final pages = event?['pages'];
      final duration = pages is int && pages > 0 ? pages * 20 : 300;
      chapters++;
      seconds += duration;
      if (workId is String && works.containsKey(workId)) {
        started.add(workId);
        final number = event?['number']?.toString() ?? '';
        chaptersByWork
            .putIfAbsent(workId, () => {})
            .add(
              double.tryParse(number)?.toString() ??
                  (number.isEmpty ? id : number),
            );
      }
      final date = DateTime.tryParse(
        event?['readAt']?.toString() ?? '',
      )?.toLocal();
      if (date == null || date.isAfter(now)) continue;
      final day = today
          .difference(DateTime.utc(date.year, date.month, date.day))
          .inDays;
      if (day < 0 || day >= 30) continue;
      days.add(day);
      month++;
      monthSeconds += duration;
      final manga = works[workId];
      if (manga == null) continue;
      counts.update(manga.id, (n) => n + 1, ifAbsent: () => 1);
      for (final tag
          in (manga.readingGenres ?? manga.tags)
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toSet()) {
        genreCounts.update(tag, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    for (final id in started) {
      final stored = history.get('chapters_count_$id');
      final total = stored is int && stored > 0
          ? stored
          : works[id]?.availableChaptersCount ?? 0;
      if (total > 0 && (chaptersByWork[id]?.length ?? 0) >= total) {
        completedIds.add(id);
      }
    }
    for (var day = days.contains(0) ? 0 : 1; days.contains(day); day++) {
      streak++;
    }
    List<String> sorted(Map<String, int> input) =>
        input.keys.toList()..sort((a, b) {
          final result = input[b]!.compareTo(input[a]!);
          return result != 0 ? result : a.compareTo(b);
        });
    return ReaderMetrics(
      chapters: chapters,
      minutes: (seconds / 60).round(),
      library: library.length,
      favorites: favoriteIds.length,
      reading: started.length - completedIds.length,
      completed: completedIds.length,
      monthlyChapters: month,
      monthlyMinutes: (monthSeconds / 60).round(),
      streak: streak,
      top: sorted(
        counts,
      ).take(3).map((id) => MapEntry(works[id]!, counts[id]!)).toList(),
      genres: sorted(genreCounts).take(3).toList(),
    );
  }
}
