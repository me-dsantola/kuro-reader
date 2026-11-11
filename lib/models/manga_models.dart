import 'catalog_sort.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Converte qualquer URL de imagem para passar pelo CDN/Proxy CORS (wsrv.nl) quando estiver a rodar no Chrome (Web).
/// No Android e no Windows Desktop (!kIsWeb), usa a URL direta nativa.
/// Gera a lista ordenada de URLs candidatas (CDN Primária + Espelhos Anti-CORS / Anti-Hotlink)
/// Funciona no Windows Desktop (sem depender do sqflite do CachedNetworkImage), no Chrome Web e no Android!
List<String> yomiCandidateImageUrls(String rawUrl) {
  String clean = rawUrl.trim();
  if (clean.startsWith('https://wsrv.nl/?url=')) {
    clean = Uri.decodeComponent(
      clean.replaceFirst('https://wsrv.nl/?url=', ''),
    );
  }
  if (clean.isEmpty || clean.contains('via.placeholder.com')) {
    return const [];
  }
  final withoutScheme = clean.replaceFirst(RegExp(r'^https?://'), '');
  final wpMirror = 'https://i0.wp.com/$withoutScheme';
  final wsrvMirror = 'https://wsrv.nl/?url=${Uri.encodeComponent(clean)}';
  final codetabsMirror =
      'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(clean)}';

  if (kIsWeb) {
    // No Chrome (Web), uploads.mangadex.org bloqueia wsrv.nl com 403, mas aceita i0.wp.com e codetabs!
    if (clean.contains('mangadex.org')) {
      return [wpMirror, codetabsMirror, wsrvMirror, clean];
    }
    return [wsrvMirror, wpMirror, codetabsMirror, clean];
  } else {
    // No Windows Desktop e Android, tenta a URL direta nativa primeiro e usa os espelhos se a operadora bloquear
    return [clean, wpMirror, wsrvMirror];
  }
}

String yomiSafeImageUrl(String rawUrl) {
  final candidates = yomiCandidateImageUrls(rawUrl);
  if (candidates.isEmpty) return '';
  return candidates.first;
}

enum MangaSourceType {
  mangadex('MDX', 'MangaDex (leitura)', Color(0xFFE11D48)),
  anilist('ANI', 'AniList (metadados)', Color(0xFF02A9FF)),
  jikanMal('MAL', 'MAL/Jikan (metadados)', Color(0xFF2E51A2)),
  // Legacy enum names are retained to avoid breaking old saved favorites.
  comick('CAT', 'Kitsu / MangaDex (catálogo)', Color(0xFF10B981)),
  comicsHq('HQs', 'HQs (pesquisa MangaDex)', Color(0xFFF59E0B)),
  adultSource('18+', 'MangaDex (filtro 18+)', Color(0xFFF472B6));

  final String badge;
  final String label;
  final Color accentColor;
  const MangaSourceType(this.badge, this.label, this.accentColor);

  static MangaSourceType fromName(String? name) {
    return MangaSourceType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => MangaSourceType.mangadex,
    );
  }
}

enum NsfwDisplayMode {
  hidden(
    'Seguro (Ocultar 18+)',
    'Oculta conteúdo adulto e obras sem classificação confirmada',
  ),
  blurred(
    'Sakura Blur (Borrar Capas)',
    'Exibe resultados 18+ com capa desfocada até segurar',
  ),
  visible('Liberado (Exibir Tudo)', 'Exibe capas e obras 18+ sem restrições');

  final String label;
  final String subtitle;
  const NsfwDisplayMode(this.label, this.subtitle);

  bool get allowNsfwFetch => this != NsfwDisplayMode.hidden;

  static NsfwDisplayMode fromName(String? name) {
    return NsfwDisplayMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => NsfwDisplayMode.hidden,
    );
  }
}

enum TagCategoryGroup {
  formatAndOrigin('Formato & Origem (Mangá, Manhwa, HQs)'),
  demographics('Demografia & Público'),
  genres('Gêneros Principais'),
  themesAndTropes('Temas, Universos & Subgêneros'),
  nsfwVault('Categorias 18+ (Visível apenas se ativado)');

  final String title;
  const TagCategoryGroup(this.title);
}

