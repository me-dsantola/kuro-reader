import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/download_manager.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/yomi_blobatar_studio.dart';
import 'home_tabs.dart';
import 'offline_manga_detail_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  Future<void> _delete(
    BuildContext context, {
    Chapter? chapter,
    Manga? mangaGroup,
  }) async {
    final all = chapter == null && mangaGroup == null;
    final title = all
        ? 'Apagar todos os downloads?'
        : mangaGroup != null
            ? 'Apagar downloads de "${mangaGroup.title}"?'
            : 'Apagar este capítulo?';
    final body = all
        ? 'Os arquivos serão removidos do aparelho, incluindo downloads ocultos pelo filtro de conteúdo. Favoritos e progresso serão preservados.'
        : mangaGroup != null
            ? 'Todos os capítulos baixados e a capa offline desta obra serão removidos. Favoritos, histórico e progresso serão preservados.'
            : 'O capítulo ${chapter!.chapterNumber} poderá ser baixado novamente. O progresso de leitura será preservado.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      if (all) {
        await DownloadManager.deleteAllDownloads();
      } else if (mangaGroup != null) {
        await DownloadManager.deleteMangaDownloads(mangaGroup.id);
      } else if (chapter != null) {
        await DownloadManager.deleteChapter(chapter.id);
      }
      if (!context.mounted) return;
      AppFeedback.show(
        context,
        SnackBar(
          content: Text(
            all ? 'Armazenamento offline limpo.' : 'Download removido.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      AppFeedback.show(
        context,
        const SnackBar(
          content: Text(
            'Não foi possível apagar. Aguarde os downloads e tente novamente.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Icon(
                  Icons.download_for_offline_rounded,
                  color: palette.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Capítulos salvos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Apagar todos os downloads',
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  color: palette.secondary,
                ),
                onPressed: () => _delete(context),
              ),
            ],
          ),
          body: ValueListenableBuilder<NsfwDisplayMode>(
            valueListenable: StorageService.nsfwModeNotifier,
            builder: (context, _, _) {
              return ListenableBuilder(
                listenable: Listenable.merge([
                  StorageService.downloadsBox.listenable(),
                  DownloadManager.activeMangaDownloads,
                  DownloadManager.activeDownloads,
                ]),
                builder: (context, _) {
                  final groups = StorageService.getGroupedDownloadedMangas();
                  if (groups.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 64,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Nenhum capítulo disponível com os filtros atuais',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const YomiMascotCompanionCard(
                              message:
                                  'Baixe capítulos nas páginas das obras para ler mesmo sem internet!',
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final manga = group.manga;
                      final chapters = group.chapters;
                      final batchStatus =
                          DownloadManager.activeMangaDownloads.value[manga.id];

                      return Material(
                        color: YomiPalette.surface,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Colors.white10),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: YomiCoverImage(
                              manga: manga,
                              width: 52,
                              height: 76,
                            ),
                          ),
                          title: Text(
                            manga.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              height: 1.2,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.offline_pin_rounded,
                                  size: 15,
                                  color: palette.secondary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    batchStatus != null
                                        ? 'Baixando ${batchStatus.completed}/${batchStatus.total}…'
                                        : '${chapters.length} ${chapters.length == 1 ? 'capítulo salvo' : 'capítulos salvos'} • Offline',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.secondary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Apagar todos os capítulos da obra',
                                icon: const Icon(
                                  Icons.delete_sweep_rounded,
                                  color: Colors.white38,
                                ),
                                onPressed: () =>
                                    _delete(context, mangaGroup: manga),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white54,
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OfflineMangaDetailScreen(
                                  manga: manga,
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
      },
    );
  }
}
