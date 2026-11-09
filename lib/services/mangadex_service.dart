import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/manga_models.dart';
import 'storage_service.dart';

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

/// Circuit Breaker para proteger o app contra erros 429 (Rate Limit) ou quedas
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
      _openUntil = DateTime.now().add(const Duration(seconds: 60));
    } else if (_failures >= 3) {
      _openUntil = DateTime.now().add(const Duration(seconds: 45));
    }
  }
}

// ============================================================================
// ADAPTER 1: MANGADEX OFICIAL (GERAL + FILTRO DINÂMICO)
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
    if (filter.includedTags.any((t) => t.mangadexUuid == null)) {
      return const PaginatedSourceResponse(items: [], nextCursor: 0, hasMore: false);
    }

    const int limit = 20;
    final buf = StringBuffer('$_baseUrl/manga?limit=$limit&offset=$cursor');
    buf.write('&includes[]=cover_art&hasAvailableChapters=true');
    buf.write('&contentRating[]=safe&contentRating[]=suggestive');

    for (final tag in filter.includedTags) {
      if (tag.mangadexUuid != null) buf.write('&includedTags[]=${tag.mangadexUuid}');
    }
    for (final tag in filter.excludedTags) {
      if (tag.mangadexUuid != null) buf.write('&excludedTags[]=${tag.mangadexUuid}');
    }

    if (filter.query.trim().isNotEmpty) {
      buf.write('&title=${Uri.encodeQueryComponent(filter.query.trim())}');
    }

    if (filter.sortByLatest) {
      buf.write('&order[latestUploadedChapter]=desc');
    } else {
      buf.write('&order[followedCount]=desc');
    }

    final response = await http
        .get(Uri.parse(buf.toString()), headers: MangaDexService.headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final List list = data['data'] ?? [];
    final int total = data['total'] ?? 0;

    final items = list
        .map((json) => Manga.fromJson(json, overrideSource: MangaSourceType.mangadex))
        .toList();

    return PaginatedSourceResponse(
      items: items,
      nextCursor: cursor + limit,
      hasMore: (cursor + limit) < total,
    );
  }
}

