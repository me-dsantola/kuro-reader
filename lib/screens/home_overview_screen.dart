import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/storage_service.dart';
import '../services/favorite_updates_service.dart';
import 'favorite_updates_screen.dart';
import 'reader_screen.dart';
import 'home_tabs.dart';

/// Reading shortcuts share the same covers, artwork and surfaces as the library.
class HomeOverviewScreen extends StatelessWidget {
  final VoidCallback onExplore;
  final VoidCallback onLibrary;

  const HomeOverviewScreen({
    super.key,
    required this.onExplore,
    required this.onLibrary,
  });

  void _openChapter(BuildContext context, Manga manga, Chapter chapter) {
    final cached = StorageService.getCachedMangaChapters(manga.id);
    final chapters = <Chapter>[
      ...cached,
      if (!cached.any((c) => c.id == chapter.id)) chapter,
    ]..sort((a, b) => a.numericChapter.compareTo(b.numericChapter));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReaderScreen(manga: manga, chapter: chapter, allChapters: chapters),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const YomiEnsoLogo(),
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    body: ValueListenableBuilder(
      valueListenable: StorageService.historyBox.listenable(
        keys: ['recent_reading_list'],
      ),
      builder: (context, Box box, _) => ValueListenableBuilder(
        valueListenable: StorageService.nsfwModeNotifier,
        builder: (context, mode, _) {
          final recent = StorageService.getContinueReadingList()
              .take(12)
              .toList();
          return ValueListenableBuilder(
            valueListenable: StorageService.historyBox.listenable(
              keys: [
                for (final item in recent)
                  'page_${(item['chapter'] as Chapter).id}',
              ],
            ),
            builder: (context, Box history, _) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _welcome(context),
                const SizedBox(height: 20),
                if (recent.isNotEmpty) ...[
                  _section('Continuar lendo', Icons.auto_stories_rounded),
                  const SizedBox(height: 12),
                  _readingCard(context, recent.first, featured: true),
                  const SizedBox(height: 20),
                ],
                _shortcuts(context),
                const SizedBox(height: 16),
                _updates(context),
                if (recent.length > 1) ...[
                  const SizedBox(height: 24),
                  _section('Outras leituras', Icons.history_rounded),
                  const SizedBox(height: 12),
                  for (final item in recent.skip(1)) ...[
                    _readingCard(context, item),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _welcome(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF280D19), YomiPalette.surface],
        ),
        border: Border.all(color: YomiPalette.ensoRed.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: Opacity(opacity: 0.35, child: YomiSakuraArtwork()),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SEU REFÚGIO DE HISTÓRIAS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: YomiPalette.sakuraSoft,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Sua próxima leitura',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cada capítulo, um novo universo.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _section(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 18, color: YomiPalette.sakuraPink),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );

  Widget _readingCard(
    BuildContext context,
    Map<String, dynamic> item, {
    bool featured = false,
  }) {
    final manga = item['manga'] as Manga;
    final chapter = item['chapter'] as Chapter;
    final page = StorageService.getSavedPageIndex(chapter.id) + 1;
    final progress = chapter.pages > 0
        ? (page / chapter.pages).clamp(0.0, 1.0)
        : null;
    void open() => _openChapter(context, manga, chapter);
    return Material(
      color: featured ? YomiPalette.surfaceElevated : YomiPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: featured
              ? YomiPalette.ensoRed.withValues(alpha: 0.4)
              : Colors.white10,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: EdgeInsets.all(featured ? 16 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: YomiCoverImage(
                      manga: manga,
                      width: featured ? 84 : 56,
                      height: featured ? 126 : 84,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (featured) ...[
                          const Text(
                            'DE ONDE VOCÊ PAROU',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w800,
                              color: YomiPalette.sakuraPink,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          manga.title,
                          maxLines: featured ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: featured ? 17 : 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cap. ${chapter.chapterNumber} · ${chapter.language}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: YomiPalette.sakuraSoft,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          chapter.pages > 0
                              ? 'Página $page de ${chapter.pages}'
                              : 'Página $page',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!featured)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: YomiPalette.sakuraPink,
                      ),
                    ),
                ],
              ),
              if (featured) ...[
                const SizedBox(height: 16),
                if (progress != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      color: YomiPalette.ensoRed,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                FilledButton.icon(
                  onPressed: open,
                  style: FilledButton.styleFrom(
                    backgroundColor: YomiPalette.ensoRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Continuar leitura'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcuts(BuildContext context) {
    final explore = _shortcut(
      'Explorar',
      'Encontre novas histórias',
      Icons.explore_rounded,
      onExplore,
    );
    final library = _shortcut(
      'Biblioteca',
      'Suas obras favoritas',
      Icons.bookmarks_rounded,
      onLibrary,
    );
    if (MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [explore, const SizedBox(height: 12), library],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: explore),
          const SizedBox(width: 12),
          Expanded(child: library),
        ],
      ),
    );
  }

  Widget _shortcut(
    String title,
    String description,
    IconData icon,
    VoidCallback onTap,
  ) => Material(
    color: YomiPalette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Colors.white10),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: YomiPalette.sakuraPink, size: 25),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _updates(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      StorageService.settingsBox.listenable(),
      StorageService.favBox.listenable(),
    ]),
    builder: (context, _) {
      final count = StorageService.getFavorites().fold<int>(
        0,
        (total, manga) =>
            total + FavoriteUpdatesService.pendingFor(manga).length,
      );
      return Material(
        color: YomiPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white10),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: const Icon(
            Icons.notifications_outlined,
            color: YomiPalette.sakuraPink,
          ),
          title: const Text(
            'Novos capítulos',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            count == 0
                ? 'Confira as novidades da Biblioteca'
                : '$count capítulo(s) aguardando leitura',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FavoriteUpdatesScreen()),
          ),
        ),
      );
    },
  );
}