enum CanonicalTag {
  // --- FORMATO & ORIGEM ---
  mangaJp(
    label: 'Mangá (Japão)',
    group: TagCategoryGroup.formatAndOrigin,
    mangadexLang: 'ja',
    comickQuery: 'manga',
  ),
  manhwaKr(
    label: 'Manhwa / Webtoon (Coreia)',
    group: TagCategoryGroup.formatAndOrigin,
    mangadexUuid: 'e197df38-d0e7-43b5-9b09-2842d0c326dd',
    mangadexLang: 'ko',
    comickQuery: 'manhwa',
  ),
  manhuaCn(
    label: 'Manhua (China)',
    group: TagCategoryGroup.formatAndOrigin,
    mangadexLang: 'zh',
    comickQuery: 'manhua',
  ),
  marvelComics(
    label: 'Marvel Comics (HQ)',
    group: TagCategoryGroup.formatAndOrigin,
    comicTopic: 'Spider-Man',
    comickQuery: 'Spider-Man',
  ),
  dcComics(
    label: 'DC Comics (HQ)',
    group: TagCategoryGroup.formatAndOrigin,
    comicTopic: 'Batman',
    comickQuery: 'Batman',
  ),
  westernIndieHq(
    label: 'HQs / Star Wars / Cyberpunk',
    group: TagCategoryGroup.formatAndOrigin,
    comicTopic: 'Star Wars',
    comickQuery: 'Star Wars',
  ),
  fullColor(
    label: 'Colorido (Full Color)',
    group: TagCategoryGroup.formatAndOrigin,
    mangadexUuid: 'f5ba408b-0e7a-484d-8d49-4e9125ac96de',
    adultSlug: 'full color',
    comickQuery: 'full color',
  ),
  oneShot(
    label: 'One-Shot (Volume Único)',
    group: TagCategoryGroup.formatAndOrigin,
    mangadexUuid: '0234a31e-a729-4e28-9d6a-3f87c4966b9e',
  ),

  // --- DEMOGRAFIA ---
  shounen(
    label: 'Shounen',
    group: TagCategoryGroup.demographics,
    mangadexDemographic: 'shounen',
    comickQuery: 'shounen',
  ),
  seinen(
    label: 'Seinen',
    group: TagCategoryGroup.demographics,
    mangadexDemographic: 'seinen',
    comickQuery: 'seinen',
  ),
  shoujo(
    label: 'Shoujo',
    group: TagCategoryGroup.demographics,
    mangadexDemographic: 'shoujo',
    comickQuery: 'shoujo',
  ),
  josei(
    label: 'Josei',
    group: TagCategoryGroup.demographics,
    mangadexDemographic: 'josei',
    comickQuery: 'josei',
  ),

  // --- GÊNEROS PRINCIPAIS ---
  action(
    label: 'Ação',
    group: TagCategoryGroup.genres,
    mangadexUuid: '391b0423-d847-456f-aff0-8b0cfc03066b',
    adultSlug: 'action',
    comicTopic: 'Action',
  ),
  adventure(
    label: 'Aventura',
    group: TagCategoryGroup.genres,
    mangadexUuid: '87cc87cd-a395-47af-b27a-93258283bbc6',
    comicTopic: 'Adventure',
  ),
  fantasy(
    label: 'Fantasia',
    group: TagCategoryGroup.genres,
    mangadexUuid: 'cdc58593-87dd-415e-bbc0-2ec27bf404cc',
    adultSlug: 'fantasy',
    comicTopic: 'Fantasy',
  ),
  sciFi(
    label: 'Ficção Científica (Sci-Fi)',
    group: TagCategoryGroup.genres,
    mangadexUuid: '256c8bd9-4904-4360-bf4f-508a76d67183',
    comicTopic: 'Sci-Fi',
  ),
  romance(
    label: 'Romance',
    group: TagCategoryGroup.genres,
    mangadexUuid: '423e2eae-a7a2-4a8b-ac03-a8351462d71d',
    adultSlug: 'romance',
    comicTopic: 'Romance',
  ),
  comedy(
    label: 'Comédia',
    group: TagCategoryGroup.genres,
    mangadexUuid: '4d32cc48-9f00-4cca-9b5a-a839f0764984',
    adultSlug: 'comedy',
    comicTopic: 'Comedy',
  ),
  drama(
    label: 'Drama',
    group: TagCategoryGroup.genres,
    mangadexUuid: 'b9af3a63-f058-46de-a9a0-e0c13906197a',
    adultSlug: 'drama',
    comicTopic: 'Drama',
  ),
  horror(
    label: 'Terror / Horror',
    group: TagCategoryGroup.genres,
    mangadexUuid: 'cdad7e68-1419-41dd-bdce-27753074a640',
    comicTopic: 'Horror',
  ),
  mystery(
    label: 'Mistério & Investigação',
    group: TagCategoryGroup.genres,
    mangadexUuid: 'ee968100-4191-4968-93d3-f82d72be7e46',
    comicTopic: 'Mystery',
  ),
  psychological(
    label: 'Psicológico',
    group: TagCategoryGroup.genres,
    mangadexUuid: '3b60b75c-a2d7-4860-ab56-05f391bb889c',
    comicTopic: 'Psychological',
  ),
  sliceOfLife(
    label: 'Slice of Life (Cotidiano)',
    group: TagCategoryGroup.genres,
    mangadexUuid: 'e5301a23-ebd9-49dd-a0cb-2add944c7fe9',
    comicTopic: 'Slice of Life',
  ),
  sports(
    label: 'Esportes',
    group: TagCategoryGroup.genres,
    mangadexUuid: '69964a64-2f90-4d33-beeb-f3ed2875eb4c',
    comicTopic: 'Sports',
  ),
  thriller(
    label: 'Suspense / Thriller',
    group: TagCategoryGroup.genres,
    mangadexUuid: '07251805-a27e-4d59-b488-f0bfbec15168',
    comicTopic: 'Thriller',
  ),
  superhero(
    label: 'Super-Heróis',
    group: TagCategoryGroup.genres,
    mangadexUuid: '7064a261-a137-4d3a-8848-2d385de3a99c',
    comicTopic: 'Action',
  ),

