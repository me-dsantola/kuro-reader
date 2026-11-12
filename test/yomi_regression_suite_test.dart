import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/screens/home/featured_preload_controller.dart';
import 'package:kuro_reader/screens/home/home_collapsible_header.dart';
import 'package:kuro_reader/services/chapter_availability_cache.dart';
import 'package:kuro_reader/services/grouped_downloads_manager.dart';

void main() {
  group('1. Sincronização de Paleta e Contraste do Header', () {
    test('FeaturedPalette.lerp mantém contraste legível entre extremos claro e escuro', () {
      final darkPalette = FeaturedPalette.fromSeed(
        const Color(0xFF090A10),
        brightness: Brightness.dark,
      );
      final lightPalette = FeaturedPalette.fromSeed(
        const Color(0xFFFFFDE7),
        brightness: Brightness.light,
      );

      for (var step = 0; step <= 10; step++) {
        final t = step / 10.0;
        final lerped = FeaturedPalette.lerp(darkPalette, lightPalette, t);
        final surfaceLum = lerped.surface.computeLuminance();
        final textLum = lerped.onSurface.computeLuminance();
        final contrastRatio = (surfaceLum > textLum)
            ? (surfaceLum + 0.05) / (textLum + 0.05)
            : (textLum + 0.05) / (surfaceLum + 0.05);

        expect(
          contrastRatio,
          greaterThanOrEqualTo(3.5),
          reason: 'Falha de contraste no progresso t=$t',
        );
      }
    });

    testWidgets('Rolagem horizontal do carrossel não recolhe o header da Home', (tester) async {
      late BuildContext buildContext;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) {
            buildContext = ctx;
            return const SizedBox();
          },
        ),
      ));

      final coordinator = VerticalScrollCoordinator();
      final horizontalNotification = ScrollUpdateNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 500,
          pixels: 120,
          viewportDimension: 360,
          axisDirection: AxisDirection.right,
          devicePixelRatio: 1.0,
        ),
        context: buildContext,
        scrollDelta: 45.0,
      );

      coordinator.handleScrollNotification(horizontalNotification);
      expect(coordinator.collapseFactor, equals(0.0));
    });
  });

  group('2. Estado de Zero Capítulos vs. Desconhecido', () {
    test('Metadado ausente (null) não é tratado como zero capítulos', () {
      final cache = ChapterAvailabilityCache();
      final listenable = cache.watch('manga_unknown', initialKnownCount: null);
      expect(listenable.value.status, ChapterCountStatus.unknown);
      expect(listenable.value.isConfirmedZero, isFalse);
    });

    test('Contagem zero confirmada ativa isConfirmedZero e atualiza quando capítulos surgem', () {
      final cache = ChapterAvailabilityCache();
      final listenable = cache.watch('manga_zero', initialKnownCount: 0);
      expect(listenable.value.isConfirmedZero, isTrue);

      cache.updateConfirmedCount('manga_zero', 3);
      expect(listenable.value.isConfirmedZero, isFalse);
      expect(listenable.value.count, 3);
    });
  });

  group('3. Downloads Agrupados e Persistência de Capa Offline', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('yomi_downloads_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Agrupa capítulos por obra, ordena por número e baixa a capa apenas uma vez', () async {
      var coverDownloadCount = 0;
      final manager = GroupedDownloadsManager(
        persistentCoversDir: Directory('${tempDir.path}/covers'),
        coverDownloader: (_) async {
          coverDownloadCount++;
          return Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);
        },
      );

      final ch2Dir = await Directory('${tempDir.path}/ch2').create();
      final ch1Dir = await Directory('${tempDir.path}/ch1').create();

      await manager.addOrUpdateChapterDownload(
        DownloadedChapterRecord(
          chapterId: 'ch_2',
          mangaId: 'horizonte',
          mangaTitle: 'Horizonte Distante',
          chapterTitle: 'Capítulo 2',
          chapterNumber: 2,
          localDirectoryPath: ch2Dir.path,
          state: ChapterDownloadState.completed,
          remoteCoverUrl: 'https://example.com/cover.png',
        ),
      );

      await manager.addOrUpdateChapterDownload(
        DownloadedChapterRecord(
          chapterId: 'ch_1',
          mangaId: 'horizonte',
          mangaTitle: 'Horizonte Distante',
          chapterTitle: 'Capítulo 1',
          chapterNumber: 1,
          localDirectoryPath: ch1Dir.path,
          state: ChapterDownloadState.completed,
          remoteCoverUrl: 'https://example.com/cover.png',
        ),
      );

      expect(coverDownloadCount, equals(1));
      expect(manager.groups.length, equals(1));
      final group = manager.groups.first;
      expect(group.chapters.map((c) => c.chapterId).toList(), ['ch_1', 'ch_2']);
      expect(group.localCoverPath, isNotNull);
      expect(File(group.localCoverPath!).existsSync(), isTrue);

      // Excluir apenas 1 capítulo mantém a capa pois ch_2 continua usando
      await manager.deleteChapterDownload('ch_1');
      expect(File(group.localCoverPath!).existsSync(), isTrue);

      // Excluir o último capítulo da obra remove a capa persistida
      final savedCoverPath = group.localCoverPath!;
      await manager.deleteChapterDownload('ch_2');
      expect(File(savedCoverPath).existsSync(), isFalse);
    });

    test('Falha no download da capa não invalida capítulos já baixados', () async {
      final manager = GroupedDownloadsManager(
        persistentCoversDir: Directory('${tempDir.path}/covers'),
        coverDownloader: (_) async => throw const SocketException('Sem internet'),
      );

      final chDir = await Directory('${tempDir.path}/ch_offline').create();
      await manager.addOrUpdateChapterDownload(
        DownloadedChapterRecord(
          chapterId: 'ch_10',
          mangaId: 'obra_offline',
          mangaTitle: 'Obra Offline',
          chapterTitle: 'Capítulo 10',
          chapterNumber: 10,
          localDirectoryPath: chDir.path,
          state: ChapterDownloadState.completed,
          remoteCoverUrl: 'https://example.com/unreachable.png',
        ),
      );

      expect(manager.groups.length, equals(1));
      expect(manager.groups.first.completedCount, equals(1));
      expect(manager.groups.first.localCoverPath, isNull);
    });
  });
}