// ============================================================================
// ADAPTER 2: FONTE ADULTA 18+ (GALERIAS DOUJIN / ACERVO HENTAI & EROTICA)
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
      return const PaginatedSourceResponse(items: [], nextCursor: 0, hasMore: false);
    }

    // 1. Tenta buscar na API de Galerias 18+ (nhentai JSON API)
    try {
      final int page = (cursor ~/ 20) + 1;
      final qParts = <String>[];
      if (filter.query.trim().isNotEmpty) qParts.add(filter.query.trim());
      for (final t in filter.includedTags) {
        if (t.adultSlug != null) qParts.add('tag:"${t.adultSlug}"');
      }
      for (final t in filter.excludedTags) {
        if (t.adultSlug != null) qParts.add('-tag:"${t.adultSlug}"');
      }

      final Uri nhUri = qParts.isEmpty
          ? Uri.parse('https://nhentai.net/api/galleries/all?page=$page')
          : Uri.parse(
              'https://nhentai.net/api/galleries/search?query=${Uri.encodeQueryComponent(qParts.join(" "))}&page=$page&sort=${filter.sortByLatest ? "date" : "popular"}',
            );

      final nhRes = await http.get(
        nhUri,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) YomiReader/1.0',
          'Referer': 'https://nhentai.net/',
        },
      ).timeout(const Duration(seconds: 4));

      if (nhRes.statusCode == 200) {
        final body = jsonDecode(nhRes.body);
        final List results = body['result'] ?? [];
        if (results.isNotEmpty) {
          final items = results.map<Manga>((json) {
            final String id = json['id'].toString();
            final String mediaId = json['media_id'].toString();
            final titleObj = json['title'] ?? {};
            final String title =
                (titleObj['pretty'] ?? titleObj['english'] ?? 'Doujin #$id')
                    .toString();
            final int epoch = json['upload_date'] ?? 0;
            final DateTime updated = epoch > 0
                ? DateTime.fromMillisecondsSinceEpoch(epoch * 1000)
                : DateTime.now();

            final List rawTags = json['tags'] ?? [];
            final parsedTags = rawTags
                .where((t) => t['type'] == 'tag' || t['type'] == 'parody')
                .map((t) => t['name'].toString())
                .take(6)
                .toList();

            final List pagesList = json['images']?['pages'] ?? [];
            final directUrls = <String>[];
            for (int i = 0; i < pagesList.length; i++) {
              final t = pagesList[i]['t'] ?? 'j';
              final ext = t == 'p' ? 'png' : (t == 'w' ? 'webp' : 'jpg');
              directUrls.add('https://i.nhentai.net/galleries/$mediaId/${i + 1}.$ext');
            }

            final virtualChapter = Chapter(
              id: 'nh_$id',
              source: MangaSourceType.adultSource,
              chapterNumber: '1',
              title: 'Galeria Completa (${directUrls.length} págs)',
              language: '18+',
              pages: directUrls.length,
              scanlator: 'Yomi Adult Gallery',
              directPageUrls: directUrls,
            );

            return Manga(
              id: 'nh_$id',
              source: MangaSourceType.adultSource,
              title: title,
              description: 'Galeria Adulta #$id • Tags: ${parsedTags.join(", ")}',
              status: 'COMPLETO',
              directCoverUrl: 'https://t.nhentai.net/galleries/$mediaId/thumb.jpg',
              directHighResCoverUrl: 'https://t.nhentai.net/galleries/$mediaId/cover.jpg',
              tags: parsedTags,
              isNsfw: true,
              updatedAt: updated,
              customHeaders: const {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 14) YomiReader/1.0',
                'Referer': 'https://nhentai.net/',
              },
              preloadedChapters: [virtualChapter],
            );
          }).toList();

          return PaginatedSourceResponse(
            items: items,
            nextCursor: cursor + 20,
            hasMore: true,
          );
        }
      }
    } catch (_) {
      // Fallback transparente caso o Cloudflare ou DNS da operadora bloqueie o domínio primário
    }

    // 2. Fallback Resiliente de Alta Disponibilidade: Stream dedicado 18+ (Pornographic & Erotica)
    const int limit = 16;
    final buf = StringBuffer('https://api.mangadex.org/manga?limit=$limit&offset=$cursor');
    buf.write('&includes[]=cover_art&hasAvailableChapters=true');
    buf.write('&contentRating[]=pornographic&contentRating[]=erotica');

    for (final tag in filter.includedTags) {
      if (tag.mangadexUuid != null) buf.write('&includedTags[]=${tag.mangadexUuid}');
    }
    for (final tag in filter.excludedTags) {
      if (tag.mangadexUuid != null) buf.write('&excludedTags[]=${tag.mangadexUuid}');
    }

    if (filter.query.trim().isNotEmpty) {
      buf.write('&title=${Uri.encodeQueryComponent(filter.query.trim())}');
    }

    if (filter.sortByLatest) {
      buf.write('&order[latestUploadedChapter]=desc');
    } else {
      buf.write('&order[followedCount]=desc');
    }

    final response = await http
        .get(Uri.parse(buf.toString()), headers: MangaDexService.headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('Adult Stream HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final List list = data['data'] ?? [];
    final int total = data['total'] ?? 0;

    final items = list
        .map((json) => Manga.fromJson(
              json,
              overrideSource: MangaSourceType.adultSource,
              forceNsfwFlag: true,
            ))
        .toList();

    return PaginatedSourceResponse(
      items: items,
      nextCursor: cursor + limit,
      hasMore: (cursor + limit) < total,
    );
  }
}

// ============================================================================
// ORQUESTRADOR PARALELO & SERVIÇO UNIFICADO YOMI
// ============================================================================
class MangaDexService {
  static const String _baseUrl = 'https://api.mangadex.org';

  static const Map<String, String> headers = {
    'User-Agent': 'YomiReaderAndroid/5.0 (Personal Use; Flutter)',
    'Accept': 'application/json',
  };

  static final List<IMangaSourceAdapter> _adapters = [
    MangaDexAdapter(),
    AdultVaultAdapter(),
  ];

  static final Map<MangaSourceType, SourceCircuitBreaker> _breakers = {
    MangaSourceType.mangadex: SourceCircuitBreaker(),
    MangaSourceType.adultSource: SourceCircuitBreaker(),
  };

  static final Map<MangaSourceType, int> _cursors = {
    MangaSourceType.mangadex: 0,
    MangaSourceType.adultSource: 0,
  };

  static final Map<MangaSourceType, bool> _hasMore = {
    MangaSourceType.mangadex: true,
    MangaSourceType.adultSource: true,
  };

  static final List<Manga> _lookaheadBuffer = [];
  static final Set<String> _seenIds = {};

  static final ValueNotifier<String?> sourceStatusBanner = ValueNotifier(null);