  // --- TEMAS, UNIVERSOS & SUBGÊNEROS ---
  isekai(
    label: 'Isekai (Outro Mundo)',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: 'ace04997-f6bd-436e-b261-779182193d3d',
    adultSlug: 'isekai',
  ),
  reincarnation(
    label: 'Reencarnação / Regressão',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: '0bc90acb-ccc1-44ca-a34a-b9f3a73259d0',
  ),
  martialArts(
    label: 'Artes Marciais / Murim',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: '799c202e-7daa-44eb-9cf7-8a3c0441531e',
  ),
  magicAndSystem(
    label: 'Magia & Sistema RPG / Dungeon',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: 'a1f53773-c69a-4ce5-8cab-fffcd90b1565',
  ),
  supernatural(
    label: 'Sobrenatural & Demônios',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: 'eabc5b4c-6aff-42f3-b657-3e90cbd00b75',
    comicTopic: 'Supernatural',
  ),
  mecha(
    label: 'Mecha (Robôs Gigantes)',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: '50880a9d-5440-4732-9afb-8f457127e836',
    comicTopic: 'Mecha',
  ),
  cyberpunkPostApoc(
    label: 'Pós-Apocalíptico / Cyberpunk',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: '9467335a-1b83-4497-9231-765337a00b96',
  ),
  schoolLife(
    label: 'Vida Escolar',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: 'caaa44eb-cd40-4177-b930-79d3ef2afe87',
  ),
  historicalSamurai(
    label: 'Histórico / Samurai / Ninja',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: '33771934-028e-4cb3-8744-691e866a923e',
  ),
  vampiresZombies(
    label: 'Vampiros & Zumbis',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: 'd7d1730f-6eb0-4ba6-9437-602cac38664c',
  ),
  yuri(
    label: 'Yuri / Girls Love',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: 'a3c67850-4684-404e-9b7f-c69850ee5da6',
    adultSlug: 'yuri',
  ),
  yaoi(
    label: 'Yaoi / Boys Love',
    group: TagCategoryGroup.themesAndTropes,
    mangadexUuid: '5920b825-4181-4a17-beeb-9918b0ff7a30',
    adultSlug: 'yaoi',
  ),

  // --- CATEGORIAS 18+ (OCULTAS QUANDO NSFW DESLIGADO) ---
  uncensored(
    label: 'Sem Censura (18+)',
    group: TagCategoryGroup.nsfwVault,
    isNsfwOnly: true,
    adultSlug: 'uncensored',
  ),
  vanilla(
    label: 'Vanilla / Romântico (18+)',
    group: TagCategoryGroup.nsfwVault,
    isNsfwOnly: true,
    mangadexUuid: '423e2eae-a7a2-4a8b-ac03-a8351462d71d',
    adultSlug: 'vanilla',
  ),
  ecchiHarem(
    label: 'Harém / Ecchi (18+)',
    group: TagCategoryGroup.nsfwVault,
    isNsfwOnly: true,
    mangadexUuid: 'aafb99c1-7f60-43fa-b75f-fc9502ce29c7',
    adultSlug: 'harem',
  ),
  netorare(
    label: 'Netorare / NTR (18+)',
    group: TagCategoryGroup.nsfwVault,
    isNsfwOnly: true,
    adultSlug: 'netorare',
  );

  final String label;
  final TagCategoryGroup group;
  final bool isNsfwOnly;
  final String? mangadexUuid;
  final String? mangadexDemographic;
  final String? mangadexLang;
  final String? adultSlug;
  final String? comicTopic;
  final String? comickQuery;

  const CanonicalTag({
    required this.label,
    required this.group,
    this.isNsfwOnly = false,
    this.mangadexUuid,
    this.mangadexDemographic,
    this.mangadexLang,
    this.adultSlug,
    this.comicTopic,
    this.comickQuery,
  });
}

class YomiSearchFilter {
  final String query;
  final Set<CanonicalTag> includedTags;
  final Set<CanonicalTag> excludedTags;
  final Set<MangaSourceType> enabledSources;
  final bool allowNsfw;
  final CatalogSort sort;
  bool get sortByLatest => sort == CatalogSort.latest;
  final bool hideZeroChapters;

  const YomiSearchFilter({
    this.query = '',
    this.includedTags = const {},
    this.excludedTags = const {},
    this.enabledSources = const {
      MangaSourceType.mangadex,
      MangaSourceType.anilist,
      MangaSourceType.jikanMal,
      MangaSourceType.comick,
      MangaSourceType.comicsHq,
      MangaSourceType.adultSource,
    },
    this.allowNsfw = false,
    bool sortByLatest = true,
    CatalogSort? sort,
    this.hideZeroChapters = false,
  }) : sort = sort ?? (sortByLatest ? CatalogSort.latest : CatalogSort.popular);
}

