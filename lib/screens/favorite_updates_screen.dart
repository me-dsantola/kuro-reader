import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/favorite_updates_service.dart';
import '../services/storage_service.dart';
import 'manga_detail_screen.dart';
import 'home_tabs.dart';

/// In-app notifications only. No Android notification permission or background
/// tracking is required, and hidden adult titles are never listed.
class FavoriteUpdatesScreen extends StatelessWidget {
  const FavoriteUpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novos capítulos'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          StorageService.settingsBox.listenable(),
          StorageService.nsfwModeNotifier,
        ]),
        builder: (context, _) {
          return ValueListenableBuilder(
            valueListenable: StorageService.favBox.listenable(),
            builder: (context, Box favoritesBox, _) {
              final favorites = StorageService.getFavorites();
              final updates = <({Manga manga, List<Chapter> chapters})>[];
              for (final manga in favorites) {
                final chapters = FavoriteUpdatesService.pendingFor(manga);
                if (chapters.isNotEmpty) {
                  updates.add((manga: manga, chapters: chapters));
                }
              }

              if (updates.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none_rounded,
                            size: 56, color: Colors.white38),
                        SizedBox(height: 14),
                        Text('Nenhuma atualização pendente'),
                        SizedBox(height: 8),
                        Text(
                          'Na Biblioteca, toque em verificar para procurar capítulos novos. A primeira consulta estabelece o histórico.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: updates.length,
                itemBuilder: (context, index) {
                  final entry = updates[index];
                  return Card(
                    color: YomiPalette.surface,
                    child: ListTile(
                      leading: const Icon(Icons.auto_stories_rounded,
                          color: YomiPalette.sakuraPink),
                      title: Text(entry.manga.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${entry.chapters.length} novo(s) • ${entry.chapters.take(3).map((ch) => 'Cap. ${ch.chapterNumber}').join(', ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Marcar atualizações como vistas',
                        icon: const Icon(Icons.done_all_rounded),
                        onPressed: () async {
                          await FavoriteUpdatesService.markSeen(entry.manga);
                        },
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MangaDetailScreen(
                              manga: entry.manga,
                              heroTag: 'update_${entry.manga.compositeId}',
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
