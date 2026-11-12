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
          clipBehavior: Clip.none,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -24,
                  right: -10,
                  child: IgnorePointer(
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            palette.primary.withValues(alpha: 0.28),
                            palette.primary.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          color: palette.primary,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Biblioteca',
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Suas leituras em um só lugar.',
                      style: TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                  ],
                ),
              ],
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
              clipBehavior: Clip.none,
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
                          color: _filter == item.$1
                              ? palette.primary
                              : palette.primary.withValues(alpha: 0.3),
                        ),
                        onSelected: (selected) {
                          FocusScope.of(context).unfocus();
                          setState(() => _filter = selected ? item.$1 : 'all');
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (continuations.isNotEmpty) ...[
              _continueCard(continuations.first, palette, progress, favorites),
              const SizedBox(height: 26),
            ],
            if (displayed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  all.isEmpty
                      ? 'Sua biblioteca está pronta para novas histórias.'
                      : switch (_filter) {
                          'favorites' => 'Nenhum favorito encontrado.',
                          'reading' => 'Nenhuma obra em leitura no momento.',
                          'completed' => 'Nenhuma obra concluída ainda.',
                          _ => 'Nenhuma obra corresponde à pesquisa e ao filtro.',
                        },
                  style: const TextStyle(color: Colors.white60),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_filter == 'all') ...[
              if (displayedFavorites.isNotEmpty) ...[
                _heading(
                  'Favoritos',
                  Icons.favorite_rounded,
                  palette,
                  onSeeAll: () => setState(() => _filter = 'favorites'),
                ),
                const SizedBox(height: 12),
                _rail(displayedFavorites, palette, progress, favorites),
                const SizedBox(height: 24),
              ],
              if (displayed.any(
                (m) => !favorites.any((fav) => fav.compositeId == m.compositeId),
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
                  favorites,
                ),
                const SizedBox(height: 24),
              ],
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
                const SizedBox(height: 12),
                if (list.mangas.where(matches).isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Nenhuma obra nesta lista corresponde à pesquisa.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                else ...[
                  _rail(
                    list.mangas.where(matches).toList(),
                    palette,
                    progress,
                    favorites,
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ] else if (_filter == 'favorites') ...[
              _heading('Favoritos', Icons.favorite_rounded, palette),
              const SizedBox(height: 12),
              _rail(displayedFavorites, palette, progress, favorites),
              const SizedBox(height: 24),
            ] else if (_filter == 'reading') ...[
              _heading('Lendo', Icons.auto_stories_rounded, palette),
              const SizedBox(height: 12),
              _rail(displayed, palette, progress, favorites),
              const SizedBox(height: 24),
            ] else if (_filter == 'completed') ...[
              _heading('Concluídas', Icons.check_circle_rounded, palette),
              const SizedBox(height: 12),
              _rail(displayed, palette, progress, favorites),
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
                  padding: const EdgeInsets.all(18),
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
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: palette.primary.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Icon(
                          Icons.layers_rounded,
                          color: palette.secondary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Adicione novas obras',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
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
    ProfileAdaptivePalette palette, {
    VoidCallback? onSeeAll,
  }) => Row(
    children: [
      Icon(icon, color: palette.secondary, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
      ),
      if (onSeeAll != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: Text(
              'Ver todos >',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _rail(
    List<Manga> items,
    ProfileAdaptivePalette palette,
    Map<String, LibraryProgress> progress,
    List<Manga> favorites,
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
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final manga = items[index];
          final reading =
              progress[manga.compositeId] ?? LibraryProgress.forManga(manga);
          final isFav = favorites.any((m) => m.compositeId == manga.compositeId);
          return SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => _detail(manga),
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: YomiCoverImage(manga: manga, width: width),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => StorageService.toggleFavorite(manga),
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.65),
                              ),
                              child: Icon(
                                isFav
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 13,
                                color: isFav ? palette.primary : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                    minHeight: 3.5,
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
    List<Manga> favorites,
  ) {
    final manga = entry['manga'] as Manga;
    final chapter = entry['chapter'] as Chapter;
    final reading =
        progress[manga.compositeId] ?? LibraryProgress.forManga(manga);
    final isFav = favorites.any((m) => m.compositeId == manga.compositeId);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.none,
      child: InkWell(
        onTap: () => _resume(manga, chapter),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.primary.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.surfaceTint,
                palette.primary.withValues(alpha: 0.22),
              ],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CONTINUE LENDO',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.secondary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      manga.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: reading.fraction ?? 0,
                        minHeight: 4,
                        color: palette.primary,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Capítulo ${chapter.chapterNumber} • ${reading.completed ? '100% concluído' : reading.label}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white60,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: FloatingContinueCover(
                  manga: manga,
                  width: 96,
                  height: 140,
                  palette: palette,
                  isFavorite: isFav,
                  onFavoriteToggle: () => StorageService.toggleFavorite(manga),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.primary,
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget reutilizável que anima a capa flutuante com rotação e translação contínuas.
class FloatingContinueCover extends StatefulWidget {
  final Manga manga;
  final double width;
  final double height;
  final ProfileAdaptivePalette palette;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const FloatingContinueCover({
    super.key,
    required this.manga,
    required this.width,
    required this.height,
    required this.palette,
    required this.isFavorite,
    this.onFavoriteToggle,
  });

  @override
  State<FloatingContinueCover> createState() => _FloatingContinueCoverState();
}

class _FloatingContinueCoverState extends State<FloatingContinueCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    final inTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!inTest) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0.5;
    }
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // Oscilação em Y de cerca de 6 pixels (-3.0 a +3.0)
        final yOffset = (_animation.value - 0.5) * 6.0;
        // Inclinação inicial ~ -5° (-0.087 rad) oscilando em torno de ±2.5° (±0.0436 rad)
        final angle = -0.087 + (_animation.value - 0.5) * 0.087;

        return Transform.translate(
          offset: Offset(0, yOffset),
          child: Transform.rotate(
            angle: angle,
            child: child,
          ),
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 18,
              offset: const Offset(0, 10),
              spreadRadius: 1,
            ),
            BoxShadow(
              color: widget.palette.primary.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: YomiCoverImage(
                  manga: widget.manga,
                  width: widget.width,
                  height: widget.height,
                  highRes: true,
                ),
              ),
            ),
            Positioned(
              top: 7,
              right: 7,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onFavoriteToggle,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.60),
                      border: Border.all(
                        color: widget.isFavorite
                            ? widget.palette.primary.withValues(alpha: 0.8)
                            : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        widget.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 15,
                        color: widget.isFavorite
                            ? widget.palette.primary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
