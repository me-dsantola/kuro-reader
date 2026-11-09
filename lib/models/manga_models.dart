enum MangaSourceType {
  mangadex('MDX', 'MangaDex'),
  adultSource('18+', 'Yomi Adult');

  final String badge;
  final String label;
  const MangaSourceType(this.badge, this.label);

  static MangaSourceType fromName(String? name) {
    if (name == 'adultSource') return MangaSourceType.adultSource;
    return MangaSourceType.mangadex;
  }
}

enum NsfwDisplayMode {
  hidden('Seguro (Ocultar 18+)'),
  blurred('Sakura Blur (Borrar 18+)'),
  visible('Liberado (Exibir 18+)');

  final String label;
  const NsfwDisplayMode(this.label);

  bool get allowNsfwFetch => this != NsfwDisplayMode.hidden;

  static NsfwDisplayMode fromName(String? name) {
    return NsfwDisplayMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => NsfwDisplayMode.blurred,
    );
  }
}

enum CanonicalTag {
  action(
    label: 'Ação',
    isNsfwOnly: false,
    mangadexUuid: '391b0423-d847-456f-aff0-8b0cfc03066b',
    adultSlug: 'action',
  ),
  romance(
    label: 'Romance',
    isNsfwOnly: false,
    mangadexUuid: '423e2eae-a7a2-4a8b-ac03-a8351462d71d',
    adultSlug: 'romance',
  ),
  fantasy(
    label: 'Fantasia',
    isNsfwOnly: false,
    mangadexUuid: 'cdc58593-87dd-415e-bbc0-2ec27bf404cc',
    adultSlug: 'fantasy',
  ),
  comedy(
    label: 'Comédia',
    isNsfwOnly: false,
    mangadexUuid: '4d32cc48-9f00-4cca-9b5a-a839f0764984',
    adultSlug: 'comedy',
  ),
  drama(
    label: 'Drama',
    isNsfwOnly: false,
    mangadexUuid: 'b9af3a63-f058-46de-a9a0-e0c13906197a',
    adultSlug: 'drama',
  ),
  isekai(
    label: 'Isekai',
    isNsfwOnly: false,
    mangadexUuid: 'ace04997-f6bd-436e-b261-779182193d3d',
    adultSlug: 'isekai',
  ),
  fullColor(
    label: 'Colorido',
    isNsfwOnly: false,
    mangadexUuid: 'f5ba408b-0e7a-484d-8d49-4e9125ac96de',
    adultSlug: 'full color',
  ),
  yuri(
    label: 'Yuri / GL',
    isNsfwOnly: false,
    mangadexUuid: 'a3c67850-4684-404e-9b7f-c69850ee5da6',
    adultSlug: 'yuri',
  ),
  uncensored(
    label: 'Sem Censura (18+)',
    isNsfwOnly: true,
    mangadexUuid: null,
    adultSlug: 'uncensored',
  ),
  vanilla(
    label: 'Vanilla (18+)',
    isNsfwOnly: true,
    mangadexUuid: '423e2eae-a7a2-4a8b-ac03-a8351462d71d',
    adultSlug: 'vanilla',
  ),
  netorare(
    label: 'NTR (18+)',
    isNsfwOnly: true,
    mangadexUuid: null,
    adultSlug: 'netorare',
  );

  final String label;
  final bool isNsfwOnly;
  final String? mangadexUuid;
  final String? adultSlug;

  const CanonicalTag({
    required this.label,
    required this.isNsfwOnly,
    required this.mangadexUuid,
    required this.adultSlug,
  });
}

class YomiSearchFilter {
  final String query;
  final Set<CanonicalTag> includedTags;
  final Set<CanonicalTag> excludedTags;
  final bool allowNsfw;
  final bool sortByLatest;

