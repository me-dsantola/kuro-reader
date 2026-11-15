import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/catalog_sort.dart';
import '../models/content_rating.dart';
import '../models/manga_models.dart';
import 'device_state_service.dart';
import 'observed_http.dart';
import 'storage_service.dart';
import 'telegram_vault_service.dart';

class PaginatedSourceResponse {
  final List<Manga> items;
  final int nextCursor;
  final bool hasMore;

  const PaginatedSourceResponse({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}

abstract class IMangaSourceAdapter {
  MangaSourceType get sourceType;
  Future<PaginatedSourceResponse> fetchCatalog({
    required YomiSearchFilter filter,
    required int cursor,
  });
}

class SourceCircuitBreaker {
  int _failures = 0;
  DateTime? _openUntil;

  bool get isOpen {
    if (_openUntil == null) return false;
    if (DateTime.now().isAfter(_openUntil!)) {
      _openUntil = null;
      _failures = 0;
      return false;
    }
    return true;
  }

  void recordSuccess() {
    _failures = 0;
    _openUntil = null;
  }

  void recordFailure({int? statusCode}) {
    _failures++;
    if (statusCode == 429) {
      _openUntil = DateTime.now().add(const Duration(seconds: 45));
    } else if (_failures >= 3) {
      _openUntil = DateTime.now().add(const Duration(seconds: 30));
    }
  }
}

// ============================================================================
// ADAPTER 1: MANGADEX OFICIAL v5 (MANGÁS, MANHWAS, MANHUAS + TAGS COMPLETAS)
// ============================================================================
class MangaDexAdapter implements IMangaSourceAdapter {
  static const String _baseUrl = 'https://api.mangadex.org';

  @override
  MangaSourceType get sourceType => MangaSourceType.mangadex;

  @override
  Future<PaginatedSourceResponse> fetchCatalog({
    required YomiSearchFilter filter,
    required int cursor,
  }) async {
    final onlyWesternComics =
        filter.includedTags.isNotEmpty &&
        filter.includedTags.every(
          (t) =>
              t == CanonicalTag.marvelComics ||
              t == CanonicalTag.dcComics ||
              t == CanonicalTag.westernIndieHq,
        );
    if (onlyWesternComics) {
      return const PaginatedSourceResponse(
        items: [],
        nextCursor: 0,
        hasMore: false,
      );
    }

    const int limit = 24;
    final buf = StringBuffer('$_baseUrl/manga?limit=$limit&offset=$cursor');
    buf.write('&includes[]=cover_art');

    if (filter.query.trim().isEmpty) {
      buf.write('&hasAvailableChapters=true');
    }

    buf.write('&contentRating[]=safe&contentRating[]=suggestive');
    if (filter.allowNsfw) {
      buf.write('&contentRating[]=erotica');
    }

    for (final tag in filter.includedTags) {
      if (tag.mangadexUuid != null) {
        buf.write('&includedTags[]=${tag.mangadexUuid}');
      }
      if (tag.mangadexDemographic != null) {
        buf.write('&publicationDemographic[]=${tag.mangadexDemographic}');
      }
      if (tag.mangadexLang != null) {
        buf.write('&originalLanguage[]=${tag.mangadexLang}');
      }
    }
    for (final tag in filter.excludedTags) {
      if (tag.mangadexUuid != null) {
        buf.write('&excludedTags[]=${tag.mangadexUuid}');
      }
    }

    if (filter.query.trim().isNotEmpty) {
      buf.write('&title=${Uri.encodeQueryComponent(filter.query.trim())}');
    }

    buf.write(filter.sort.mangaDexOrder);

    final response = await MangaDexService.safeHttpGet(buf.toString());

    final data = jsonDecode(response.body);
    final List list = data['data'] ?? [];
    final int total = data['total'] ?? 0;

    // MangaDex accepts excludedTags[] for genre UUIDs, but does not offer
    // exclusion parameters for originalLanguage or publicationDemographic.
    // Apply those exclusions locally instead of silently ignoring them.
    final excludedLanguages = filter.excludedTags
        .map((tag) => tag.mangadexLang)
        .whereType<String>()
        .toSet();
    final excludedDemographics = filter.excludedTags
        .map((tag) => tag.mangadexDemographic)
        .whereType<String>()
        .toSet();

    final items = <Manga>[];
    for (final json in list) {
      if (json is! Map) continue;
      final attributes = json['attributes'];
      if (attributes is Map) {
        final language = attributes['originalLanguage']?.toString();
        final demographic = attributes['publicationDemographic']?.toString();
        if (excludedLanguages.contains(language) ||
            excludedDemographics.contains(demographic)) {
          continue;
        }
      }
      final m = Manga.fromJson(
        Map<String, dynamic>.from(json),
        overrideSource: MangaSourceType.mangadex,
      );
      final knownCount = StorageService.getKnownChaptersCount(
        m.id,
        m.availableChaptersCount,
        titleKey: m.normalizedTitleKey,
      );
      items.add(m.copyWith(availableChaptersCount: knownCount));
    }

    return PaginatedSourceResponse(
      items: items,
      nextCursor: cursor + limit,
      hasMore: (cursor + limit) < total,
    );
  }
}

// ============================================================================
// ADAPTER 2: ANILIST GRAPHQL API (100% CORS NATIVO NO CHROME & ANDROID!)
// ============================================================================
class AniListGraphQLAdapter implements IMangaSourceAdapter {
  @override
  MangaSourceType get sourceType => MangaSourceType.anilist;

  @override
  Future<PaginatedSourceResponse> fetchCatalog({
    required YomiSearchFilter filter,
    required int cursor,
  }) async {
    final onlyWesternComics =
        filter.includedTags.isNotEmpty &&
        filter.includedTags.every(
          (t) =>
              t == CanonicalTag.marvelComics ||
              t == CanonicalTag.dcComics ||
              t == CanonicalTag.westernIndieHq,
        );
    if (onlyWesternComics) {
      return const PaginatedSourceResponse(
        items: [],
        nextCursor: 0,
        hasMore: false,
      );
    }

    final int page = (cursor ~/ 20) + 1;
    final String sortMode = filter.sort.aniListOrder;

    String countryFilter = '';
    if (filter.includedTags.contains(CanonicalTag.manhwaKr)) {
      countryFilter = ', countryOfOrigin: "KR"';
    } else if (filter.includedTags.contains(CanonicalTag.manhuaCn)) {
      countryFilter = ', countryOfOrigin: "CN"';
    } else if (filter.includedTags.contains(CanonicalTag.mangaJp)) {
      countryFilter = ', countryOfOrigin: "JP"';
    }

    final genres = <String>[];
    for (final t in filter.includedTags) {
      if (t.comicTopic != null &&
          t.group == TagCategoryGroup.genres &&
          t.comicTopic != 'superhero') {
        genres.add('"${t.comicTopic}"');
      }
    }
    final String genreFilter = genres.isNotEmpty
        ? ', genre_in: [${genres.join(",")}]'
        : '';

    // AniList supports explicit genre exclusions in its GraphQL search.
    final excludedGenres = <String>[];
    for (final tag in filter.excludedTags) {
      if (tag.group == TagCategoryGroup.genres &&
          tag.comicTopic != null &&
          tag.comicTopic != 'superhero') {
        excludedGenres.add(jsonEncode(tag.comicTopic));
      }
    }
    final String excludedGenreFilter = excludedGenres.isNotEmpty
        ? ', genre_not_in: [${excludedGenres.join(",")}]'
        : '';

    final String searchArg = filter.query.trim().isNotEmpty
        ? ', search: ${jsonEncode(filter.query.trim())}'
        : '';

    final String gqlQuery =
        'query { Page(page: $page, perPage: 20) { pageInfo { hasNextPage } media(type: MANGA, isAdult: ${filter.allowNsfw ? "null" : "false"}, sort: [$sortMode]$searchArg$countryFilter$genreFilter$excludedGenreFilter) { id updatedAt title { english romaji } description(asHtml: false) status chapters genres isAdult countryOfOrigin coverImage { large extraLarge } } } }';

    final response = await ObservedHttp.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'query': gqlQuery}),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('AniList HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final pageData = decoded['data']?['Page'] ?? {};
    final bool hasNext = pageData['pageInfo']?['hasNextPage'] == true;
    final List mediaList = pageData['media'] ?? [];

    final items = <Manga>[];
    for (final m in mediaList) {
      if (m is! Map) continue;
      final bool isAdult = m['isAdult'] == true;
      if (!filter.allowNsfw && isAdult) continue;

      final excludedCountries = <String>{
        if (filter.excludedTags.contains(CanonicalTag.mangaJp)) 'JP',
        if (filter.excludedTags.contains(CanonicalTag.manhwaKr)) 'KR',
        if (filter.excludedTags.contains(CanonicalTag.manhuaCn)) 'CN',
      };
      if (excludedCountries.contains(m['countryOfOrigin'])) continue;

      final titleObj = m['title'] ?? {};
      final String title =
          (titleObj['english'] ?? titleObj['romaji'] ?? 'Sem Título')
              .toString();
      final String rawDesc = (m['description'] ?? 'Sinopse via AniList Global.')
          .toString();
      final String cleanDesc = rawDesc
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      final coverObj = m['coverImage'] ?? {};
      final String coverLarge = (coverObj['large'] ?? '').toString();
      final String coverXL = (coverObj['extraLarge'] ?? coverLarge).toString();

      // AniList may omit chapter totals; unknown is not a fabricated count.
      final statusStr = (m['status'] ?? 'RELEASING').toString().toUpperCase();
      final rawCh = (m['chapters'] as num?)?.toInt();
      final fallbackCh = (rawCh == 0 || statusStr == 'NOT_YET_RELEASED')
          ? 0
          : -1;
      final itemId = 'ani_title_${Uri.encodeComponent(title)}';
      final int chCount = StorageService.getKnownChaptersCount(
        itemId,
        fallbackCh,
        titleKey: normalizeMangaTitle(title),
      );
      final List<String> parsedGenres = List<String>.from(
        m['genres'] ?? [],
      ).take(6).toList();

      items.add(
        Manga(
          id: itemId,
          source: MangaSourceType.anilist,
          title: title,
          description: cleanDesc,
          status: statusStr,
          directCoverUrl: coverLarge,
          directHighResCoverUrl: coverXL,
          tags: ['AniList Oficial', ...parsedGenres],
          isNsfw: isAdult,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            ((m['updatedAt'] as num?)?.toInt() ?? 0) * 1000,
          ),
          availableChaptersCount: chCount,
        ),
      );
    }

    return PaginatedSourceResponse(
      items: items,
      nextCursor: cursor + 20,
      hasMore: hasNext,
    );
  }
}

