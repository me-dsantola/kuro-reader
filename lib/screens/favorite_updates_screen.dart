import '../widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/favorite_updates_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/yomi_blobatar_studio.dart';
import 'manga_detail_screen.dart';
import 'home_tabs.dart';

/// In-app notifications only. No Android notification permission or background
/// tracking is required, and hidden adult titles are never listed.
class FavoriteUpdatesScreen extends StatefulWidget {
  const FavoriteUpdatesScreen({super.key});

  @override
  State<FavoriteUpdatesScreen> createState() => _FavoriteUpdatesScreenState();
}

class _FavoriteUpdatesScreenState extends State<FavoriteUpdatesScreen> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final favorites = StorageService.getFavorites();
      if (favorites.isNotEmpty &&
          FavoriteUpdatesService.allPending(favorites).isEmpty) {
        _checkUpdates();
      }
    });
  }

  Future<void> _checkUpdates() async {
    if (_checking) return;
    final favorites = StorageService.getFavorites();
    if (favorites.isEmpty) return;

    setState(() => _checking = true);
    try {
      final found = await FavoriteUpdatesService.checkAllFavorites(favorites);
      if (!mounted) return;
      if (found > 0) {
        AppFeedback.show(
          context,
          SnackBar(
            content: Text(
              '$found novo(s) capítulo(s) encontrado(s) nos seus favoritos!',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return Scaffold(
          backgroundColor: YomiPalette.pitchBlack,
          appBar: AppBar(
            title: Row(
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  color: palette.primary,
                ),
                const SizedBox(width: 10),
                const Text('Notificações & Capítulos'),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Verificar novos capítulos agora',
                onPressed: _checking ? null : _checkUpdates,
                icon: _checking
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.primary,
                        ),
                      )
                    : Icon(Icons.sync_rounded, color: palette.secondary),
              ),
              IconButton(
                tooltip: 'Limpar todas as notificações',
                onPressed: () async {
                  await FavoriteUpdatesService.markAllSeen(
                    StorageService.getFavorites(),
                  );
                },
                icon: const Icon(Icons.done_all_rounded, color: Colors.white70),
              ),
            ],
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_checking) ...[
                              CircularProgressIndicator(color: palette.primary),
                              const SizedBox(height: 16),
                              const Text(
                                'Consultando capítulos dos seus favoritos...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ] else ...[
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 56,
                                color: palette.secondary.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                favorites.isEmpty
                                    ? 'Você ainda não tem obras favoritas'
                                    : 'Nenhuma atualização pendente',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                favorites.isEmpty
                                    ? 'Adicione mangás aos Favoritos para acompanhar lançamentos e novos capítulos por aqui.'
                                    : 'Seus favoritos estão em dia! Toque no botão abaixo sempre que quiser buscar novos capítulos.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                ),
                              ),
                              if (favorites.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: palette.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _checkUpdates,
                                  icon: const Icon(Icons.sync_rounded),
                                  label: const Text(
                                    'Verificar capítulos agora',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              const YomiMascotCompanionCard(
                                message:
                                    'Eu aviso aqui sempre que seus mangás favoritos tiverem capítulos novos para ler!',
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: palette.primary,
                    onRefresh: _checkUpdates,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: updates.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = updates[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: palette.primary.withValues(alpha: 0.28),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: YomiCoverImage(
                                manga: entry.manga,
                                width: 46,
                                height: 64,
                              ),
                            ),
                            title: Text(
                              entry.manga.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${entry.chapters.length} cap(s) disponível(is) • ${entry.chapters.take(3).map((ch) => 'Cap. ${ch.chapterNumber}').join(', ')}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.soft,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Marcar atualizações como vistas',
                              icon: Icon(
                                Icons.check_circle_outline_rounded,
                                color: palette.secondary,
                              ),
                              onPressed: () async {
                                await FavoriteUpdatesService.markSeen(
                                  entry.manga,
                                );
                              },
                            ),
                            onTap: () async {
                              await FavoriteUpdatesService.markSeen(
                                entry.manga,
                              );
                              if (!context.mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MangaDetailScreen(
                                    manga: entry.manga,
                                    heroTag:
                                        'update_${entry.manga.compositeId}',
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
