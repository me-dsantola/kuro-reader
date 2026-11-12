import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../widgets/yomi_blobatar_studio.dart';
import '../models/manga_models.dart';
import '../services/storage_service.dart';
import '../services/library_progress.dart';
import '../services/profile_palette_service.dart';
import '../services/device_state_service.dart';
import '../services/favorite_updates_service.dart';
import '../services/mangadex_service.dart';
import '../services/download_manager.dart';
import '../widgets/app_feedback.dart';
import 'home_tabs.dart';
import 'home_overview_screen.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

class LibraryCollectionScreen extends StatefulWidget {
  final VoidCallback? onExplore;
  const LibraryCollectionScreen({super.key, this.onExplore});
  @override
  State<LibraryCollectionScreen> createState() =>
      _LibraryCollectionScreenState();
}

class _LibraryCollectionScreenState extends State<LibraryCollectionScreen> {
  final _search = TextEditingController();
  String _filter = 'all';
  bool _working = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _detail(Manga manga) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MangaDetailScreen(
        manga: manga,
        heroTag: 'library_${manga.compositeId}',
      ),
    ),
  );

  void _resume(Manga manga, Chapter chapter) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReaderScreen(
        manga: manga,
        chapter: chapter,
        allChapters: HomeOverviewScreen.buildSortedChapterList(manga, chapter),
      ),
    ),
  );

  Future<void> _organize(String action, List<Manga> favorites) async {
    if (action == 'create') {
      await showCreateOrEditReadingListDialog(context);
      return;
    }
    if (_working || DeviceStateService.instance.isOffline) return;
    if (action == 'download') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Baixar biblioteca?'),
          content: Text(
            'Baixar os capítulos disponíveis de ${favorites.length} obras para ler sem internet?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Baixar'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() => _working = true);
    try {
      var count = 0;
      if (action == 'updates') {
        count = await FavoriteUpdatesService.checkAllFavorites(favorites);
      } else {
        for (final manga in favorites) {
          if (!mounted || DeviceStateService.instance.isOffline) break;
          final chapters = await MangaDexService.fetchChapters(manga);
          count += await DownloadManager.downloadManga(
            manga: manga,
            chapters: chapters,
          );
        }
      }
      if (mounted) {
        AppFeedback.message(
          context,
          action == 'updates'
              ? '$count novos capítulos encontrados.'
              : '$count capítulos salvos em Biblioteca → Baixados.',
        );
      }
    } catch (_) {
      if (mounted) {
        AppFeedback.message(
          context,
          'Não foi possível concluir. Verifique sua conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ProfilePaletteService.paletteNotifier,
      StorageService.favBox.listenable(),
      StorageService.settingsBox.listenable(),
      StorageService.historyBox.listenable(),
      StorageService.downloadsBox.listenable(),
      StorageService.nsfwModeNotifier,
      DeviceStateService.instance,
    ]),
    builder: (context, _) {
      final palette = ProfilePaletteService.paletteNotifier.value;
      final offline = DeviceStateService.instance.isOffline;
      final favorites = StorageService.getFavorites();
      final lists = StorageService.getReadingLists();
      final recent = StorageService.getContinueReadingList();
      final all = <String, Manga>{
        for (final manga in favorites) manga.compositeId: manga,
        for (final list in lists)
          for (final manga in list.mangas) manga.compositeId: manga,
        for (final entry in recent)
          (entry['manga'] as Manga).compositeId: entry['manga'] as Manga,
        for (final entry in StorageService.getAllDownloadedChapters())
          Manga.fromMap(
            Map<String, dynamic>.from(entry['manga'] as Map),
          ).compositeId: Manga.fromMap(
            Map<String, dynamic>.from(entry['manga'] as Map),
          ),
      };
      final progress = {
        for (final manga in all.values)
          manga.compositeId: LibraryProgress.forManga(manga),
      };
      bool matches(Manga manga) {
        final query = mangaSearchKey(_search.text.trim());
        if (query.isNotEmpty && !mangaSearchKey(manga.title).contains(query)) {
          return false;
        }
        final reading =
            progress[manga.compositeId] ?? LibraryProgress.forManga(manga);
        return switch (_filter) {
          'favorites' => favorites.any(
            (m) => m.compositeId == manga.compositeId,
          ),
          'reading' => reading.started && !reading.completed,
          'completed' => reading.completed,
          _ => true,
        };
      }

      final displayedFavorites = favorites.where(matches).toList();
      final displayed = all.values.where(matches).toList();
      final continuations = recent
          .where(
            (entry) =>
                matches(entry['manga'] as Manga) &&
                !(progress[(entry['manga'] as Manga).compositeId]?.completed ??
                    false),
          )
          .toList();
      return Scaffold(
        backgroundColor: YomiPalette.pitchBlack,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 112),
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_rounded, color: palette.primary, size: 26),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Biblioteca',
                    style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Suas leituras em um só lugar.',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar na sua biblioteca…',
                prefixIcon: Icon(Icons.search_rounded, color: palette.primary),
                filled: true,
                fillColor: palette.surfaceTint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: palette.primary.withValues(alpha: 0.25),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: palette.primary.withValues(alpha: 0.25),
                  ),
                ),
                suffixIcon: _working
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.primary,
                        ),
                      )
                    : PopupMenuButton<String>(
                        tooltip: 'Organizar biblioteca',
                        onSelected: (action) => _organize(
                          action,
                          action == 'download'
                              ? all.values.toList()
                              : favorites,
                        ),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'create',
                            child: Text('Criar lista de leitura'),
                          ),
                          PopupMenuItem(
                            value: 'updates',
                            enabled: !offline && favorites.isNotEmpty,
                            child: const Text('Verificar novidades'),
                          ),
                          PopupMenuItem(
                            value: 'download',
                            enabled: !offline && all.isNotEmpty,
                            child: const Text('Baixar biblioteca'),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in [
                    ('all', 'Todas', Icons.grid_view_rounded),
                    ('favorites', 'Favoritos', Icons.favorite_rounded),
                    ('reading', 'Lendo', Icons.auto_stories_rounded),
                    ('completed', 'Concluídas', Icons.check_circle_rounded),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(
                          item.$3,
                          size: 16,
                          color: _filter == item.$1
                              ? Colors.white
                              : palette.secondary,
                        ),
                        label: Text(item.$2),
                        labelStyle: TextStyle(
                          color: _filter == item.$1
                              ? Colors.white
                              : Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                        selected: _filter == item.$1,
                        showCheckmark: false,
                        selectedColor: palette.primary,
                        side: BorderSide(
                          color: palette.primary.withValues(alpha: 0.3),
                        ),
                        onSelected: (_) {
                          FocusScope.of(context).unfocus();
                          setState(() => _filter = item.$1);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (continuations.isNotEmpty) ...[
              _continueCard(continuations.first, palette, progress),
              const SizedBox(height: 26),
            ],
            if (displayed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  all.isEmpty
                      ? 'Sua biblioteca está pronta para novas histórias.'
                      : 'Nenhuma obra corresponde à pesquisa e ao filtro.',
                  style: const TextStyle(color: Colors.white60),
                  textAlign: TextAlign.center,
                ),
              ),
            if (displayedFavorites.isNotEmpty) ...[
              _heading('Favoritos', Icons.favorite_rounded, palette),
              const SizedBox(height: 12),
              _rail(displayedFavorites, palette, progress),
              const SizedBox(height: 24),
            ],
            if (_filter != 'favorites' &&
                displayed.any(
                  (m) =>
                      !favorites.any((fav) => fav.compositeId == m.compositeId),
                )) ...[
              _heading(
                'Suas obras',
                Icons.collections_bookmark_rounded,
                palette,
              ),
              const SizedBox(height: 12),
              _rail(
                displayed
                    .where(
                      (m) => !favorites.any(
                        (fav) => fav.compositeId == m.compositeId,
                      ),
                    )
                    .toList(),
                palette,
                progress,
              ),
              const SizedBox(height: 24),
            ],
            if (_filter == 'all')
              for (final list in lists) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        list.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opções da lista ${list.name}',
                      onSelected: (action) async {
                        if (action == 'edit') {
                          await showCreateOrEditReadingListDialog(
                            context,
                            existing: list,
                          );
                        } else {
                          final remove = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Excluir lista?'),
                              content: Text(
                                'Excluir "${list.name}"? As obras e os downloads serão mantidos.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Excluir'),
                                ),
                              ],
                            ),
                          );
                          if (remove == true) {
                            await StorageService.deleteReadingList(list.id);
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Renomear lista'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Excluir lista'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (list.mangas.where(matches).isEmpty)
                  const Text(
                    'Nenhuma obra nesta lista corresponde à pesquisa.',
                    style: TextStyle(color: Colors.white54),
                  )
                else
                  _rail(list.mangas.where(matches).toList(), palette, progress),
                const SizedBox(height: 24),
              ],
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: offline
                    ? () => AppFeedback.message(
                        context,
                        'Reconecte para descobrir e adicionar novas obras.',
                      )
                    : widget.onExplore,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      colors: [
                        palette.primary.withValues(alpha: 0.18),
                        palette.surfaceTint,
                      ],
                    ),
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.library_add_rounded,
                        color: palette.secondary,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Adicione novas obras',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              offline
                                  ? 'Reconecte para explorar novas histórias.'
                                  : 'Descubra histórias incríveis para sua coleção.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _heading(
    String title,
    IconData icon,
    ProfileAdaptivePalette palette,
  ) => Row(
    children: [
      Icon(icon, color: palette.secondary, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 110),
        child: TextButton(
          onPressed: () => setState(
            () => _filter = title == 'Favoritos' ? 'favorites' : 'all',
          ),
          child: Text(
            'Ver todos',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.secondary),
          ),
        ),
      ),
    ],
  );

  Widget _rail(
    List<Manga> items,
    ProfileAdaptivePalette palette,
    Map<String, LibraryProgress> progress,
  ) {
    final width = ((MediaQuery.sizeOf(context).width - 66) / 4).clamp(
      100.0,
      156.0,
    );
    return SizedBox(
      height:
          width * 1.5 + MediaQuery.textScalerOf(context).scale(13) * 4.8 + 20,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final manga = items[index];
          final reading =
              progress[manga.compositeId] ?? LibraryProgress.forManga(manga);
          return SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => _detail(manga),
                  borderRadius: BorderRadius.circular(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: YomiCoverImage(manga: manga, width: width),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(13) * 2.6,
                  child: Text(
                    manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: reading.fraction ?? 0,
                    minHeight: 4,
                    color: palette.primary,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reading.completed ? '100% concluído' : reading.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _continueCard(
    Map<String, dynamic> entry,
    ProfileAdaptivePalette palette,
    Map<String, LibraryProgress> progress,
  ) {
    final manga = entry['manga'] as Manga;
    final chapter = entry['chapter'] as Chapter;
    final reading =
        progress[manga.compositeId] ?? LibraryProgress.forManga(manga);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _resume(manga, chapter),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.primary.withValues(alpha: 0.4)),
            gradient: LinearGradient(
              colors: [
                palette.surfaceTint,
                palette.primary.withValues(alpha: 0.25),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTINUE LENDO',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.secondary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        manga.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value: reading.fraction ?? 0,
                        minHeight: 4,
                        color: palette.primary,
                        backgroundColor: Colors.white10,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cap. ${chapter.chapterNumber} · ${reading.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: palette.secondary,
                      ),
                    ],
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(22),
                ),
                child: YomiCoverImage(
                  manga: manga,
                  width: MediaQuery.sizeOf(context).width < 340 ? 100 : 132,
                  height: 238,
                  highRes: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