// ============================================================================
// ADAPTER 3: MYANIMELIST / JIKAN v4 API (100% CORS NATIVO NO CHROME & ANDROID!)
// ============================================================================
class JikanMalAdapter implements IMangaSourceAdapter {
  @override
  MangaSourceType get sourceType => MangaSourceType.jikanMal;

  @override
  Future<PaginatedSourceResponse> fetchCatalog({
    required YomiSearchFilter filter,
    required int cursor,
  }) async {
    final onlyWesternComics =
        filter.includedTags.isNotEmpty &&
        filter.includedTags.every(
          (t) =>
              t == CanonicalTag.marvelComics ||
              t == CanonicalTag.dcComics ||
              t == CanonicalTag.westernIndieHq,
        );
    if (onlyWesternComics) {
      return const PaginatedSourceResponse(
        items: [],
        nextCursor: 0,
        hasMore: false,
      );
    }

    final int page = (cursor ~/ 20) + 1;
    final buf = StringBuffer(
      'https://api.jikan.moe/v4/manga?page=$page&limit=20&sfw=${!filter.allowNsfw}',
    );

    if (filter.query.trim().isNotEmpty) {
      buf.write('&q=${Uri.encodeQueryComponent(filter.query.trim())}');
    } else if (filter.includedTags.contains(CanonicalTag.manhwaKr)) {
      buf.write('&type=manhwa');
    } else if (filter.includedTags.contains(CanonicalTag.manhuaCn)) {
      buf.write('&type=manhua');
    }
    buf.write(filter.sort.jikanOrder);

    final response = await ObservedHttp.get(
      Uri.parse(buf.toString()),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('Jikan MAL HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    final List dataList = body['data'] ?? [];
    final bool hasNext = body['pagination']?['has_next_page'] == true;

    final items = <Manga>[];
    for (final entry in dataList) {
      if (entry is! Map) continue;
      final rating = ContentRating.fromJikan(entry);
      if (!filter.allowNsfw && rating.needsSensitiveMode) continue;
      final String title =
          (entry['title_english'] ?? entry['title'] ?? 'Sem Título').toString();
      final String synopsis =
          (entry['synopsis'] ?? 'Acervo MyAnimeList / Jikan.').toString();
      final jpgMap = entry['images']?['jpg'] ?? {};
      final String imgUrl = (jpgMap['image_url'] ?? '').toString();
      final String largeImgUrl = (jpgMap['large_image_url'] ?? imgUrl)
          .toString();
      // Jikan returns null when the chapter total is unknown.
      final statusStr = (entry['status'] ?? 'Publishing')
          .toString()
          .toUpperCase();
      final rawCh = (entry['chapters'] as num?)?.toInt();
      final fallbackCh = (rawCh == 0 || statusStr.contains('NOT YET')) ? 0 : -1;
      final itemId = 'mal_title_${Uri.encodeComponent(title)}';
      final int chCount = StorageService.getKnownChaptersCount(
        itemId,
        fallbackCh,
        titleKey: normalizeMangaTitle(title),
      );

      final List rawGenres = entry['genres'] ?? [];
      final tags = rawGenres
          .whereType<Map>()
          .map((g) => (g['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .take(5)
          .toList();

      items.add(
        Manga(
          id: 'mal_title_${Uri.encodeComponent(title)}',
          source: MangaSourceType.jikanMal,
          title: title,
          description: synopsis,
          status: (entry['status'] ?? 'Publishing').toString().toUpperCase(),
          directCoverUrl: imgUrl,
          directHighResCoverUrl: largeImgUrl,
          tags: ['MyAnimeList', ...tags],
          isNsfw: rating.needsSensitiveMode,
          contentRatingKnown: rating != ContentRating.unknown,
          updatedAt:
              DateTime.tryParse(
                entry['published']?['from']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          availableChaptersCount: chCount,
        ),
      );
    }

    return PaginatedSourceResponse(
      items: items,
      nextCursor: cursor + 20,
      hasMore: hasNext,
    );
  }
}

// ============================================================================
// ADAPTER 4: COMICK / SCANS PLUS (VIA KITSU EDGE API NATIVA + MULTI-IDIOMA)
// ============================================================================
class ComicKPlusAdapter implements IMangaSourceAdapter {
  @override
  MangaSourceType get sourceType => MangaSourceType.comick;

  @override
  Future<PaginatedSourceResponse> fetchCatalog({
    required YomiSearchFilter filter,
    required int cursor,
  }) async {
    final onlyWesternComics =
        filter.includedTags.isNotEmpty &&
        filter.includedTags.every(
          (t) =>
              t == CanonicalTag.marvelComics ||
              t == CanonicalTag.dcComics ||
              t == CanonicalTag.westernIndieHq,
        );
    if (onlyWesternComics) {
      return const PaginatedSourceResponse(
        items: [],
        nextCursor: 0,
        hasMore: false,
      );
    }

    // 1. Consulta Kitsu Edge API (100% CORS nativo no Chrome e Android, ultra rápida!)
    try {
      const int limit = 20;
      final buf = StringBuffer(
        'https://kitsu.io/api/edge/manga?page[limit]=$limit&page[offset]=$cursor',
      );
      if (filter.query.trim().isNotEmpty) {
        buf.write(
          '&filter[text]=${Uri.encodeQueryComponent(filter.query.trim())}',
        );
      }
      buf.write('&sort=${filter.sort.kitsuOrder}');

      final res = await ObservedHttp.get(
        Uri.parse(buf.toString()),
        headers: const {'Accept': 'application/vnd.api+json'},
      ).timeout(const Duration(seconds: 7));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final List dataList = decoded['data'] ?? [];
        if (dataList.isNotEmpty) {
          final items = <Manga>[];
          for (final item in dataList) {
            if (item is! Map) continue;
            final attr = item['attributes'] ?? {};
            final rating = ContentRating.fromKitsu(attr);
            if (!filter.allowNsfw && rating.needsSensitiveMode) continue;
            final titles = attr['titles'] ?? {};
            final String title =
                (attr['canonicalTitle'] ??
                        titles['en'] ??
                        titles['en_jp'] ??
                        'Sem Título')
                    .toString();
            final String desc =
                (attr['synopsis'] ?? 'Acervo Scans Plus / Kitsu.').toString();
            final poster = attr['posterImage'] ?? {};
            final String coverSmall =
                (poster['medium'] ?? poster['large'] ?? '').toString();
            final String coverLarge =
                (poster['large'] ?? poster['original'] ?? coverSmall)
                    .toString();
            final statusStr = (attr['status'] ?? 'current')
                .toString()
                .toUpperCase();
            final rawCh = (attr['chapterCount'] as num?)?.toInt();
            final fallbackCh =
                (rawCh == 0 ||
                    statusStr == 'UNRELEASED' ||
                    statusStr == 'UPCOMING')
                ? 0
                : -1;
            final itemId = 'cmk_title_${Uri.encodeComponent(title)}';
            final int chCount = StorageService.getKnownChaptersCount(
              itemId,
              fallbackCh,
              titleKey: normalizeMangaTitle(title),
            );
            final String subtype = (attr['subtype'] ?? 'manga')
                .toString()
                .toUpperCase();

            items.add(
              Manga(
                id: 'cmk_title_${Uri.encodeComponent(title)}',
                source: MangaSourceType.comick,
                title: title,
                description: desc,
                status: (attr['status'] ?? 'current').toString().toUpperCase(),
                directCoverUrl: coverSmall,
                directHighResCoverUrl: coverLarge,
                tags: ['Catálogo Kitsu', subtype],
                isNsfw: rating.needsSensitiveMode,
                contentRatingKnown: rating != ContentRating.unknown,
                updatedAt:
                    DateTime.tryParse(attr['updatedAt']?.toString() ?? '') ??
                    DateTime.fromMillisecondsSinceEpoch(0),
                availableChaptersCount: chCount,
              ),
            );
          }
          return PaginatedSourceResponse(
            items: items,
            nextCursor: cursor + limit,
            hasMore: decoded['links']?['next'] != null,
          );
        }
      }
    } catch (_) {}

    // 2. Fallback para MangaDex Multi-Idioma
    const int limit = 20;
    final buf = StringBuffer(
      'https://api.mangadex.org/manga?limit=$limit&offset=$cursor',
    );
    buf.write('&includes[]=cover_art&hasAvailableChapters=true');
    buf.write('&contentRating[]=safe&contentRating[]=suggestive');
    if (filter.query.trim().isNotEmpty) {
      buf.write('&title=${Uri.encodeQueryComponent(filter.query.trim())}');
    }
    buf.write(filter.sort.mangaDexOrder);

    final response = await MangaDexService.safeHttpGet(buf.toString());
    final data = jsonDecode(response.body);
    final List list = data['data'] ?? [];
    final items = list.map((json) {
      final base = Manga.fromJson(json, overrideSource: MangaSourceType.comick);
      return Manga(
        id: 'cmk_mdx_${base.id}',
        source: MangaSourceType.comick,
        title: base.title,
        description: base.description,
        status: base.status,
        coverFileName: base.coverFileName,
        tags: ['Resultado MangaDex', ...base.tags.take(4)],
        isNsfw: base.isNsfw,
        updatedAt: base.updatedAt,
        availableChaptersCount: base.availableChaptersCount,
      );
    }).toList();

    return PaginatedSourceResponse(
      items: items,
      nextCursor: cursor + limit,
      hasMore: items.length >= limit,
    );
  }
}

// ============================================================================
// ADAPTER 5: MARVEL • DC • COMICS & HQs (QUADRINHOS REAIS COM CAPAS VÁLIDAS)
// ============================================================================
class WesternComicsHqAdapter implements IMangaSourceAdapter {
  @override
  MangaSourceType get sourceType => MangaSourceType.comicsHq;

  static const List<String> _marvelKeywords = [
    'Spider-Man',
    'Deadpool',
    'X-Men',
    'Avengers',
    'Wolverine',
    'Venom',
    'Iron Man',
  ];

  static const List<String> _dcKeywords = [
    'Batman',
    'Superman',
    'Justice League',
    'Harley Quinn',
    'Joker',
    'Teen Titans',
  ];

  static const List<String> _generalHqKeywords = [
    'Spider-Man',
    'Batman',
    'Star Wars',
    'Deadpool',
    'Superman',
    'X-Men',
    'Avengers',
    'Cyberpunk',
    'The Witcher',
    'Sonic',
    'Transformers',
  ];

  @override
  Future<PaginatedSourceResponse> fetchCatalog({
    required YomiSearchFilter filter,
    required int cursor,
  }) async {
    final q = filter.query.trim();
    final bool wantMarvel = filter.includedTags.contains(
      CanonicalTag.marvelComics,
    );
    final bool wantDc = filter.includedTags.contains(CanonicalTag.dcComics);
    final bool wantIndie = filter.includedTags.contains(
      CanonicalTag.westernIndieHq,
    );

    List<String> keywords = _generalHqKeywords;

    if (wantMarvel && !wantDc) {
      keywords = _marvelKeywords;
    } else if (wantDc && !wantMarvel) {
      keywords = _dcKeywords;
    } else if (wantIndie) {
      keywords = ['Star Wars', 'Cyberpunk', 'The Witcher', 'Sonic', 'Avatar'];
    }

    final int kwIndex = cursor ~/ 16;
    if (q.isEmpty && kwIndex >= keywords.length) {
      return const PaginatedSourceResponse(
        items: [],
        nextCursor: 0,
        hasMore: false,
      );
    }
    final String activeSearch = q.isNotEmpty ? q : keywords[kwIndex];
    final int apiOffset = q.isNotEmpty ? cursor : 0;

    final buf = StringBuffer(
      'https://api.mangadex.org/manga?limit=16&offset=$apiOffset'
      '&includes[]=cover_art&hasAvailableChapters=true'
      '&contentRating[]=safe&contentRating[]=suggestive'
      '&title=${Uri.encodeQueryComponent(activeSearch)}'
      '${filter.sort.mangaDexOrder}',
    );

    final items = <Manga>[];

    Map<String, dynamic> data;
    try {
      final response = await MangaDexService.safeHttpGet(buf.toString());
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      if (items.isEmpty) rethrow;
      return PaginatedSourceResponse(
        items: items,
        nextCursor: cursor,
        hasMore: false,
      );
    }
    final List list = data['data'] ?? [];

    for (final entry in list) {
      if (entry is! Map) continue;
      final base = Manga.fromJson(
        Map<String, dynamic>.from(entry),
        overrideSource: MangaSourceType.comicsHq,
      );
      items.add(
        Manga(
          id: 'hq_mdx_${base.id}',
          source: MangaSourceType.comicsHq,
          title: base.title,
          description: base.description,
          status: base.status,
          coverFileName: base.coverFileName,
          tags: ['Resultado MangaDex', ...base.tags.take(5)],
          isNsfw: base.isNsfw,
          updatedAt: base.updatedAt,
          availableChaptersCount: base.availableChaptersCount,
        ),
      );
    }

    return PaginatedSourceResponse(
      items: items,
      nextCursor: cursor + 16,
      hasMore: q.isEmpty
          ? (kwIndex + 1 < keywords.length)
          : (cursor + 16) < (data['total'] as num? ?? 0),
    );
  }
}

// ============================================================================
// ADAPTER 6: FONTE ADULTA 18+ (DESATIVADA POR PADRÃO, ATIVÁVEL EM AJUSTES)
// ============================================================================
class AdultVaultAdapter implements IMangaSourceAdapter {
  @override
  MangaSourceType get sourceType => MangaSourceType.adultSource;

  @override
  Future<PaginatedSourceResponse> fetchCatalog({
    required YomiSearchFilter filter,
    required int cursor,
  }) async {
    if (!filter.allowNsfw) {
      return const PaginatedSourceResponse(
        items: [],
        nextCursor: 0,
        hasMore: false,
      );
    }

    const int limit = 16;
    final buf = StringBuffer(
      'https://api.mangadex.org/manga?limit=$limit&offset=$cursor',
    );
    buf.write('&includes[]=cover_art&hasAvailableChapters=true');
    buf.write('&contentRating[]=pornographic&contentRating[]=erotica');

    for (final tag in filter.includedTags) {
      if (tag.mangadexUuid != null) {
        buf.write('&includedTags[]=${tag.mangadexUuid}');
      }
      if (tag.mangadexLang != null) {
        buf.write('&originalLanguage[]=${tag.mangadexLang}');
      }
      if (tag.mangadexDemographic != null) {
        buf.write('&publicationDemographic[]=${tag.mangadexDemographic}');
      }
    }
    for (final tag in filter.excludedTags) {
      if (tag.mangadexUuid != null) {
        buf.write('&excludedTags[]=${tag.mangadexUuid}');
      }
    }
    if (filter.query.trim().isNotEmpty) {
      buf.write('&title=${Uri.encodeQueryComponent(filter.query.trim())}');
    }
    buf.write(filter.sort.mangaDexOrder);

    final response = await MangaDexService.safeHttpGet(buf.toString());

    final data = jsonDecode(response.body);
    final List list = data['data'] ?? [];
    final int total = data['total'] ?? 0;

    final excludedLanguages = filter.excludedTags
        .map((tag) => tag.mangadexLang)
        .whereType<String>()
        .toSet();
    final excludedDemographics = filter.excludedTags
        .map((tag) => tag.mangadexDemographic)
        .whereType<String>()
        .toSet();

    final items = <Manga>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final json = Map<String, dynamic>.from(entry);
      final attributes = json['attributes'];
      if (attributes is Map) {
        if (excludedLanguages.contains(attributes['originalLanguage']) ||
            excludedDemographics.contains(
              attributes['publicationDemographic'],
            )) {
          continue;
        }
      }
      items.add(
        Manga.fromJson(
          json,
          overrideSource: MangaSourceType.adultSource,
          forceNsfwFlag: true,
        ),
      );
    }

    return PaginatedSourceResponse(
      items: items,
      nextCursor: cursor + limit,
      hasMore: (cursor + limit) < total,
    );
  }
}

// ============================================================================
// ORQUESTRADOR MULTI-FONTE INTELIGENTE (6 FONTES + CACHE DE UUID + ANTI-CORS)
// ============================================================================
class MangaDexService {
  static const String _baseUrl = 'https://api.mangadex.org';
  static final Map<String, String> _resolvedTitleUuidCache = {};
  static final Map<String, String> _resolvedTitleCoverCache = {};

  /// Recupera automaticamente a capa oficial em alta definição via AniList GraphQL (100% CORS nativo)
  /// caso a URL primária de qualquer obra falhe no Chrome, Windows ou Android!
  static Future<String?> resolveCoverUrlByTitle(String title) async {
    final cleanKey = title.toLowerCase().trim();
    if (cleanKey.isEmpty) return null;
    if (_resolvedTitleCoverCache.containsKey(cleanKey)) {
      return _resolvedTitleCoverCache[cleanKey];
    }
    try {
      final gql =
          'query { Media(search: ${jsonEncode(title)}, type: MANGA) { coverImage { extraLarge large } } }';
      final res = await ObservedHttp.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'query': gql}),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final cover = data['data']?['Media']?['coverImage'];
        final String? url = (cover?['large'] ?? cover?['extraLarge'])
            ?.toString();
        if (url != null && url.isNotEmpty) {
          _resolvedTitleCoverCache[cleanKey] = url;
          return url;
        }
      }
    } catch (_) {}
    return null;
  }

  static Map<String, String> get headers => kIsWeb
      ? const {}
      : const {
          'User-Agent': 'YomiReaderAndroid/7.0 (Personal Use; Flutter)',
          'Accept': 'application/json',
        };

  @visibleForTesting
  static Duration httpRetryBaseDelay = const Duration(milliseconds: 300);

  static Duration _computeRetryDelay(
    http.Response? res,
    int attemptIndex,
  ) {
    if (res != null && res.statusCode == 429) {
      final retryAfterRaw = res.headers['retry-after'] ?? res.headers['Retry-After'];
      final secs = int.tryParse(retryAfterRaw?.trim() ?? '');
      if (secs != null && secs >= 0) {
        final cappedMs = (secs * 1000).clamp(50, 3500);
        if (httpRetryBaseDelay.inMilliseconds < 50) {
          return httpRetryBaseDelay;
        }
        return Duration(milliseconds: cappedMs);
      }
    }
    return httpRetryBaseDelay * (1 << attemptIndex);
  }

  /// Executa GET resiliente com retry e backoff para HTTP 429 / 502 / 503 / 504:
  /// - No Android / Windows Desktop (!kIsWeb): chamada direta nativa.
  /// - No Chrome Web (kIsWeb): usa túnel JSON AllOrigins (/get) + CodeTabs + tentativa direta.
  static Future<http.Response> safeHttpGet(String rawUrl) async {
    if (!kIsWeb) {
      const maxAttempts = 3;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          final directRes = await ObservedHttp.get(
            Uri.parse(rawUrl),
            headers: headers,
          ).timeout(const Duration(seconds: 8));
          if (directRes.statusCode == 200) return directRes;

          final retryable =
              directRes.statusCode == 429 ||
              directRes.statusCode == 502 ||
              directRes.statusCode == 503 ||
              directRes.statusCode == 504;
          if (!retryable || attempt == maxAttempts - 1) {
            throw Exception('HTTP ${directRes.statusCode}');
          }
          await Future<void>.delayed(_computeRetryDelay(directRes, attempt));
        } on TimeoutException {
          if (attempt == maxAttempts - 1 || DeviceStateService.instance.isOffline) {
            rethrow;
          }
          await Future<void>.delayed(_computeRetryDelay(null, attempt));
        }
      }
      throw Exception('Falha de conexão na fonte');
    }