/// Exact title identity across scripts, without conflating unrelated CJK works.
String normalizeMangaTitle(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

class Manga {
  final String id;
  final MangaSourceType source;
  final String title;
  final String description;
  final String status;
  final String? coverFileName;
  final String? directCoverUrl;
  final String? directHighResCoverUrl;
  final List<String> tags;
  final bool isNsfw;
  final bool contentRatingKnown;
  final DateTime updatedAt;
  final Map<String, String> customHeaders;
  final List<Chapter>? preloadedChapters;
  final int availableChaptersCount;
  final List<Manga> alternativeSources;

  Manga({
    required this.id,
    this.source = MangaSourceType.mangadex,
    required this.title,
    required this.description,
    required this.status,
    this.coverFileName,
    this.directCoverUrl,
    this.directHighResCoverUrl,
    required this.tags,
    this.isNsfw = false,
    this.contentRatingKnown = true,
    DateTime? updatedAt,
    Map<String, String>? customHeaders,
    this.preloadedChapters,
    this.availableChaptersCount = -1,
    this.alternativeSources = const [],
  }) : updatedAt = updatedAt ?? DateTime.now(),
       customHeaders = kIsWeb
           ? const {}
           : (customHeaders ??
                 const {
                   'User-Agent':
                       'Mozilla/5.0 (Windows NT 10.0; Win64; x64) YomiReader/8.0',
                 });

  String get compositeId => '${source.name}_$id';

  bool get isCoverOnly => availableChaptersCount == 0;

  String get normalizedTitleKey {
    return normalizeMangaTitle(title);
  }

  Manga copyWith({
    int? availableChaptersCount,
    List<Manga>? alternativeSources,
    List<Chapter>? preloadedChapters,
  }) {
    return Manga(
      id: id,
      source: source,
      title: title,
      description: description,
      status: status,
      coverFileName: coverFileName,
      directCoverUrl: directCoverUrl,
      directHighResCoverUrl: directHighResCoverUrl,
      tags: tags,
      isNsfw: isNsfw,
      contentRatingKnown: contentRatingKnown,
      updatedAt: updatedAt,
      customHeaders: customHeaders,
      preloadedChapters: preloadedChapters ?? this.preloadedChapters,
      availableChaptersCount:
          availableChaptersCount ?? this.availableChaptersCount,
      alternativeSources: alternativeSources ?? this.alternativeSources,
    );
  }

  String getRawCoverUrl({bool highRes = false}) {
    if (highRes &&
        directHighResCoverUrl != null &&
        directHighResCoverUrl!.isNotEmpty) {
      return directHighResCoverUrl!;
    }
    if (directCoverUrl != null && directCoverUrl!.isNotEmpty) {
      return directCoverUrl!;
    }
    if (coverFileName != null && coverFileName!.isNotEmpty) {
      final cleanId = id
          .replaceFirst('cmk_mdx_', '')
          .replaceFirst('hq_mdx_', '')
          .replaceFirst('ani_mdx_', '')
          .replaceFirst('mal_mdx_', '')
          .replaceFirst('cmk_title_', '');
      final suffix = highRes ? '.512.jpg' : '.256.jpg';
      return 'https://uploads.mangadex.org/covers/$cleanId/$coverFileName$suffix';
    }
    for (final alt in alternativeSources) {
      final altRaw = alt.getRawCoverUrl(highRes: highRes);
      if (altRaw.isNotEmpty) return altRaw;
    }
    return '';
  }

  List<String> getAllCandidateCoverUrls({bool highRes = false}) {
    final urls = <String>[];
    final primaryRaw = getRawCoverUrl(highRes: highRes);
    if (primaryRaw.isNotEmpty) {
      urls.addAll(yomiCandidateImageUrls(primaryRaw));
    }
    for (final alt in alternativeSources) {
      final altRaw = alt.getRawCoverUrl(highRes: highRes);
      if (altRaw.isNotEmpty && altRaw != primaryRaw) {
        for (final u in yomiCandidateImageUrls(altRaw)) {
          if (!urls.contains(u)) urls.add(u);
        }
      }
    }
    return urls;
  }

  String getCoverUrl({bool highRes = false}) {
    String raw;
    if (highRes &&
        directHighResCoverUrl != null &&
        directHighResCoverUrl!.isNotEmpty) {
      raw = directHighResCoverUrl!;
    } else if (directCoverUrl != null && directCoverUrl!.isNotEmpty) {
      raw = directCoverUrl!;
    } else if (coverFileName != null && coverFileName!.isNotEmpty) {
      final cleanId = id
          .replaceFirst('cmk_mdx_', '')
          .replaceFirst('hq_mdx_', '')
          .replaceFirst('ani_mdx_', '')
          .replaceFirst('mal_mdx_', '');
      final suffix = highRes ? '.512.jpg' : '.256.jpg';
      raw =
          'https://uploads.mangadex.org/covers/$cleanId/$coverFileName$suffix';
    } else {
      raw = '';
    }
    return yomiSafeImageUrl(raw);
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'source': source.name,
    'title': title,
    'description': description,
    'status': status,
    'coverFileName': coverFileName,
    'directCoverUrl': directCoverUrl,
    'directHighResCoverUrl': directHighResCoverUrl,
    'tags': tags,
    'isNsfw': isNsfw,
    'contentRatingKnown': contentRatingKnown,
    'updatedAt': updatedAt.toIso8601String(),
    'customHeaders': customHeaders,
    'availableChaptersCount': availableChaptersCount,
    'preloadedChapters': preloadedChapters?.map((c) => c.toMap()).toList(),
  };

  factory Manga.fromMap(Map<String, dynamic> map) {
    final rawPreloaded = map['preloadedChapters'];
    final source = MangaSourceType.fromName(map['source']?.toString());
    final id = (map['id'] ?? '').toString();
    final legacyMangaDex =
        id.startsWith('cmk_mdx_') || id.startsWith('mal_mdx_');
    // Older Jikan/Kitsu records hard-coded isNsfw=false. Preserve their data
    // and IDs, but require sensitive mode until a fresh classified lookup.
    final known = map['contentRatingKnown'] is bool
        ? map['contentRatingKnown'] == true
        : legacyMangaDex ||
              (source != MangaSourceType.jikanMal &&
                  source != MangaSourceType.comick);
    return Manga(
      id: id,
      source: source,
      title: (map['title'] ?? 'Sem Título').toString(),
      description: (map['description'] ?? '').toString(),
      status: (map['status'] ?? 'PUBLICADO').toString(),
      coverFileName: map['coverFileName']?.toString(),
      directCoverUrl: map['directCoverUrl']?.toString(),
      directHighResCoverUrl: map['directHighResCoverUrl']?.toString(),
      tags: map['tags'] is List
          ? (map['tags'] as List).whereType<String>().toList()
          : const [],
      isNsfw: map['isNsfw'] == true || !known,
      contentRatingKnown: known,
      updatedAt:
          DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      customHeaders: kIsWeb
          ? const {}
          : (map['customHeaders'] is Map
                ? {
                    for (final entry in (map['customHeaders'] as Map).entries)
                      if (entry.key is String && entry.value is String)
                        entry.key as String: entry.value as String,
                  }
                : const {
                    'User-Agent':
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) YomiReader/8.0',
                  }),
      availableChaptersCount:
          map['availableChaptersCount'] is int &&
              map['availableChaptersCount'] >= -1
          ? map['availableChaptersCount'] as int
          : -1,
      preloadedChapters: rawPreloaded is List
          ? rawPreloaded
                .whereType<Map>()
                .where((entry) => entry.keys.every((key) => key is String))
                .map(
                  (entry) => Chapter.fromMap(Map<String, dynamic>.from(entry)),
                )
                .where((chapter) => chapter.id.isNotEmpty)
                .toList()
          : null,
    );
  }

  factory Manga.fromJson(
    Map<String, dynamic> json, {
    MangaSourceType overrideSource = MangaSourceType.mangadex,
    bool forceNsfwFlag = false,
  }) {
    final attributes = json['attributes'] ?? {};
    final titleMap = Map<String, dynamic>.from(attributes['title'] ?? {});
    String resolvedTitle =
        titleMap['pt-br'] ??
        titleMap['en'] ??
        titleMap['ja-ro'] ??
        (titleMap.values.isNotEmpty ? titleMap.values.first.toString() : '');

    // Se title principal vier vazio, procura em altTitles
    if (resolvedTitle.trim().isEmpty) {
      final altList = (attributes['altTitles'] as List?) ?? [];
      for (final alt in altList) {
        if (alt is Map && alt.values.isNotEmpty) {
          resolvedTitle = (alt['pt-br'] ?? alt['en'] ?? alt.values.first)
              .toString();
          if (resolvedTitle.trim().isNotEmpty) break;
        }
      }
    }
    if (resolvedTitle.trim().isEmpty) resolvedTitle = 'Obra Sem Título';

    final descMap = Map<String, dynamic>.from(attributes['description'] ?? {});
    String resolvedDesc =
        descMap['pt-br'] ??
        descMap['en'] ??
        (descMap.values.isNotEmpty
            ? descMap.values.first.toString()
            : 'Sinopse não disponível.');

    final rawTags = (attributes['tags'] as List?) ?? [];
    final parsedTags = rawTags
        .map((t) {
          final nameMap = t['attributes']?['name'] as Map?;
          return (nameMap?['pt-br'] ?? nameMap?['en'] ?? '').toString();
        })
        .where((t) => t.isNotEmpty)
        .take(8)
        .toList();

    String? coverFile;
    final relationships = (json['relationships'] as List?) ?? [];
    for (final rel in relationships) {
      if (rel['type'] == 'cover_art' && rel['attributes'] != null) {
        coverFile = rel['attributes']['fileName'];
        break;
      }
    }

    final String rating = attributes['contentRating']?.toString() ?? '';
    final bool ratingKnown =
        forceNsfwFlag ||
        const {
          'safe',
          'suggestive',
          'erotica',
          'pornographic',
        }.contains(rating);
    final bool isNsfw =
        forceNsfwFlag ||
        !ratingKnown ||
        rating == 'erotica' ||
        rating == 'pornographic';

    final DateTime updated =
        DateTime.tryParse(attributes['updatedAt']?.toString() ?? '') ??
        DateTime.now();

    // Publication totals and an uploaded chapter ID do not prove how many
    // readable chapters this app can fetch. Only a cached feed knows a count.
    final int knownAvailability =
        attributes.containsKey('latestUploadedChapter') &&
            (attributes['latestUploadedChapter'] == null ||
                attributes['latestUploadedChapter'].toString().isEmpty)
        ? 0
        : -1;

    return Manga(
      id: json['id'].toString(),
      source: overrideSource,
      title: resolvedTitle,
      description: resolvedDesc,
      status: (attributes['status'] ?? 'ongoing').toString().toUpperCase(),
      coverFileName: coverFile,
      tags: parsedTags,
      isNsfw: isNsfw,
      contentRatingKnown: ratingKnown,
      updatedAt: updated,
      availableChaptersCount: knownAvailability,
    );
  }
}

