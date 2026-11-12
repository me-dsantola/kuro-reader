import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/manga_models.dart';
import 'observed_http.dart';
import 'storage_service.dart';

class TelegramVaultService {
  static const String botToken = '9226471608:AAGR6VQL6i7zLHLK4c2F9k69efPE6kfyGfw';
  static const String channelId = '-1004356625326';

  static final ValueNotifier<List<Manga>> vaultMangasNotifier = ValueNotifier([]);

  /// Carrega o catálogo sincronizado de HQs do Telegram Vault
  static Future<List<Manga>> loadCatalog() async {
    final mangas = <Manga>[];

    // 1. Tenta carregar do arquivo gerado localmente pelo script
    try {
      final baseDir = await getApplicationSupportDirectory();
      final localCatalogFile = File('${baseDir.path}/yomi_hqs_catalog.json');

      String? jsonStr;
      if (await localCatalogFile.exists()) {
        jsonStr = await localCatalogFile.readAsString();
      } else {
        // Fallback: tenta ler da raiz do projeto se estiver em execução desktop/debug
        final projectFile = File('yomi_hqs_catalog.json');
        if (await projectFile.exists()) {
          jsonStr = await projectFile.readAsString();
        }
      }

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr);
        final List items = decoded['items'] ?? [];
        for (final item in items) {
          if (item is! Map) continue;
          final title = item['title'] ?? 'HQ Sem Título';
          final id = item['id'] ?? 'tg_${title.hashCode}';
          final chaptersList = (item['chapters'] as List? ?? []).map((ch) {
            final numVal = (ch['number'] as num?)?.toString() ?? '1';
            return Chapter(
              id: 'tg_ch_${ch['file_id'] ?? numVal}',
              source: MangaSourceType.comicsHq,
              chapterNumber: numVal,
              title: ch['title'] ?? 'Capítulo $numVal',
              language: 'PT-BR',
              pages: 1, // PDF inteiro tratado como volume/capítulo
              scanlator: 'Telegram Vault',
            );
          }).toList();

          final manga = Manga(
            id: id,
            source: MangaSourceType.comicsHq,
            title: title,
            description: 'Acervo exclusivo YOMI Telegram Vault. Disponível para download e leitura offline.',
            status: 'COMPLETED',
            tags: ['HQ Ocidental', 'Marvel', 'Telegram Vault'],
            availableChaptersCount: chaptersList.length,
            preloadedChapters: chaptersList,
          );

          mangas.add(manga);
          // Armazena no cache para acesso instantâneo na Biblioteca
          await StorageService.cacheMangaChapters(id, chaptersList, titleKey: manga.normalizedTitleKey);
        }
      }
    } catch (_) {}

    vaultMangasNotifier.value = mangas;
    return mangas;
  }

  /// Resolve o link de download direto de um arquivo pelo Bot API
  static Future<String?> resolveDirectDownloadUrl(String fileId) async {
    try {
      final url = 'https://api.telegram.org/bot$botToken/getFile?file_id=$fileId';
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
