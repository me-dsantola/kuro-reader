import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/manga_models.dart';
import 'observed_http.dart';
import 'storage_service.dart';

class TelegramVaultService {
  static const String botToken = String.fromEnvironment('TELEGRAM_BOT_TOKEN');

  static Future<Map<String, dynamic>> _catalogData() async {
    final candidates = <Future<String> Function()>[
      if (!kIsWeb) ...[
        () async {
          final directory = await getApplicationSupportDirectory();
          return File('${directory.path}/yomi_hqs_catalog.json').readAsString();
        },
        if (kDebugMode) () => File('yomi_hqs_catalog.json').readAsString(),
      ],
      () => rootBundle.loadString('yomi_hqs_catalog.json'),
    ];
    for (final read in candidates) {
      try {
        final data = jsonDecode(await read());
        if (data is Map<String, dynamic> && data['items'] is List) return data;
      } catch (_) {
        // A missing or damaged local override must not hide the bundled catalog.
      }
    }
    throw const FormatException('Nenhum catálogo de HQs válido disponível.');
  }

  /// Carrega o catálogo sincronizado de HQs do Telegram Vault
  static Future<List<Manga>> loadCatalog() async {
    final mangas = <Manga>[];

    // 1. Tenta carregar do arquivo gerado localmente pelo script
    try {
      final decoded = await _catalogData();
      final List items = decoded['items'] ?? [];
      for (final item in items) {
        if (item is! Map || item['id'] is! String || item['title'] is! String) {
          continue;
        }
        final title = item['title'] as String;
        final id = item['id'] as String;
        final chaptersList =
            (item['chapters'] is List ? item['chapters'] as List : const [])
                .whereType<Map>()
                .where(
                  (ch) =>
                      ch['file_id'] is String &&
                      (ch['file_id'] as String).isNotEmpty,
                )
                .map((ch) {
                  final numVal = ch['number']?.toString() ?? '1';
                  return Chapter(
                    id: 'tg_ch_${ch['file_id'] ?? numVal}',
                    source: MangaSourceType.comicsHq,
                    chapterNumber: numVal,
                    title: ch['title']?.toString() ?? 'Capítulo $numVal',
                    language: 'PT-BR',
                    pages:
                        0, // Quantidade de páginas ainda não extraída do documento.
                    scanlator: 'Telegram Vault',
                  );
                })
                .toList();

        final manga = Manga(
          id: id,
          source: MangaSourceType.comicsHq,
          title: title,
          description:
              'HQ do catálogo Telegram Vault. A leitura de documentos PDF/CBR/ZIP ainda não está disponível.',
          status: 'COMPLETED',
          tags: ['HQ Ocidental', 'Marvel', 'Telegram Vault'],
          availableChaptersCount: chaptersList.length,
          preloadedChapters: chaptersList,
        );

        mangas.add(manga);
        // Armazena no cache para acesso instantâneo na Biblioteca
        try {
          await StorageService.cacheMangaChapters(
            id,
            chaptersList,
            titleKey: manga.normalizedTitleKey,
          );
        } catch (_) {
          // Catalog discovery remains available if the local cache cannot write.
        }
      }
    } catch (error) {
      debugPrint('Não foi possível carregar o catálogo de HQs: $error');
    }

    return mangas;
  }

  /// Resolve o link de download direto de um arquivo pelo Bot API
  static Future<String?> resolveDirectDownloadUrl(String fileId) async {
    if (botToken.isEmpty || fileId.trim().isEmpty) return null;
    try {
      final url =
          'https://api.telegram.org/bot$botToken/getFile?file_id=${Uri.encodeQueryComponent(fileId)}';
      final response = await ObservedHttp.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true && data['result'] != null) {
          final filePath = data['result']['file_path'];
          if (filePath != null) {
            return 'https://api.telegram.org/file/bot$botToken/$filePath';
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
