import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/favorite_updates_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/yomi_blobatar_studio.dart';
import '../widgets/yomi_brand_widgets.dart';
import 'favorite_updates_screen.dart';
import 'home_overview_screen.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

class ProfileDashboardScreen extends StatefulWidget {
  final VoidCallback? onGoToExplore;
  final VoidCallback? onGoToSettings;

  const ProfileDashboardScreen({
    super.key,
    required this.onGoToExplore,
    required this.onGoToSettings,
  });

  @override
  State<ProfileDashboardScreen> createState() => _ProfileDashboardScreenState();
}

class _ProfileDashboardScreenState extends State<ProfileDashboardScreen> {
  int _selectedGenreIdx = 0;

  @override
  void initState() {
    super.initState();
    ProfilePaletteService.bindToProfileNotifier(StorageService.profileNotifier);
  }

  void _openChapterFromProfile(
    BuildContext context,
    Manga manga,
    Chapter chapter,
  ) {
    final chapters = HomeOverviewScreen.buildSortedChapterList(manga, chapter);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReaderScreen(manga: manga, chapter: chapter, allChapters: chapters),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        StorageService.profileNotifier,
        StorageService.nsfwModeNotifier,
        ProfilePaletteService.paletteNotifier,
      ]),
      builder: (context, _) {
        final profile = StorageService.profileNotifier.value;
        final palette = ProfilePaletteService.paletteNotifier.value;
        final accent = palette.primary;
        final secondary = palette.secondary;
        final hasCustomPhoto =
            !profile.useBlobatarAsAvatar &&
            (profile.avatarImagePath?.trim().isNotEmpty ?? false);

        return Scaffold(
          backgroundColor: YomiPalette.pitchBlack,
          body: ValueListenableBuilder(
            valueListenable: StorageService.historyBox.listenable(
              keys: ['recent_reading_list'],
            ),
            builder: (context, Box historyBox, _) {
              return ValueListenableBuilder(
                valueListenable: StorageService.favBox.listenable(),
                builder: (context, Box favBox, _) {
                  return ValueListenableBuilder(
                    valueListenable: StorageService.settingsBox.listenable(),
                    builder: (context, Box settingsBox, _) {
                      final continueList =
                          StorageService.getContinueReadingList();
                      final favorites = StorageService.getFavorites();
                      final readingLists = StorageService.getReadingLists();
                      final pendingUpdatesCount =
                          FavoriteUpdatesService.allPending(favorites).length;
                      final genreTags = profile.genreTags;

                      return ListView(
                        padding: const EdgeInsets.only(bottom: 116),
                        children: [
                          // 1. BANNER ADAPTATIVO + TOP BAR + BOTÃO DIRETO DE BANNER + AVATAR CENTRAL SOBREPOSTO
                          SizedBox(
                            height: 294,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Banner Art / Custom Image / Preset
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: 232,
                                  child: GestureDetector(
                                    onTap: () =>
                                        showYomiProfileAndBlobatarEditor(
                                          context,
                                          profile,
                                          initialTab: 1,
                                        ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        YomiBannerBackdrop(
                                          bannerPath: profile.bannerImagePath,
                                          palette: palette,
                                        ),
                                        DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.black.withValues(
                                                  alpha: 0.40,
                                                ),
                                                Colors.transparent,
                                                YomiPalette.pitchBlack
                                                    .withValues(alpha: 0.90),
                                                YomiPalette.pitchBlack,
                                              ],
                                              stops: const [
                                                0.0,
                                                0.35,
                                                0.84,
                                                1.0,
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Direct 1-tap Banner Change Pill Button
                                        Positioned(
                                          left: 14,
                                          bottom: 36,
                                          child: Material(
                                            color: Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              side: BorderSide(
                                                color: accent.withValues(
                                                  alpha: 0.55,
                                                ),
                                              ),
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              onTap: () =>
                                                  showYomiProfileAndBlobatarEditor(
                                                    context,
                                                    profile,
                                                    initialTab: 1,
                                                  ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.wallpaper_rounded,
                                                      size: 14,
                                                      color: palette.soft,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    const Text(
                                                      'Banner',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Transparent Top Bar (YOMI logo + Bell + Gear + More)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: SafeArea(
                                    bottom: false,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          const YomiEnsoLogo(),
                                          const Spacer(),
                                          IconButton(
                                            tooltip:
                                                'Notificações e capítulos de favoritos',
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const FavoriteUpdatesScreen(),
                                              ),
                                            ),
                                            icon: Badge(
                                              isLabelVisible:
                                                  pendingUpdatesCount > 0,
                                              backgroundColor: accent,
                                              label: Text(
                                                pendingUpdatesCount > 99
                                                    ? '99+'
                                                    : '$pendingUpdatesCount',
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              child: Icon(
                                                pendingUpdatesCount > 0
                                                    ? Icons
                                                          .notifications_active_rounded
                                                    : Icons
                                                          .notifications_none_rounded,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Ajustes & Backup',
                                            onPressed: widget.onGoToSettings,
                                            icon: const Icon(
                                              Icons.settings_outlined,
                                              color: Colors.white,
                                              size: 23,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Personalizar Perfil e Mascote',
                                            onPressed: () =>
                                                showYomiProfileAndBlobatarEditor(
                                                  context,
                                                  profile,
                                                  initialTab: 0,
                                                ),
                                            icon: const Icon(
                                              Icons.more_vert_rounded,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Overlapping Centered Avatar + Edit Button + Companion Blobatar
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: SizedBox(
                                      width: 126,
                                      height: 120,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: accent.withValues(
                                                    alpha: 0.35,
                                                  ),
                                                  blurRadius: 28,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                            child: YomiProfileAvatarView(
                                              profile: profile,
                                              size: 114,
                                              borderColor: Colors.white
                                                  .withValues(alpha: 0.75),
                                              adaptiveHue: palette.hue,
                                              onTap: () =>
                                                  showYomiProfileAndBlobatarEditor(
                                                    context,
                                                    profile,
                                                    initialTab: hasCustomPhoto
                                                        ? 1
                                                        : 0,
                                                  ),
                                            ),
                                          ),
                                          if (hasCustomPhoto)
                                            Positioned(
                                              left: -4,
                                              bottom: 2,
                                              child: Tooltip(
                                                message:
                                                    'Personalizar Mascote ${profile.effectiveBlobatarName}',
                                                child: GestureDetector(
                                                  onTap: () =>
                                                      showYomiProfileAndBlobatarEditor(
                                                        context,
                                                        profile,
                                                        initialTab: 0,
                                                      ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(2),
                                                    decoration: BoxDecoration(
                                                      color: YomiPalette
                                                          .pitchBlack,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: accent,
                                                        width: 1.5,
                                                      ),
                                                    ),
                                                    child: YomiProfileBlobatar(
                                                      profile: profile,
                                                      size: 32,
                                                      adaptiveHue: palette.hue,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          Positioned(
                                            right: 4,
                                            bottom: 2,
                                            child: GestureDetector(
                                              onTap: () =>
                                                  showYomiProfileAndBlobatarEditor(
                                                    context,
                                                    profile,
                                                    initialTab: 1,
                                                  ),
                                              child: Container(
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  color: accent,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color:
                                                        YomiPalette.pitchBlack,
                                                    width: 2.2,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: accent.withValues(
                                                        alpha: 0.5,
                                                      ),
                                                      blurRadius: 10,
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.edit_rounded,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // 2. NOME & BIO CENTRALIZADOS (SEM ESTATÍSTICAS)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                Text(
                                  profile.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  profile.bio.isEmpty
                                      ? 'Mais histórias, menos realidade.'
                                      : profile.bio,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 3. BOTÃO OUTLINED "Editar perfil"
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      showYomiProfileAndBlobatarEditor(
                                        context,
                                        profile,
                                        initialTab: 1,
                                      ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: accent.withValues(
                                      alpha: 0.05,
                                    ),
                                    side: BorderSide(
                                      color: accent.withValues(alpha: 0.65),
                                      width: 1.2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(26),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.person_outline_rounded,
                                    size: 19,
                                  ),
                                  label: const Text(
                                    'Editar perfil',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // 4. CARD INTERATIVO DO MASCOTE BLOBATAR COM NOME PERSONALIZADO
                                Material(
                                  color: palette.cardSurface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    side: BorderSide(
                                      color: accent.withValues(alpha: 0.28),
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        showYomiProfileAndBlobatarEditor(
                                          context,
                                          profile,
                                          initialTab: 0,
                                        ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          YomiProfileBlobatar(
                                            profile: profile,
                                            size: 46,
                                            adaptiveHue: palette.hue,
                                            interactiveCycleOnTap: true,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Mascote ${profile.effectiveBlobatarName}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                const Text(
                                                  'Personalize nome, expressão, silhueta, foto e banner.',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: accent,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 22),

                                // 5. GÊNEROS FAVORITOS
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Gêneros favoritos',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () =>
                                          showYomiProfileAndBlobatarEditor(
                                            context,
                                            profile,
                                            initialTab: 2,
                                          ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'Editar',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: secondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: List.generate(genreTags.length, (
                                      i,
                                    ) {
                                      final isSelected =
                                          i ==
                                          (_selectedGenreIdx %
                                              genreTags.length);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        child: GestureDetector(
                                          onTap: () => setState(
                                            () => _selectedGenreIdx = i,
                                          ),
                                          onLongPress: () =>
                                              showYomiProfileAndBlobatarEditor(
                                                context,
                                                profile,
                                                initialTab: 2,
                                              ),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? accent.withValues(
                                                      alpha: 0.22,
                                                    )
                                                  : const Color(0xFF121218),
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              border: Border.all(
                                                color: isSelected
                                                    ? accent
                                                    : Colors.white10,
                                                width: isSelected ? 1.3 : 1.0,
                                              ),
                                            ),
                                            child: Text(
                                              genreTags[i],
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSelected
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),

                                const SizedBox(height: 26),

                                // 6. SEÇÃO 1: OBRAS LIDAS RECENTEMENTE (EM ROLL)
                                _buildRecentWorksRoll(
                                  context,
                                  continueList,
                                  palette,
                                ),

                                const SizedBox(height: 26),

                                // 7. SEÇÃO 2: LISTAS DE LEITURA COM OS TÍTULOS EM ROLL
                                _buildReadingListsRollSection(
                                  context,
                                  readingLists,
                                  palette,
                                ),

                                const SizedBox(height: 26),

                                // 8. SEÇÃO 3: OBRAS FAVORITAS (EM ROLL)
                                _buildFavoriteWorksRollSection(
                                  context,
                                  favorites,
                                  palette,
                                ),
                              ],
                            ),
                          ),
                        ],
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

  Widget _buildRecentWorksRoll(
    BuildContext context,
    List<Map<String, dynamic>> continueList,
    ProfileAdaptivePalette palette,
  ) {
    final accent = palette.primary;
    final secondary = palette.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: accent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Obras lidas recentemente',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: widget.onGoToExplore,
              child: Text(
                'Explorar →',
                style: TextStyle(
                  color: secondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (continueList.isEmpty)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onGoToExplore,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.cardSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.menu_book_rounded, color: accent),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nenhuma obra lida recentemente',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'As obras e capítulos que você abrir aparecerão automaticamente aqui.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 202,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: continueList.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final item = continueList[idx];
                final Manga manga = item['manga'];
                final Chapter chapter = item['chapter'];
                final savedPage = StorageService.getSavedPageIndex(chapter.id);

                return GestureDetector(
                  onTap: () => _openChapterFromProfile(context, manga, chapter),
                  onLongPress: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MangaDetailScreen(
                        manga: manga,
                        heroTag: 'profile_recent_${manga.compositeId}',
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: 118,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                YomiCoverImage(manga: manga, highRes: false),
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.78,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Text(
                                      'Cap. ${chapter.chapterNumber} · P.${savedPage + 1}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: palette.soft,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          manga.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildReadingListsRollSection(
    BuildContext context,
    List<UserReadingList> readingLists,
    ProfileAdaptivePalette palette,
  ) {
    final accent = palette.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    Icons.collections_bookmark_rounded,
                    color: accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Listas de leitura',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.2),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => showCreateOrEditReadingListDialog(context),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text(
                'Nova lista',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (readingLists.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: palette.cardSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crie suas próprias listas de leitura personalizadas',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Organize seus mangás, manhwas e HQs em coleções com títulos em roll.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: Icon(
                        Icons.add_circle_outline_rounded,
                        size: 16,
                        color: accent,
                      ),
                      label: const Text('Criar Lista Personalizada'),
                      onPressed: () =>
                          showCreateOrEditReadingListDialog(context),
                    ),
                    ActionChip(
                      label: const Text('+ Para Ler Depois'),
                      onPressed: () => StorageService.createReadingList(
                        'Para Ler Depois',
                        description: 'Obras salvas para começar em breve',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          for (final list in readingLists) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.cardSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              list.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (list.description.isNotEmpty)
                              Text(
                                list.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white60,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Editar lista',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => showCreateOrEditReadingListDialog(
                          context,
                          existing: list,
                        ),
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: palette.soft,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Excluir lista',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            StorageService.deleteReadingList(list.id),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (list.mangas.isEmpty)
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Nenhuma obra adicionada a esta lista ainda.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => showCreateOrEditReadingListDialog(
                            context,
                            existing: list,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Adicionar'),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      height: 186,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: list.mangas.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, idx) => SizedBox(
                          width: 108,
                          child: MangaGridCard(
                            manga: list.mangas[idx],
                            heroPrefix: 'profile_list_${list.id}',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  Widget _buildFavoriteWorksRollSection(
    BuildContext context,
    List<Manga> favorites,
    ProfileAdaptivePalette palette,
  ) {
    final accent = palette.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.favorite_rounded, color: accent, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Obras favoritas',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (favorites.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.cardSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Icon(Icons.favorite_border_rounded, color: accent, size: 32),
                const SizedBox(height: 10),
                const Text(
                  'Sua vitrine de Obras Favoritas está vazia',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Toque no ícone de coração em qualquer Mangá, Manhwa ou Webtoon para destacá-lo no seu perfil.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.22),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: widget.onGoToExplore,
                  icon: const Icon(Icons.explore_rounded, size: 18),
                  label: const Text('Explorar Catálogo'),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: favorites.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, idx) => SizedBox(
                width: 112,
                child: MangaGridCard(
                  manga: favorites[idx],
                  heroPrefix: 'profile_fav',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

