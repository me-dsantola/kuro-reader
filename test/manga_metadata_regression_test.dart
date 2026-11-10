import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/manga_models.dart';

void main() {
  test(
    'different Japanese and Korean titles cannot collapse to an empty identity',
    () {
      expect(normalizeMangaTitle('進撃の巨人'), isNotEmpty);
      expect(normalizeMangaTitle('進撃の巨人'), isNot(normalizeMangaTitle('鬼滅の刃')));
      expect(normalizeMangaTitle('나 혼자만 레벨업'), isNotEmpty);
      expect(
        normalizeMangaTitle('One Piece!'),
        normalizeMangaTitle('ONE PIECE'),
      );
    },
  );

  test(
    'MangaDex does not invent chapter counts or trust missing classifications',
    () {
      Manga parse(Map<String, Object?> attributes) =>
          Manga.fromJson({'id': 'manga', 'attributes': attributes});
      expect(
        parse({
          'contentRating': 'safe',
          'latestUploadedChapter': 'chapter',
        }).availableChaptersCount,
        -1,
      );
      expect(
        parse({
          'contentRating': 'safe',
          'latestUploadedChapter': null,
        }).availableChaptersCount,
        0,
      );
      expect(parse({'contentRating': 'safe'}).isNsfw, isFalse);
      expect(parse({}).contentRatingKnown, isFalse);
      expect(parse({}).isNsfw, isTrue);
      expect(parse({'contentRating': 'unexpected'}).isNsfw, isTrue);
    },
  );

  test(
    'a missing preferred quality falls back to the available page sequence',
    () {
      final hdOnly = ChapterPagesData(
        baseUrl: 'https://pages.example',
        hash: 'hash',
        hdFiles: ['1.png', '2.png'],
        dataSaverFiles: [],
      );
      expect(hdOnly.getUrls(useDataSaver: true), [
        'https://pages.example/data/hash/1.png',
        'https://pages.example/data/hash/2.png',
      ]);
      final saverOnly = ChapterPagesData(
        baseUrl: 'https://pages.example',
        hash: 'hash',
        hdFiles: [],
        dataSaverFiles: ['1.png'],
      );
      expect(saverOnly.getUrls(useDataSaver: false), [
        'https://pages.example/data-saver/hash/1.png',
      ]);
      final invalid = ChapterPagesData(
        baseUrl: '',
        hash: '',
        hdFiles: [],
        dataSaverFiles: [],
        directUrls: ['file:///private/image.png'],
      );
      expect(() => invalid.getUrls(useDataSaver: false), throwsFormatException);
    },
  );
}
