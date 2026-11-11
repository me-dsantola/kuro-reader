import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/download_manager.dart';

void main() {
  test('chapter deduplication prioritizes PT-BR and fills missing gaps from EN', () {
    final rawChapters = [
      Chapter(
        id: 'pt_1',
        chapterNumber: '1',
        title: 'Início',
        language: 'PT-BR',
        pages: 20,
      ),
      Chapter(
        id: 'en_1',
        chapterNumber: '1',
        title: 'Beginning',
        language: 'EN',
        pages: 20,
      ),
      Chapter(
        id: 'en_2',
        chapterNumber: '2',
        title: 'Journey',
        language: 'EN',
        pages: 22,
      ),
      Chapter(
        id: 'pt_3',
        chapterNumber: '3',
        title: 'Batalha',
        language: 'PT-BR',
        pages: 18,
      ),
    ];

    final deduplicated = DownloadManager.deduplicateForBatchDownload(rawChapters);

    // Deve conter exatamente 3 capítulos únicos: 1 (PT-BR), 2 (EN como gap filler) e 3 (PT-BR)
    expect(deduplicated.length, 3);
    expect(deduplicated[0].chapterNumber, '1');
    expect(deduplicated[0].language, 'PT-BR');

    expect(deduplicated[1].chapterNumber, '2');
    expect(deduplicated[1].language, 'EN'); // Preencheu a lacuna!

    expect(deduplicated[2].chapterNumber, '3');
    expect(deduplicated[2].language, 'PT-BR');
  });
}
