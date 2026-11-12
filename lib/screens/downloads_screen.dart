import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/download_manager.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/yomi_blobatar_studio.dart';
import 'home_overview_screen.dart';
import 'home_tabs.dart';
import 'reader_screen.dart';

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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: YomiCoverImage(
                                      manga: manga,
                                      width: 52,
                                      height: 74,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          manga.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          batchStatus != null
                                              ? 'Baixando ${batchStatus.completed}/${batchStatus.total} capítulos…'
                                              : '${chapters.length} ${chapters.length == 1 ? 'capítulo salvo' : 'capítulos salvos'} • Offline pronto',
                                          style: TextStyle(
                                            color: palette.secondary,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Apagar todos os capítulos da obra',
                                    icon: const Icon(
                                      Icons.delete_sweep_rounded,
                                      color: Colors.white54,
                                    ),
                                    onPressed: () =>
                                        _delete(context, mangaGroup: manga),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(color: Colors.white10, height: 1),
                            for (final chapter in chapters)
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 2,
                                ),
                                title: Text(
                                  'Cap. ${chapter.chapterNumber} (${chapter.language})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: Text(
                                  '${StorageService.getDownloadedChapterPaths(chapter.id).length} págs',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  tooltip: 'Apagar capítulo',
                                  onPressed: () =>
                                      _delete(context, chapter: chapter),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReaderScreen(
                                        manga: manga,
                                        chapter: chapter,
                                        allChapters: HomeOverviewScreen
                                            .buildSortedChapterList(
                                          manga,
                                          chapter,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
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
