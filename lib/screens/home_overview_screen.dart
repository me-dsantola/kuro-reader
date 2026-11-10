import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/storage_service.dart';
import 'home_tabs.dart';
import 'manga_detail_screen.dart';

/// Lightweight reading-first home. The detailed profile and metrics remain
/// available on the Profile tab instead of being forced on app startup.
class HomeOverviewScreen extends StatelessWidget {
  final VoidCallback onExplore;
  final VoidCallback onLibrary;

  const HomeOverviewScreen({
    super.key,
    required this.onExplore,
    required this.onLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const YomiEnsoLogo()),
      body: ValueListenableBuilder(
        valueListenable: StorageService.historyBox.listenable(
          keys: ['recent_reading_list'],
        ),
        builder: (context, Box box, _) => ValueListenableBuilder(
          valueListenable: StorageService.nsfwModeNotifier,
          builder: (context, mode, _) {
            final recent = StorageService.getContinueReadingList().take(12).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const Text(
                  'Sua próxima leitura',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Continue de onde parou ou encontre uma nova história.',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onExplore,
                        icon: const Icon(Icons.explore_rounded),
                        label: const Text('Explorar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: YomiPalette.ensoRed,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onLibrary,
                        icon: const Icon(Icons.bookmarks_rounded),
                        label: const Text('Biblioteca'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'Continuar lendo',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (recent.isEmpty)
                  const Card(
                    color: YomiPalette.surface,
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Suas leituras recentes aparecerão aqui.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  )
                else
                  for (final item in recent)
                    Builder(builder: (context) {
                      final manga = item['manga'] as Manga;
                      final chapter = item['chapter'] as Chapter;
                      return Card(
                        color: YomiPalette.surface,
                        child: ListTile(
                          leading: const Icon(Icons.menu_book_rounded,
                              color: YomiPalette.sakuraPink),
                          title: Text(
                            manga.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('Última leitura: cap. ${chapter.chapterNumber}'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MangaDetailScreen(
                                manga: manga,
                                heroTag: 'home_${manga.compositeId}',
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
              ],
            );
          },
        ),
      ),
    );
  }
}