    // 1. Tenta AllOrigins JSON envelope (/get?url=...) que sempre envia Access-Control-Allow-Origin: *
    try {
      final aoUri = Uri.parse(
        'https://api.allorigins.win/get?url=${Uri.encodeComponent(rawUrl)}',
      );
      final aoRes = await ObservedHttp.get(
        aoUri,
      ).timeout(const Duration(seconds: 8));
      if (aoRes.statusCode == 200) {
        final wrapper = jsonDecode(aoRes.body);
        final String? contents = wrapper['contents']?.toString();
        if (contents != null && contents.trim().startsWith('{')) {
          return http.Response.bytes(
            utf8.encode(contents),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
      }
    } catch (_) {}

    // 2. Outros espelhos CORS + tentativa direta
    final webFallbacks = [
      'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(rawUrl)}',
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent(rawUrl)}',
      rawUrl,
    ];
    for (final candidate in webFallbacks) {
      try {
        final res = await ObservedHttp.get(
          Uri.parse(candidate),
        ).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200 && res.body.trim().startsWith('{')) {
          return res;
        }
      } catch (_) {}
    }

    throw Exception('Falha de conexão na fonte');
  }

  static final List<IMangaSourceAdapter> _adapters = [
    MangaDexAdapter(),
    AniListGraphQLAdapter(),
    JikanMalAdapter(),
    ComicKPlusAdapter(),
    WesternComicsHqAdapter(),
    AdultVaultAdapter(),
  ];

  static final Map<MangaSourceType, SourceCircuitBreaker> _breakers = {
    for (final s in MangaSourceType.values) s: SourceCircuitBreaker(),
  };

  static final Map<MangaSourceType, int> _cursors = {
    for (final s in MangaSourceType.values) s: 0,
  };

  static final Map<MangaSourceType, bool> _hasMore = {
    for (final s in MangaSourceType.values) s: true,
  };

  static final List<Manga> _lookaheadBuffer = [];
  static final Set<String> _seenIds = {};
  static final ValueNotifier<String?> sourceStatusBanner = ValueNotifier(null);

  // Invalidates in-flight catalog requests when search or filters change.
  static int _catalogGeneration = 0;
  static String? _activeQuery;

  static void resetAggregator() {
    _catalogGeneration++;
    _activeQuery = null;
    _lookaheadBuffer.clear();
    _seenIds.clear();
    sourceStatusBanner.value = null;
    for (final a in _adapters) {
      _cursors[a.sourceType] = 0;
      _hasMore[a.sourceType] = true;
    }
  }

  static Future<List<Manga>> fetchPopularMangas({
    int limit = 12,
    bool includeNsfw = false,
  }) async {
    final res = await MangaDexAdapter().fetchCatalog(
      filter: YomiSearchFilter(
        sort: CatalogSort.popular,
        allowNsfw: includeNsfw,
      ),
      cursor: 0,
    );
    return res.items.take(limit).toList();
  }

  static Future<List<Manga>> fetchMergedCatalog({
    required YomiSearchFilter filter,
    bool reset = false,
    int pageSize = 24,
  }) async {
    final query = filter.query.trim();
    if (reset || query != _activeQuery) {
      resetAggregator();
      _activeQuery = query;
    }
    final generation = _catalogGeneration;

    final eligible = _adapters.where((a) {
      if (a.sourceType == MangaSourceType.adultSource && !filter.allowNsfw) {
        return false;
      }
      if (!filter.enabledSources.contains(a.sourceType)) {
        return false;
      }
      return (_hasMore[a.sourceType] ?? true) &&
          !(_breakers[a.sourceType]?.isOpen ?? false);
    }).toList();

    if (eligible.isEmpty &&
        _lookaheadBuffer.isEmpty &&
        filter.enabledSources.any(
          (source) => _breakers[source]?.isOpen ?? false,
        )) {
      sourceStatusBanner.value =
          'As fontes estão temporariamente indisponíveis. Aguarde e tente novamente.';
    }
    if (eligible.isNotEmpty) {
      var successful = 0;
      final futures = eligible.map((adapter) async {
        final type = adapter.sourceType;
        final cursor = _cursors[type] ?? 0;
        final breaker = _breakers[type]!;
        try {
          // Metadata-only sources must not hold the entire search screen
          // hostage on high-latency mobile networks. MangaDex remains the
          // primary readable source and keeps its normal request timeout.
          final request = adapter.fetchCatalog(filter: filter, cursor: cursor);
          final res =
              type == MangaSourceType.mangadex ||
                  type == MangaSourceType.adultSource
              ? await request
              : await request.timeout(const Duration(seconds: 5));
          if (generation != _catalogGeneration) return <Manga>[];
          successful++;
          breaker.recordSuccess();
          _cursors[type] = res.nextCursor;
          _hasMore[type] = res.hasMore;
          return res.items;
        } catch (e) {
          if (generation != _catalogGeneration) return <Manga>[];
          final is429 = e.toString().contains('429');
          breaker.recordFailure(statusCode: is429 ? 429 : 500);
          return <Manga>[];
        }
      });

      final results = await Future.wait(futures);
      if (generation != _catalogGeneration) return <Manga>[];
      sourceStatusBanner.value = successful == 0
          ? 'Não foi possível consultar as fontes. Verifique sua conexão e tente novamente.'
          : null;
      // Interleave provider rankings; chapter count is not popularity.
      final maxLength = results.fold<int>(
        0,
        (n, list) => list.length > n ? list.length : n,
      );
      for (var rank = 0; rank < maxLength; rank++) {
        for (final list in results) {
          if (rank >= list.length) continue;
          final manga = list[rank];
          if (_seenIds.add(manga.compositeId)) {
            _lookaheadBuffer.add(manga);
          }
        }
      }
    }

    if (!filter.allowNsfw) {
      _lookaheadBuffer.removeWhere((m) => m.isNsfw);
    }
    if (filter.hideZeroChapters) {
      _lookaheadBuffer.removeWhere((m) => m.isCoverOnly);
    }

    // AGRUPAMENTO INTELIGENTE POR TÍTULO (Eleição automática da fonte com MAIS CAPÍTULOS)
    final Map<String, List<Manga>> groupedByTitle = {};
    for (final m in _lookaheadBuffer) {
      final key = m.normalizedTitleKey;
      if (key.length < 3) {
        groupedByTitle[m.compositeId] = [m];
      } else {
        groupedByTitle.putIfAbsent(key, () => []).add(m);
      }
    }

    final List<Manga> consolidated = [];
    for (final group in groupedByTitle.values) {
      if (group.length == 1) {
        consolidated.add(group.first);
      } else {
        // Prefer a genuine MangaDex catalog entry over metadata-only
        // providers. A chapter count reported by AniList or MAL is not
        // evidence that pages can be read inside YOMI.
        group.sort((a, b) {
          final aReadable =
              a.source == MangaSourceType.mangadex ||
              a.source == MangaSourceType.adultSource;
          final bReadable =
              b.source == MangaSourceType.mangadex ||
              b.source == MangaSourceType.adultSource;
          if (aReadable != bReadable) return aReadable ? -1 : 1;
          return b.availableChaptersCount.compareTo(a.availableChaptersCount);
        });
        final primary = group.first;
        final alternatives = group.sublist(1);
        consolidated.add(primary.copyWith(alternativeSources: alternatives));
      }
    }

    // Popularity keeps the interleaved native rankings, without inventing
    // a comparable popularity score between unrelated providers.
    if (filter.sort != CatalogSort.popular) {
      consolidated.sort((a, b) {
        if (filter.sort == CatalogSort.latest) {
          final date = b.updatedAt.compareTo(a.updatedAt);
          if (date != 0) return date;
        }
        final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return title != 0 ? title : a.compositeId.compareTo(b.compositeId);
      });
    }

    _lookaheadBuffer
      ..clear()
      ..addAll(consolidated);

    final takeCount = _lookaheadBuffer.length >= pageSize
        ? pageSize
        : _lookaheadBuffer.length;
    final slice = _lookaheadBuffer.sublist(0, takeCount);
    _lookaheadBuffer.removeRange(0, takeCount);
    return slice;
  }

  static String _cleanMangaDexUuid(String rawId) {
    return rawId
        .replaceFirst('cmk_mdx_', '')
        .replaceFirst('hq_mdx_', '')
        .replaceFirst('ani_mdx_', '')
        .replaceFirst('mal_mdx_', '')
        .replaceFirst('cmk_title_', '');
  }

  /// Resolve um título vindo do AniList, MyAnimeList ou Kitsu para o UUID real de leitura (com cache em memória!)
  static Future<({String? uuid, bool networkError})>
  _resolveMangaDexUuidByTitleWithStatus(String title) async {
    final normKey = title.toLowerCase().trim();
    if (_resolvedTitleUuidCache.containsKey(normKey)) {
      return (uuid: _resolvedTitleUuidCache[normKey], networkError: false);
    }

    try {
      final url =
          '$_baseUrl/manga?limit=5&title=${Uri.encodeQueryComponent(title)}'
          '&hasAvailableChapters=true&order[followedCount]=desc';
      final res = await safeHttpGet(url);
      final data = jsonDecode(res.body);
      final List list = data['data'] ?? [];
      // A text search is fuzzy. Never attach chapters from an unrelated
      // title just because MangaDex returned it first.
      String normalizeTitle(String value) => normalizeMangaTitle(value);
      final requested = normalizeTitle(title);
      if (requested.isEmpty) return (uuid: null, networkError: false);
      for (final entry in list) {
        if (entry is! Map) continue;
        final attributes = entry['attributes'];
        if (attributes is! Map) continue;
        final candidates = <String>[];
        final localizedTitles = attributes['title'];
        if (localizedTitles is Map) {
          candidates.addAll(localizedTitles.values.whereType<String>());
        }
        final alternativeTitles = attributes['altTitles'];
        if (alternativeTitles is List) {
          for (final alternative in alternativeTitles) {
            if (alternative is Map) {
              candidates.addAll(alternative.values.whereType<String>());
            }
          }
        }
        if (!candidates.any(
          (candidate) => normalizeTitle(candidate) == requested,
        )) {
          continue;
        }
        final foundId = entry['id']?.toString();
        if (foundId != null && foundId.isNotEmpty) {
          _resolvedTitleUuidCache[normKey] = foundId;
          return (uuid: foundId, networkError: false);
        }
      }
      return (uuid: null, networkError: false);
    } catch (_) {
      return (uuid: null, networkError: true);
    }
  }

  static final Map<String, bool> _olderChapterPages = {};

  static bool hasOlderChapters(String mangaId) =>
      _olderChapterPages[mangaId] ?? false;

  static Future<Map<MangaSourceType, List<Chapter>>> discoverAllSourcesForManga(
    Manga manga, {
    int offset = 0,
    bool? includeSpanishFallback,
  }) async {
    final Map<MangaSourceType, List<Chapter>> sourceChaptersMap = {};
    if (DeviceStateService.instance.isOffline) {
      _olderChapterPages[manga.id] = false;
      return {
        manga.source: StorageService.getOfflineOrCachedChapters(manga.id),
      };
    }

    // HQs do Vault não possuem UUID do MangaDex. A tela de detalhes usa
    // este método diretamente, sem passar por fetchChapters.
    if (manga.source == MangaSourceType.comicsHq &&
        manga.id.startsWith('tg_')) {
      final catalog = await TelegramVaultService.loadCatalog();
      final matches = catalog.where((item) => item.id == manga.id);
      final chapters = matches.isNotEmpty
          ? matches.first.preloadedChapters ?? <Chapter>[]
          : manga.preloadedChapters ??
                StorageService.getCachedMangaChapters(manga.id);
      _olderChapterPages[manga.id] = false;
      await StorageService.cacheMangaChapters(
        manga.id,
        chapters,
        titleKey: manga.normalizedTitleKey,
      );
      return {manga.source: offset == 0 ? chapters : <Chapter>[]};
    }

    // Only MangaDex IDs (including legacy MangaDex-backed entries) may be
    // used directly in the MangaDex chapter endpoint. AniList, MAL and Kitsu
    // identifiers belong to other services and must never be sent as UUIDs.
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    String? mangadexIdFor(Manga candidate) {
      final isMangaDexBacked =
          candidate.source == MangaSourceType.mangadex ||
          candidate.source == MangaSourceType.adultSource ||
          candidate.id.startsWith('cmk_mdx_') ||
          candidate.id.startsWith('hq_mdx_') ||
          candidate.id.startsWith('ani_mdx_') ||
          candidate.id.startsWith('mal_mdx_');
      if (!isMangaDexBacked) return null;
      final id = _cleanMangaDexUuid(candidate.id);
      return uuidPattern.hasMatch(id) ? id : null;
    }

    String? targetUuid = mangadexIdFor(manga);
    for (final alt in manga.alternativeSources) {
      targetUuid ??= mangadexIdFor(alt);
    }

    var titleLookupFailed = false;
    if (targetUuid == null) {
      final resolved = await _resolveMangaDexUuidByTitleWithStatus(manga.title);
      targetUuid = resolved.uuid;
      titleLookupFailed = resolved.networkError;
    }

    if (targetUuid == null || targetUuid.isEmpty) {
      if (titleLookupFailed) {
        final existing = StorageService.getOfflineOrCachedChapters(manga.id);
        if (existing.isNotEmpty) {
          return {manga.source: existing};
        }
        throw Exception('Falha temporária ao localizar capítulos da obra.');
      }
      await StorageService.cacheMangaChapters(
        manga.id,
        const [],
        titleKey: manga.normalizedTitleKey,
      );
      return {manga.source: []};
    }

    // Carregamento completo com preenchimento de lacunas (PT-BR -> EN -> ES),
    // paginação além de 1.500 capítulos e concorrência controlada (máx. 2 reqs).
    const int pageSize = 500;
    const int maxFeedOffsetPerLanguage = 2500;
    const int maxConcurrentPages = 2;

    Future<
      ({List<Chapter> chapters, int total, int rawCount, bool failed})
    > fetchFeedPage(
      List<String> langs, {
      required int reqOffset,
    }) async {
      try {
        final langParams = langs
            .map((l) => 'translatedLanguage[]=${Uri.encodeQueryComponent(l)}')
            .join('&');
        final url =
            '$_baseUrl/manga/$targetUuid/feed?limit=$pageSize&offset=$reqOffset'
            '&$langParams'
            '&includes[]=scanlation_group'
            '&order[chapter]=desc'
            '&includeExternalUrl=0';
        final response = await safeHttpGet(url);
        final data = jsonDecode(response.body);
        final List entries = data['data'] ?? [];
        final rawCount = entries.length;
        final total = (data['total'] as int?) ?? rawCount;
        final list = entries
            .whereType<Map<String, dynamic>>()
            .map(
              (entry) =>
                  Chapter.fromJson(entry, source: MangaSourceType.mangadex),
            )
            .where((ch) => ch.pages > 0)
            .toList();
        return (
          chapters: list,
          total: total,
          rawCount: rawCount,
          failed: false,
        );
      } catch (_) {
        return (
          chapters: <Chapter>[],
          total: 0,
          rawCount: 0,
          failed: true,
        );
      }
    }

    Future<
      ({List<Chapter> chapters, bool failed, bool hasMore, int total})
    > fetchAllPagesForLanguage(
      List<String> langs, {
      required int startOffset,
    }) async {
      final first = await fetchFeedPage(langs, reqOffset: startOffset);
      if (first.failed) {
        return (
          chapters: <Chapter>[],
          failed: true,
          hasMore: false,
          total: 0,
        );
      }

      final all = List<Chapter>.from(first.chapters);
      var coveredUntil = startOffset + first.rawCount;
      var partialFailure = false;

      if (startOffset == 0 && first.total > pageSize) {
        final extraOffsets = <int>[
          for (
            int nextOff = pageSize;
            nextOff < first.total && nextOff <= maxFeedOffsetPerLanguage;
            nextOff += pageSize
          )
            nextOff,
        ];
        for (var i = 0; i < extraOffsets.length; i += maxConcurrentPages) {
          final chunk = extraOffsets.sublist(
            i,
            (i + maxConcurrentPages).clamp(0, extraOffsets.length),
          );
          final chunkResults = await Future.wait([
            for (final off in chunk) fetchFeedPage(langs, reqOffset: off),
          ]);
          for (var j = 0; j < chunkResults.length; j++) {
            final res = chunkResults[j];
            if (res.failed) {
              partialFailure = true;
            } else {
              all.addAll(res.chapters);
              final end = chunk[j] + res.rawCount;
              if (end > coveredUntil) coveredUntil = end;
            }
          }
        }
      }

      final hasMore =
          partialFailure ||
          (startOffset == 0
              ? first.total > (maxFeedOffsetPerLanguage + pageSize)
              : coveredUntil < first.total);

      return (
        chapters: all,
        failed: false,
        hasMore: hasMore,
        total: first.total,
      );
    }

    final ptRes = await fetchAllPagesForLanguage(
      const ['pt-br'],
      startOffset: offset,
    );
    final enRes = await fetchAllPagesForLanguage(
      const ['en'],
      startOffset: offset,
    );

    final useSpanish =
        includeSpanishFallback ?? StorageService.includeSpanishFallback;
    final esRes = useSpanish
        ? await fetchAllPagesForLanguage(
            const ['es', 'es-la'],
            startOffset: offset,
          )
        : (chapters: <Chapter>[], failed: false, hasMore: false, total: 0);

    final allFeedsFailed =
        ptRes.failed && enRes.failed && (!useSpanish || esRes.failed);
    final anyFeedFailed =
        ptRes.failed || enRes.failed || (useSpanish && esRes.failed);

    if (allFeedsFailed) {
      final fallbackCached = StorageService.getOfflineOrCachedChapters(
        manga.id,
      );
      if (fallbackCached.isNotEmpty) {
        return {manga.source: fallbackCached};
      }
      throw Exception(
        'Não foi possível consultar os capítulos no momento. Tente novamente.',
      );
    }

    final Map<String, Chapter> completeChapters = {};
    void mergeIntoComplete(List<Chapter> incoming) {
      for (final ch in incoming) {
        final key = ch.canonicalKey;
        if (key.isEmpty) continue;
        final existing = completeChapters[key];
        if (existing == null ||
            ch.languagePriority > existing.languagePriority ||
            (ch.languagePriority == existing.languagePriority &&
                ch.pages > existing.pages)) {
          completeChapters[key] = ch;
        }
      }
    }

    // Prioridade: PT-BR > EN > ES (espanhol preenche lacunas quando ativo)
    mergeIntoComplete(ptRes.chapters);
    mergeIntoComplete(enRes.chapters);
    if (useSpanish) {
      mergeIntoComplete(esRes.chapters);
    }

    final completeList = completeChapters.values.toList()
      ..sort((a, b) => b.numericChapter.compareTo(a.numericChapter));

    _olderChapterPages[manga.id] =
        ptRes.hasMore || enRes.hasMore || (useSpanish && esRes.hasMore);

    sourceChaptersMap[manga.source] = completeList;
    sourceChaptersMap[MangaSourceType.mangadex] = completeList;
    for (final alt in manga.alternativeSources) {
      sourceChaptersMap.putIfAbsent(alt.source, () => completeList);
    }

    // Grava no cache somente se encontrou capítulos ou se TODAS as consultas
    // retornaram com sucesso confirmado (evitando marcar 0 capítulos em erro parcial).
    if (offset == 0 && (completeList.isNotEmpty || !anyFeedFailed)) {
      final cached = StorageService.getCachedMangaChapters(manga.id);
      final seen = completeList.map((ch) => ch.id).toSet();
      await StorageService.cacheMangaChapters(manga.id, [
        ...completeList,
        ...cached.where((ch) => seen.add(ch.id)),
      ], titleKey: manga.normalizedTitleKey);
    }

    return sourceChaptersMap;
  }

  static Future<List<Chapter>> fetchChapters(Manga manga) async {
    if (DeviceStateService.instance.isOffline) {
      return StorageService.getDownloadedChaptersForManga(manga.id);
    }
    if (manga.preloadedChapters != null &&
        manga.preloadedChapters!.isNotEmpty) {
      await StorageService.cacheMangaChapters(
        manga.id,
        manga.preloadedChapters!,
      );
      return manga.preloadedChapters!;
    }

    final map = await discoverAllSourcesForManga(manga);
    return map[manga.source] ??
        (map.values.isNotEmpty ? map.values.first : <Chapter>[]);
  }

  static Future<ChapterPagesData> fetchChapterPages(Chapter chapter) async {
    if (chapter.source == MangaSourceType.comicsHq &&
        chapter.id.startsWith('tg_ch_')) {
      throw UnsupportedError(
        'A leitura deste formato de HQ ainda não está disponível.',
      );
    }
    if (chapter.directPageUrls != null && chapter.directPageUrls!.isNotEmpty) {
      return ChapterPagesData(
        baseUrl: '',
        hash: '',
        hdFiles: const [],
        dataSaverFiles: const [],
        directUrls: chapter.directPageUrls,
      );
    }

    final cleanChapterId = chapter.id
        .replaceFirst('cmk_mdx_', '')
        .replaceFirst('hq_mdx_', '')
        .replaceFirst('ani_mdx_', '')
        .replaceFirst('mal_mdx_', '');
    final url = '$_baseUrl/at-home/server/$cleanChapterId?forcePort443=true';
    final response = await safeHttpGet(url);

    final data = jsonDecode(response.body);
    final ch = data['chapter'];
    return ChapterPagesData(
      baseUrl: data['baseUrl'],
      hash: ch['hash'],
      hdFiles: List<String>.from(ch['data'] ?? []),
      dataSaverFiles: List<String>.from(ch['dataSaver'] ?? []),
    );
  }
}