class Chapter {
  final String id;
  final MangaSourceType source;
  final String chapterNumber;
  final String title;
  final String language;
  final int pages;
  final String scanlator;
  final List<String>? directPageUrls;
  final String? externalArchiveId;

  Chapter({
    required this.id,
    this.source = MangaSourceType.mangadex,
    required this.chapterNumber,
    required this.title,
    required this.language,
    required this.pages,
    this.scanlator = 'Scan Oficial / Comunidade',
    this.directPageUrls,
    this.externalArchiveId,
  });

  double get numericChapter {
    final cleaned = chapterNumber.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 999999.0;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'source': source.name,
    'chapterNumber': chapterNumber,
    'title': title,
    'language': language,
    'pages': pages,
    'scanlator': scanlator,
    'directPageUrls': directPageUrls,
    'externalArchiveId': externalArchiveId,
  };

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
    id: (map['id'] ?? '').toString(),
    source: MangaSourceType.fromName(map['source']?.toString()),
    chapterNumber: (map['chapterNumber'] ?? '1').toString(),
    title: (map['title'] ?? 'Capítulo').toString(),
    language: (map['language'] ?? 'PT-BR').toString(),
    pages: map['pages'] is int && map['pages'] >= 0 ? map['pages'] as int : 0,
    scanlator: (map['scanlator'] ?? 'Comunidade').toString(),
    directPageUrls:
        map['directPageUrls'] is List &&
            (map['directPageUrls'] as List).every((value) => value is String)
        ? List<String>.from(map['directPageUrls'] as List)
        : null,
    externalArchiveId: map['externalArchiveId']?.toString(),
  );

  factory Chapter.fromJson(
    Map<String, dynamic> json, {
    MangaSourceType source = MangaSourceType.mangadex,
  }) {
    final attr = json['attributes'] ?? {};
    String scanName = 'Comunidade';
    final rels = (json['relationships'] as List?) ?? [];
    for (final r in rels) {
      if (r['type'] == 'scanlation_group' && r['attributes'] != null) {
        scanName = (r['attributes']['name'] ?? 'Comunidade').toString();
        break;
      }
    }

    final chNum = (attr['chapter'] ?? '1').toString();
    return Chapter(
      id: json['id'].toString(),
      source: source,
      chapterNumber: chNum,
      title:
          (attr['title'] != null && attr['title'].toString().trim().isNotEmpty)
          ? attr['title'].toString()
          : 'Capítulo $chNum',
      language: (attr['translatedLanguage'] ?? 'en').toString().toUpperCase(),
      pages: (attr['pages'] as int?) ?? 0,
      scanlator: scanName,
    );
  }
}