  static void resetAggregator() {
    _lookaheadBuffer.clear();
    _seenIds.clear();
    sourceStatusBanner.value = null;
    for (final a in _adapters) {
      _cursors[a.sourceType] = 0;
      _hasMore[a.sourceType] = true;
    }
  }

  /// Busca simultânea nas duas fontes, une arrays, remove duplicatas e ordena por data
  static Future<List<Manga>> fetchMergedCatalog({
    required YomiSearchFilter filter,
    bool reset = false,
    int pageSize = 24,
  }) async {
    if (reset) resetAggregator();

    final eligible = _adapters.where((a) {
      if (a.sourceType == MangaSourceType.adultSource && !filter.allowNsfw) {
        return false;
      }
      return (_hasMore[a.sourceType] ?? true) &&
          !(_breakers[a.sourceType]?.isOpen ?? false);
    }).toList();

    if (eligible.isNotEmpty) {
      final futures = eligible.map((adapter) async {
        final type = adapter.sourceType;
        final cursor = _cursors[type] ?? 0;
        final breaker = _breakers[type]!;

        try {
          final res = await adapter.fetchCatalog(filter: filter, cursor: cursor);
          breaker.recordSuccess();
          _cursors[type] = res.nextCursor;
          _hasMore[type] = res.hasMore;
          return res.items;
        } catch (e) {
          final is429 = e.toString().contains('429');
          breaker.recordFailure(statusCode: is429 ? 429 : 500);
          sourceStatusBanner.value =
              'Fonte ${type.label} instável • Exibindo resultados disponíveis.';
          return <Manga>[];
        }
      });

      final results = await Future.wait(futures);
      for (final list in results) {
        for (final manga in list) {
          if (_seenIds.add(manga.compositeId)) {
            _lookaheadBuffer.add(manga);
          }
        }
      }
    }

    if (!filter.allowNsfw) {
      _lookaheadBuffer.removeWhere((m) => m.isNsfw);
    }

    // Ordena cronologicamente pelos lançamentos/atualizações mais recentes
    _lookaheadBuffer.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final takeCount = _lookaheadBuffer.length >= pageSize
        ? pageSize
        : _lookaheadBuffer.length;
    final slice = _lookaheadBuffer.sublist(0, takeCount);
    _lookaheadBuffer.removeRange(0, takeCount);
    return slice;
  }

  /// Busca capítulos unificados (Suporta Virtual Chapter 18+ e MangaDex Feed)
  static Future<List<Chapter>> fetchChapters(Manga manga) async {
    if (manga.preloadedChapters != null && manga.preloadedChapters!.isNotEmpty) {
      await StorageService.cacheMangaChapters(manga.id, manga.preloadedChapters!);
      return manga.preloadedChapters!;
    }

    final fullUrl = '$_baseUrl/manga/${manga.id}/feed?limit=500'
        '&translatedLanguage[]=pt-br&translatedLanguage[]=en'
        '&includes[]=scanlation_group'
        '&order[chapter]=desc'
        '&includeExternalUrl=0';

    final response = await http.get(Uri.parse(fullUrl), headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List list = data['data'] ?? [];
      final rawChapters = list
          .map((json) => Chapter.fromJson(json, source: manga.source))
          .where((ch) => ch.pages > 0)
          .toList();

      final Map<String, Chapter> uniqueMap = {};
      for (final ch in rawChapters) {
        final key = '${ch.language}_${ch.chapterNumber}';
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = ch;
        }
      }

      final chapters = uniqueMap.values.toList();
      await StorageService.cacheMangaChapters(manga.id, chapters);
      return chapters;
    } else {
      throw Exception('Falha ao carregar capítulos (${response.statusCode})');
    }
  }

  /// Obtém URLs das páginas (Suporta URLs diretas do CDN 18+ ou MangaDex@Home)
  static Future<ChapterPagesData> fetchChapterPages(Chapter chapter) async {
    if (chapter.directPageUrls != null && chapter.directPageUrls!.isNotEmpty) {
      return ChapterPagesData(
        baseUrl: '',
        hash: '',
        hdFiles: const [],
        dataSaverFiles: const [],
        directUrls: chapter.directPageUrls,
      );
    }

    final url = Uri.parse('$_baseUrl/at-home/server/${chapter.id}');
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final ch = data['chapter'];
      return ChapterPagesData(
        baseUrl: data['baseUrl'],
        hash: ch['hash'],
        hdFiles: List<String>.from(ch['data'] ?? []),
        dataSaverFiles: List<String>.from(ch['dataSaver'] ?? []),
      );
    } else {
      throw Exception('Servidor de páginas indisponível');
    }
  }
}
