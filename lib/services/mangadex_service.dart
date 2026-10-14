import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/manga_models.dart';
import 'storage_service.dart';

class MangaDexService {
  static const String _baseUrl = 'https://api.mangadex.org';

  static const Map<String, String> headers = {
    'User-Agent': 'KuroReaderAndroid/4.0 (Personal Use; Flutter)',
    'Accept': 'application/json',
  };

  static Future<List<Manga>> fetchMangas({
    String? query,
    int offset = 0,
  }) async {
    final fullUrl =
        '$_baseUrl/manga?limit=24&offset=$offset'
        '&includes[]=cover_art'
        '&contentRating[]=safe&contentRating[]=suggestive'
        '&hasAvailableChapters=true'
        '${(query != null && query.trim().isNotEmpty) ? '&title=${Uri.encodeQueryComponent(query.trim())}&order[relevance]=desc' : '&order[followedCount]=desc'}';

    final response = await http.get(Uri.parse(fullUrl), headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List list = data['data'] ?? [];
      return list.map((json) => Manga.fromJson(json)).toList();
    } else {
      throw Exception('Erro na API MangaDex (${response.statusCode})');
    }
  }

  static Future<List<Chapter>> fetchChapters(String mangaId) async {
    final fullUrl =
        '$_baseUrl/manga/$mangaId/feed?limit=500'
        '&translatedLanguage[]=pt-br&translatedLanguage[]=en'
        '&includes[]=scanlation_group'
        '&order[chapter]=desc'
        '&includeExternalUrl=0';

    final response = await http.get(Uri.parse(fullUrl), headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List list = data['data'] ?? [];
      final rawChapters = list
          .map((json) => Chapter.fromJson(json))
          .where((ch) => ch.pages > 0)
          .toList();

      // Deduplicação inteligente: mantém 1 versão por número de capítulo em cada idioma
      final Map<String, Chapter> uniqueMap = {};
      for (final ch in rawChapters) {
        final key = '${ch.language}_${ch.chapterNumber}';
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = ch;
        }
      }

      final chapters = uniqueMap.values.toList();
      await StorageService.cacheMangaChapters(mangaId, chapters);
      return chapters;
    } else {
      throw Exception('Falha ao carregar capítulos (${response.statusCode})');
    }
  }

  static Future<ChapterPagesData> fetchChapterPages(String chapterId) async {
    final url = Uri.parse('$_baseUrl/at-home/server/$chapterId');
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final chapter = data['chapter'];
      return ChapterPagesData(
        baseUrl: data['baseUrl'],
        hash: chapter['hash'],
        hdFiles: List<String>.from(chapter['data'] ?? []),
        dataSaverFiles: List<String>.from(chapter['dataSaver'] ?? []),
      );
    } else {
      throw Exception('Servidor de páginas indisponível');
    }
  }
}
