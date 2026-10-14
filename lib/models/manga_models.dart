class Manga {
  final String id;
  final String title;
  final String description;
  final String status;
  final String? coverFileName;
  final List<String> tags;

  Manga({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.coverFileName,
    required this.tags,
  });

  String getCoverUrl({bool highRes = false}) {
    if (coverFileName == null) {
      return 'https://via.placeholder.com/512x720.png?text=Sem+Capa';
    }
    final suffix = highRes ? '.512.jpg' : '.256.jpg';
    return 'https://uploads.mangadex.org/covers/$id/$coverFileName$suffix';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'status': status,
    'coverFileName': coverFileName,
    'tags': tags,
  };

  factory Manga.fromMap(Map<String, dynamic> map) => Manga(
    id: map['id'] ?? '',
    title: map['title'] ?? 'Sem Título',
    description: map['description'] ?? '',
    status: map['status'] ?? 'UNKNOWN',
    coverFileName: map['coverFileName'],
    tags: List<String>.from(map['tags'] ?? []),
  );

  factory Manga.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] ?? {};

    final titleMap = Map<String, dynamic>.from(attributes['title'] ?? {});
    String resolvedTitle =
        titleMap['pt-br'] ??
        titleMap['en'] ??
        titleMap['ja-ro'] ??
        (titleMap.values.isNotEmpty ? titleMap.values.first : 'Sem Título');

    final descMap = Map<String, dynamic>.from(attributes['description'] ?? {});
    String resolvedDesc =
        descMap['pt-br'] ??
        descMap['en'] ??
        (descMap.values.isNotEmpty
            ? descMap.values.first
            : 'Sinopse não disponível.');

    final rawTags = (attributes['tags'] as List?) ?? [];
    final parsedTags = rawTags
        .map((t) {
          final nameMap = t['attributes']?['name'] as Map?;
          return (nameMap?['pt-br'] ?? nameMap?['en'] ?? '').toString();
        })
        .where((t) => t.isNotEmpty)
        .take(5)
        .toList();

    String? coverFile;
    final relationships = (json['relationships'] as List?) ?? [];
    for (final rel in relationships) {
      if (rel['type'] == 'cover_art' && rel['attributes'] != null) {
        coverFile = rel['attributes']['fileName'];
        break;
      }
    }

    return Manga(
      id: json['id'],
      title: resolvedTitle,
      description: resolvedDesc,
      status: (attributes['status'] ?? 'unknown').toString().toUpperCase(),
      coverFileName: coverFile,
      tags: parsedTags,
    );
  }
}

class Chapter {
  final String id;
  final String chapterNumber;
  final String title;
  final String language;
  final int pages;
  final String scanlator;

  Chapter({
    required this.id,
    required this.chapterNumber,
    required this.title,
    required this.language,
    required this.pages,
    this.scanlator = 'Scan Oficial / Comunidade',
  });

  double get numericChapter => double.tryParse(chapterNumber) ?? 999999.0;

  Map<String, dynamic> toMap() => {
    'id': id,
    'chapterNumber': chapterNumber,
    'title': title,
    'language': language,
    'pages': pages,
    'scanlator': scanlator,
  };

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
    id: map['id'] ?? '',
    chapterNumber: map['chapterNumber'] ?? '?',
    title: map['title'] ?? 'Capítulo',
    language: map['language'] ?? 'PT-BR',
    pages: map['pages'] ?? 0,
    scanlator: map['scanlator'] ?? 'Comunidade',
  );

  factory Chapter.fromJson(Map<String, dynamic> json) {
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
      chapterNumber: (attr['chapter'] ?? '?').toString(),
      title:
          (attr['title'] != null && attr['title'].toString().trim().isNotEmpty)
          ? attr['title'].toString()
          : 'Capítulo ${attr['chapter'] ?? '?'}',
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

  ChapterPagesData({
    required this.baseUrl,
    required this.hash,
    required this.hdFiles,
    required this.dataSaverFiles,
  });

  List<String> getUrls({required bool useDataSaver}) {
    final folder = useDataSaver ? 'data-saver' : 'data';
    final files = useDataSaver ? dataSaverFiles : hdFiles;
    return files.map((f) => '$baseUrl/$folder/$hash/$f').toList();
  }
}
