import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';
import '../services/download_manager.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Manga> _mangas = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _loadMangas(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        !_isLoading &&
        !_isLoadingMore) {
      _loadMoreMangas();
    }
  }

  Future<void> _loadMangas({String? query, bool reset = true}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      if (reset) _offset = 0;
    });
    try {
      final result = await MangaDexService.fetchMangas(
        query: query,
        offset: _offset,
      );
      if (mounted) {
        setState(() {
          _mangas = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreMangas() async {
    setState(() => _isLoadingMore = true);
    try {
      final nextOffset = _offset + 24;
      final result = await MangaDexService.fetchMangas(
        query: _searchController.text,
        offset: nextOffset,
      );
      if (mounted && result.isNotEmpty) {
        setState(() {
          _offset = nextOffset;
          _mangas.addAll(result);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_stories_rounded, color: Color(0xFF8B5CF6)),
            SizedBox(width: 10),
            Text('KuroReader'),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => _loadMangas(query: value, reset: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText:
                    'Buscar mangá, manhwa (ex: Solo Leveling, Berserk)...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8B5CF6)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          _loadMangas(reset: true);
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF14141F),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 48,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sem conexão. Acesse a aba Offline ou sua Biblioteca.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () =>
                          _loadMangas(query: _searchController.text),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadMangas(query: _searchController.text),
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.64,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => MangaGridCard(
                          manga: _mangas[index],
                          heroPrefix: 'explore',
                        ),
                        childCount: _mangas.length,
                      ),
                    ),
                  ),
                  if (_isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bookmarks_rounded, color: Color(0xFFC084FC)),
            SizedBox(width: 10),
            Text('Minha Biblioteca'),
          ],
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: StorageService.favBox.listenable(),
        builder: (context, Box box, _) {
          final favorites = StorageService.getFavorites();

          if (favorites.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      size: 64,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Sua biblioteca está vazia',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Toque no coração em qualquer mangá para salvá-lo aqui.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.64,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            itemCount: favorites.length,
            itemBuilder: (context, index) =>
                MangaGridCard(manga: favorites[index], heroPrefix: 'lib'),
          );
        },
      ),
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.download_for_offline_rounded, color: Color(0xFF8B5CF6)),
            SizedBox(width: 10),
            Text('Capítulos Offline'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Apagar todos os downloads',
            icon: const Icon(
              Icons.delete_sweep_outlined,
              color: Colors.redAccent,
            ),
            onPressed: () async {
              await DownloadManager.deleteAllDownloads();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Armazenamento offline limpo!')),
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: StorageService.downloadsBox.listenable(),
        builder: (context, Box box, _) {
          final items = StorageService.getAllDownloadedChapters();

          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 64,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Nenhum capítulo salvo no aparelho',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white10),
            itemBuilder: (context, index) {
              final entry = items[index];
              final manga = Manga.fromMap(
                Map<String, dynamic>.from(entry['manga']),
              );
              final chapter = Chapter.fromMap(
                Map<String, dynamic>.from(entry['chapter']),
              );
              final paths = List<String>.from(entry['paths'] ?? []);

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: manga.getCoverUrl(),
                    httpHeaders: MangaDexService.headers,
                    width: 48,
                    height: 68,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 48,
                      height: 68,
                      color: const Color(0xFF14141F),
                      child: const Icon(Icons.book, color: Colors.white38),
                    ),
                  ),
                ),
                title: Text(
                  manga.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Cap. ${chapter.chapterNumber} (${chapter.language}) • ${paths.length} págs',
                  style: const TextStyle(
                    color: Color(0xFFC084FC),
                    fontSize: 12.5,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  onPressed: () => DownloadManager.deleteChapter(chapter.id),
                ),
                onTap: () {
                  StorageService.markChapterAsRead(
                    manga.id,
                    chapter,
                    read: true,
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReaderScreen(
                        manga: manga,
                        chapter: chapter,
                        allChapters: [chapter],
                      ),
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

class MangaGridCard extends StatelessWidget {
  final Manga manga;
  final String heroPrefix;

  const MangaGridCard({
    super.key,
    required this.manga,
    required this.heroPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final heroTag = '${heroPrefix}_cover_${manga.id}';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MangaDetailScreen(manga: manga, heroTag: heroTag),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: manga.getCoverUrl(highRes: false),
                      httpHeaders: MangaDexService.headers,
                      memCacheWidth: 350,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: const Color(0xFF14141F),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF14141F),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: StorageService.favBox.listenable(
                        keys: [manga.id],
                      ),
                      builder: (context, Box box, _) {
                        if (!StorageService.isFavorite(manga.id)) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              size: 14,
                              color: Color(0xFFC084FC),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