class ChapterPagesData {
  final String baseUrl;
  final String hash;
  final List<String> hdFiles;
  final List<String> dataSaverFiles;
  final List<String>? directUrls;

  ChapterPagesData({
    required this.baseUrl,
    required this.hash,
    required this.hdFiles,
    required this.dataSaverFiles,
    this.directUrls,
  });

  List<String> getUrls({required bool useDataSaver}) {
    if (directUrls != null && directUrls!.isNotEmpty) {
      if (directUrls!.any((url) => !_validPageUrl(url))) {
        throw const FormatException('Endereço de página inválido');
      }
      return directUrls!.map(yomiSafeImageUrl).toList();
    }
    // Some chapters expose only one quality. Preserve the page sequence while
    // falling back to the available set instead of returning an empty chapter.
    final useSaver = useDataSaver ? dataSaverFiles.isNotEmpty : hdFiles.isEmpty;
    final folder = useSaver ? 'data-saver' : 'data';
    final files = useSaver ? dataSaverFiles : hdFiles;
    if (files.isEmpty) return const [];
    if (!_validPageUrl(baseUrl) ||
        hash.trim().isEmpty ||
        files.any((file) => file.trim().isEmpty)) {
      throw const FormatException('Dados de páginas inválidos');
    }
    return files
        .map((file) => yomiSafeImageUrl('$baseUrl/$folder/$hash/$file'))
        .toList();
  }

