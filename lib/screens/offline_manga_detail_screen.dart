import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/storage_service.dart';
import '../services/yomi_theme_system.dart';
import '../widgets/app_feedback.dart';
import '../widgets/yomi_brand_widgets.dart';
import 'reader_screen.dart';

/// Tela de Detalhes Offline da Obra:
/// Apresenta exclusivamente os capítulos realmente baixados e disponíveis no armazenamento local,
/// permitindo a leitura e gerenciamento 100% desconectado sem depender de rede.
class OfflineMangaDetailScreen extends StatefulWidget {
  final Manga manga;

  const OfflineMangaDetailScreen({
    super.key,
    required this.manga,
  });

  @override
  State<OfflineMangaDetailScreen> createState() =>
      _OfflineMangaDetailScreenState();
}

class _OfflineMangaDetailScreenState extends State<OfflineMangaDetailScreen> {
  bool _sortAscending = true;

  List<Chapter> _getDownloadedChapters() {
    final groups = StorageService.getGroupedDownloadedMangas();
    final match = groups.where((g) => g.manga.id == widget.manga.id);
    if (match.isEmpty) return const [];
    final chapters = List<Chapter>.from(match.first.chapters);
    chapters.sort((a, b) {
      final numA = double.tryParse(a.chapterNumber) ?? 0.0;
      final numB = double.tryParse(b.chapterNumber) ?? 0.0;
      return _sortAscending ? numA.compareTo(numB) : numB.compareTo(numA);
    });
    return chapters;
  }

  Future<void> _deleteChapter(Chapter chapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar capítulo offline?'),
        content: Text(
          'Deseja remover as páginas do Capítulo ${chapter.chapterNumber} do seu aparelho?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await StorageService.deleteDownloadedChapter(chapter.id);
      if (mounted) {
        AppFeedback.message(context, 'Capítulo ${chapter.chapterNumber} apagado.');
        final remaining = _getDownloadedChapters();
        if (remaining.isEmpty) {
          Navigator.pop(context);
        }
      }
    }
  }

  Future<void> _deleteAllChapters(List<Chapter> chapters) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar todos os capítulos salvos?'),
        content: Text(
          'Deseja remover todos os ${chapters.length} capítulos baixados de "${widget.manga.title}" do armazenamento local?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar Todos'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      for (final ch in chapters) {
        await StorageService.deleteDownloadedChapter(ch.id);
      }
      if (mounted) {
        AppFeedback.message(
          context,
          'Todos os capítulos offline desta obra foram removidos.',
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<YomiThemeTokens>(
      valueListenable: YomiThemeController.instance,
      builder: (context, theme, _) {
        return ValueListenableBuilder(
          valueListenable: StorageService.downloadsBox.listenable(),
          builder: (context, Box box, _) {
            final chapters = _getDownloadedChapters();
            if (chapters.isEmpty) {
              return Scaffold(
                backgroundColor: theme.background,
                appBar: AppBar(
                  backgroundColor: theme.surface,
                  title: const Text('Detalhes Offline'),
                ),
                body: const Center(
                  child: Text('Nenhum capítulo disponível offline.'),
                ),
              );
            }

            final firstChapter = chapters.first;
            var totalPages = 0;
            for (final ch in chapters) {
              totalPages +=
                  StorageService.getDownloadedChapterPaths(ch.id).length;
            }

            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
                title: Text(
                  widget.manga.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: theme.textPrimary),
                  tooltip: 'Voltar aos downloads',
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Apagar todos os capítulos baixados desta obra',
                    icon: Icon(
                      Icons.delete_sweep_rounded,
                      color: theme.textSecondary,
                    ),
                    onPressed: () => _deleteAllChapters(chapters),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // Cabeçalho da obra (Capa + Metadados Locais)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: YomiCoverImage(
                          manga: widget.manga,
                          width: 105,
                          height: 152,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: theme.accentPrimary.withValues(
                                  alpha: 0.18,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.accentPrimary.withValues(
                                    alpha: 0.40,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'ARMAZENAMENTO OFFLINE',
                                style: TextStyle(
                                  color: theme.accentPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.manga.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${chapters.length} ${chapters.length == 1 ? 'capítulo salvo' : 'capítulos salvos'} • $totalPages páginas',
                              style: TextStyle(
                                color: theme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.offline_pin_rounded,
                                  size: 16,
                                  color: theme.accentSecondary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Pronto para leitura sem internet',
                                  style: TextStyle(
                                    color: theme.accentSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Botão de Leitura Direta
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accentPrimary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: Text(
                      'Ler Capítulo ${firstChapter.chapterNumber} (Offline)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReaderScreen(
                            manga: widget.manga,
                            chapter: firstChapter,
                            allChapters: chapters,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Título da Seção + Alternador de Ordenação
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Capítulos Salvos (${chapters.length})',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        tooltip: _sortAscending
                            ? 'Ordenação: Crescente (Toque para decrescente)'
                            : 'Ordenação: Decrescente (Toque para crescente)',
                        icon: Icon(
                          _sortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 20,
                          color: theme.textSecondary,
                        ),
                        onPressed: () {
                          setState(() => _sortAscending = !_sortAscending);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Lista exclusiva dos capítulos realmente baixados
                  Material(
                    color: theme.surface,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.border),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: chapters.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: theme.border, height: 1),
                      itemBuilder: (context, idx) {
                        final chapter = chapters[idx];
                        final paths = StorageService.getDownloadedChapterPaths(
                          chapter.id,
                        );
                        final isRead = StorageService.isChapterRead(chapter.id);

                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          leading: Icon(
                            isRead
                                ? Icons.check_circle_rounded
                                : Icons.download_done_rounded,
                            color: isRead
                                ? theme.accentPrimary
                                : theme.accentSecondary,
                            size: 22,
                          ),
                          title: Text(
                            'Capítulo ${chapter.chapterNumber} (${chapter.language})',
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${paths.length} páginas salvas no dispositivo',
                            style: TextStyle(
                              color: theme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: theme.textSecondary,
                              size: 20,
                            ),
                            tooltip: 'Apagar capítulo',
                            onPressed: () => _deleteChapter(chapter),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReaderScreen(
                                  manga: widget.manga,
                                  chapter: chapter,
                                  allChapters: chapters,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