  const YomiSearchFilter({
    this.query = '',
    this.includedTags = const {},
    this.excludedTags = const {},
    this.allowNsfw = true,
    this.sortByLatest = true,
  });
}

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
  final DateTime updatedAt;
  final Map<String, String> customHeaders;
  final List<Chapter>? preloadedChapters;

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
    DateTime? updatedAt,
    this.customHeaders = const {
      'User-Agent': 'YomiReader/1.0 (Android; Flutter)',
      'Accept': 'application/json',
    },
    this.preloadedChapters,
  }) : updatedAt = updatedAt ?? DateTime.now();

  String get compositeId => '${source.name}_$id';

  String getCoverUrl({bool highRes = false}) {
    if (highRes && directHighResCoverUrl != null && directHighResCoverUrl!.isNotEmpty) {
      return directHighResCoverUrl!;
    }
    if (directCoverUrl != null && directCoverUrl!.isNotEmpty) {
      return directCoverUrl!;
    }
    if (coverFileName == null) {
      return 'https://via.placeholder.com/512x720.png?text=YOMI';
    }
    final suffix = highRes ? '.512.jpg' : '.256.jpg';
    return 'https://uploads.mangadex.org/covers/$id/$coverFileName$suffix';
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
        'updatedAt': updatedAt.toIso8601String(),
        'customHeaders': customHeaders,
        'preloadedChapters': preloadedChapters?.map((c) => c.toMap()).toList(),
      };

  factory Manga.fromMap(Map<String, dynamic> map) {
    final rawPreloaded = map['preloadedChapters'] as List?;
    return Manga(
      id: map['id'] ?? '',
      source: MangaSourceType.fromName(map['source']?.toString()),
      title: map['title'] ?? 'Sem Título',
      description: map['description'] ?? '',
      status: map['status'] ?? 'PUBLICADO',
      coverFileName: map['coverFileName'],
      directCoverUrl: map['directCoverUrl'],
      directHighResCoverUrl: map['directHighResCoverUrl'],
      tags: List<String>.from(map['tags'] ?? []),
      isNsfw: map['isNsfw'] == true,
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      customHeaders: map['customHeaders'] != null
          ? Map<String, String>.from(map['customHeaders'] as Map)
          : const {'User-Agent': 'YomiReader/1.0 (Android; Flutter)'},
      preloadedChapters: rawPreloaded
          ?.map((e) => Chapter.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  factory Manga.fromJson(
    Map<String, dynamic> json, {
    MangaSourceType overrideSource = MangaSourceType.mangadex,
    bool forceNsfwFlag = false,
  }) {
    final attributes = json['attributes'] ?? {};

    final titleMap = Map<String, dynamic>.from(attributes['title'] ?? {});
    String resolvedTitle = titleMap['pt-br'] ??
        titleMap['en'] ??
        titleMap['ja-ro'] ??
        (titleMap.values.isNotEmpty ? titleMap.values.first.toString() : 'Sem Título');

    final descMap = Map<String, dynamic>.from(attributes['description'] ?? {});
    String resolvedDesc = descMap['pt-br'] ??
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
        .take(6)
        .toList();

    String? coverFile;
    final relationships = (json['relationships'] as List?) ?? [];
    for (final rel in relationships) {
      if (rel['type'] == 'cover_art' && rel['attributes'] != null) {
        coverFile = rel['attributes']['fileName'];
        break;
      }
    }

    final String rating = (attributes['contentRating'] ?? 'safe').toString();
    final bool isNsfw =
        forceNsfwFlag || rating == 'erotica' || rating == 'pornographic';

    final DateTime updated =
        DateTime.tryParse(attributes['updatedAt']?.toString() ?? '') ??
            DateTime.now();

    return Manga(
      id: json['id'],
      source: overrideSource,
      title: resolvedTitle,
      description: resolvedDesc,
      status: (attributes['status'] ?? 'ongoing').toString().toUpperCase(),
      coverFileName: coverFile,
      tags: parsedTags,
      isNsfw: isNsfw,
      updatedAt: updated,
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

  Chapter({
    required this.id,
    this.source = MangaSourceType.mangadex,
    required this.chapterNumber,
    required this.title,
    required this.language,
    required this.pages,
    this.scanlator = 'Scan Oficial / Comunidade',
    this.directPageUrls,
  });

  double get numericChapter => double.tryParse(chapterNumber) ?? 999999.0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'source': source.name,
        'chapterNumber': chapterNumber,
        'title': title,
        'language': language,
        'pages': pages,
        'scanlator': scanlator,
        'directPageUrls': directPageUrls,
      };

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
        id: map['id'] ?? '',
        source: MangaSourceType.fromName(map['source']?.toString()),
        chapterNumber: map['chapterNumber'] ?? '?',
        title: map['title'] ?? 'Capítulo',
        language: map['language'] ?? 'PT-BR',
        pages: map['pages'] ?? 0,
        scanlator: map['scanlator'] ?? 'Comunidade',
        directPageUrls: map['directPageUrls'] != null
            ? List<String>.from(map['directPageUrls'] as List)
            : null,
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
        scanName = r['attributes']['name'] ?? 'Comunidade';
        break;
      }
    }

    return Chapter(
      id: json['id'],
      source: source,
      chapterNumber: (attr['chapter'] ?? '1').toString(),
      title: (attr['title'] != null && attr['title'].toString().trim().isNotEmpty)
          ? attr['title'].toString()
          : 'Capítulo ${attr['chapter'] ?? '1'}',
      language: (attr['translatedLanguage'] ?? 'en').toString().toUpperCase(),
      pages: attr['pages'] ?? 0,
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
      return directUrls!;
    }
    final folder = useDataSaver ? 'data-saver' : 'data';
    final files = useDataSaver ? dataSaverFiles : hdFiles;
    return files.map((f) => '$baseUrl/$folder/$hash/$f').toList();
  }
}