  static bool _validPageUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }
}

class UserProfile {
  final String name;
  final String bio;
  final int avatarIndex;
  final String favoriteGenre;
  final bool openOnProfileByDefault;
  final bool isConfigured;
  final String? avatarImagePath;
  final String? bannerImagePath;
  final bool useBlobatarAsAvatar;
  final String blobatarName;
  final String blobatarSeed;
  final String blobatarShape;
  final String blobatarExpression;
  final double? blobatarHue;
  final String blobatarBackground;
  final bool blobatarAnimated;
  final int? customAccentColor;

  const UserProfile({
    this.name = 'Leitor YOMI',
    this.bio = 'Explorando universos de mangás, manhwas e HQs.',
    this.avatarIndex = 0,
    this.favoriteGenre = 'Ação, Fantasia & Seinen',
    this.openOnProfileByDefault = false,
    this.isConfigured = true,
    this.avatarImagePath,
    this.bannerImagePath,
    this.useBlobatarAsAvatar = true,
    this.blobatarName = 'Kuro',
    this.blobatarSeed = '',
    this.blobatarShape = 'auto',
    this.blobatarExpression = 'happy',
    this.blobatarHue,
    this.blobatarBackground = 'circle',
    this.blobatarAnimated = true,
    this.customAccentColor,
  });

  String get effectiveBlobatarSeed =>
      blobatarSeed.trim().isNotEmpty ? blobatarSeed.trim() : name;

  String get effectiveBlobatarName =>
      blobatarName.trim().isNotEmpty ? blobatarName.trim() : 'Kuro';

  List<String> get genreTags {
    final parts = favoriteGenre
        .split(RegExp(r'[,•·&/]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty
        ? const ['Ação', 'Fantasia', 'Romance', 'Seinen']
        : parts;
  }

  UserProfile copyWith({
    String? name,
    String? bio,
    int? avatarIndex,
    String? favoriteGenre,
    bool? openOnProfileByDefault,
    bool? isConfigured,
    String? avatarImagePath,
    bool clearAvatarImage = false,
    String? bannerImagePath,
    bool clearBannerImage = false,
    bool? useBlobatarAsAvatar,
    String? blobatarName,
    String? blobatarSeed,
    String? blobatarShape,
    String? blobatarExpression,
    double? blobatarHue,
    bool clearBlobatarHue = false,
    String? blobatarBackground,
    bool? blobatarAnimated,
    int? customAccentColor,
    bool clearCustomAccentColor = false,
  }) {
    return UserProfile(
      name: name ?? this.name,
      bio: bio ?? this.bio,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      favoriteGenre: favoriteGenre ?? this.favoriteGenre,
      openOnProfileByDefault:
          openOnProfileByDefault ?? this.openOnProfileByDefault,
      isConfigured: isConfigured ?? this.isConfigured,
      avatarImagePath:
          clearAvatarImage ? null : (avatarImagePath ?? this.avatarImagePath),
      bannerImagePath:
          clearBannerImage ? null : (bannerImagePath ?? this.bannerImagePath),
      useBlobatarAsAvatar: useBlobatarAsAvatar ?? this.useBlobatarAsAvatar,
      blobatarName: blobatarName ?? this.blobatarName,
      blobatarSeed: blobatarSeed ?? this.blobatarSeed,
      blobatarShape: blobatarShape ?? this.blobatarShape,
      blobatarExpression: blobatarExpression ?? this.blobatarExpression,
      blobatarHue:
          clearBlobatarHue ? null : (blobatarHue ?? this.blobatarHue),
      blobatarBackground: blobatarBackground ?? this.blobatarBackground,
      blobatarAnimated: blobatarAnimated ?? this.blobatarAnimated,
      customAccentColor: clearCustomAccentColor
          ? null
          : (customAccentColor ?? this.customAccentColor),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'bio': bio,
    'avatarIndex': avatarIndex,
    'favoriteGenre': favoriteGenre,
    'openOnProfileByDefault': openOnProfileByDefault,
    'isConfigured': isConfigured,
    if (avatarImagePath != null) 'avatarImagePath': avatarImagePath,
    if (bannerImagePath != null) 'bannerImagePath': bannerImagePath,
    'useBlobatarAsAvatar': useBlobatarAsAvatar,
    'blobatarName': blobatarName,
    'blobatarSeed': blobatarSeed,
    'blobatarShape': blobatarShape,
    'blobatarExpression': blobatarExpression,
    if (blobatarHue != null) 'blobatarHue': blobatarHue,
    'blobatarBackground': blobatarBackground,
    'blobatarAnimated': blobatarAnimated,
    if (customAccentColor != null) 'customAccentColor': customAccentColor,
  };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    name: (map['name'] ?? 'Leitor YOMI').toString(),
    bio: (map['bio'] ?? 'Explorando universos de mangás, manhwas e HQs.')
        .toString(),
    avatarIndex: map['avatarIndex'] is int && map['avatarIndex'] >= 0
        ? map['avatarIndex'] as int
        : 0,
    favoriteGenre: (map['favoriteGenre'] ?? 'Ação, Fantasia & Seinen')
        .toString(),
    // Keep the saved preference when present; new installations start
    // in the reading-focused Home screen.
    openOnProfileByDefault: map['openOnProfileByDefault'] == true,
    isConfigured: map['isConfigured'] != false,
    avatarImagePath: map['avatarImagePath'] is String &&
            (map['avatarImagePath'] as String).trim().isNotEmpty
        ? (map['avatarImagePath'] as String).trim()
        : null,
    bannerImagePath: map['bannerImagePath'] is String &&
            (map['bannerImagePath'] as String).trim().isNotEmpty
        ? (map['bannerImagePath'] as String).trim()
        : null,
    useBlobatarAsAvatar: map['useBlobatarAsAvatar'] is bool
        ? map['useBlobatarAsAvatar'] as bool
        : true,
    blobatarName: map['blobatarName'] is String &&
            (map['blobatarName'] as String).trim().isNotEmpty
        ? (map['blobatarName'] as String).trim()
        : 'Kuro',
    blobatarSeed: (map['blobatarSeed'] ?? '').toString(),
    blobatarShape: (map['blobatarShape'] ?? 'auto').toString(),
    blobatarExpression: (map['blobatarExpression'] ?? 'happy').toString(),
    blobatarHue: map['blobatarHue'] is num &&
            (map['blobatarHue'] as num).isFinite
        ? (map['blobatarHue'] as num).toDouble()
        : null,
    blobatarBackground: (map['blobatarBackground'] ?? 'circle').toString(),
    blobatarAnimated: map['blobatarAnimated'] != false,
    customAccentColor: map['customAccentColor'] is int
        ? map['customAccentColor'] as int
        : null,
  );
}

class UserReadingList {
  final String id;
  final String name;
  final String description;
  final List<Manga> mangas;
  final DateTime createdAt;

  UserReadingList({
    required this.id,
    required this.name,
    this.description = '',
    this.mangas = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  UserReadingList copyWith({
    String? id,
    String? name,
    String? description,
    List<Manga>? mangas,
    DateTime? createdAt,
  }) {
    return UserReadingList(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      mangas: mangas ?? this.mangas,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'mangas': mangas.map((m) => m.toMap()).toList(),
  };

  factory UserReadingList.fromMap(Map<String, dynamic> map) {
    final rawMangas = map['mangas'];
    final parsedMangas = <Manga>[];
    if (rawMangas is List) {
      for (final item in rawMangas) {
        if (item is Map) {
          try {
            final m = Manga.fromMap(Map<String, dynamic>.from(item));
            if (m.id.isNotEmpty) {
              parsedMangas.add(m);
            }
          } catch (_) {}
        }
      }
    }
    return UserReadingList(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? 'Lista de Leitura').toString(),
      description: (map['description'] ?? '').toString(),
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      mangas: parsedMangas,
    );
  }
}

class ReadingMetricsSummary {
  final int chaptersReadToday;
  final int chaptersReadThisWeek;
  final int totalChaptersRead;
  final int totalPagesRead;
  final Manga? mostReadManga;
  final int mostReadCount;
  final Manga? leastReadManga;
  final int leastReadCount;
  final Chapter? longestChapterRead;
  final Chapter? shortestChapterRead;
  final List<MapEntry<Manga, int>> rankedMangas;

  const ReadingMetricsSummary({
    required this.chaptersReadToday,
    required this.chaptersReadThisWeek,
    required this.totalChaptersRead,
    required this.totalPagesRead,
    this.mostReadManga,
    this.mostReadCount = 0,
    this.leastReadManga,
    this.leastReadCount = 0,
    this.longestChapterRead,
    this.shortestChapterRead,
    this.rankedMangas = const [],
  });

  String get rankTitle {
    if (totalChaptersRead >= 100) return 'Xogun das Letras • Nível S';
    if (totalChaptersRead >= 40) return 'Mestre Ronin • Nível A';
    if (totalChaptersRead >= 15) return 'Espadachim Samurai • Nível B';
    if (totalChaptersRead >= 3) return 'Caçador de Capítulos • Nível C';
    return 'Iniciado do Torii • Nível 1';
  }

  double get rankProgress {
    if (totalChaptersRead >= 100) return 1.0;
    if (totalChaptersRead >= 40) return (totalChaptersRead - 40) / 60.0;
    if (totalChaptersRead >= 15) return (totalChaptersRead - 15) / 25.0;
    if (totalChaptersRead >= 3) return (totalChaptersRead - 3) / 12.0;
    return (totalChaptersRead / 3.0).clamp(0.08, 1.0);
  }
}
