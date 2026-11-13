import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'dart:io';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/screens/offline_manga_detail_screen.dart';
import 'package:kuro_reader/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  final testManga = Manga(
    id: 'offline-manga-1',
    title: 'Solo Leveling (Offline)',
    description: 'Descrição de teste',
    status: 'completed',
    tags: const ['Ação', 'Fantasia'],
    directCoverUrl: 'https://example.com/cover.jpg',
  );

  final testChapter1 = Chapter(
    id: 'ch-1',
    chapterNumber: '1',
    title: 'Capítulo 1',
    language: 'PT-BR',
    pages: 15,
  );

  final testChapter2 = Chapter(
    id: 'ch-2',
    chapterNumber: '2',
    title: 'Capítulo 2',
    language: 'PT-BR',
    pages: 20,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_detail_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(StorageService.downloadsBoxName);
    await Hive.openBox(StorageService.settingsBoxName);
    await Hive.openBox(StorageService.historyBoxName);
    await Hive.openBox(StorageService.favBoxName);

    // Save 2 mock downloaded chapters
    await StorageService.downloadsBox.put('ch-1', {
      'manga': testManga.toMap(),
      'chapter': testChapter1.toMap(),
      'paths': ['/dummy/path/1.jpg'],
    });

    await StorageService.downloadsBox.put('ch-2', {
      'manga': testManga.toMap(),
      'chapter': testChapter2.toMap(),
      'paths': ['/dummy/path/2.jpg'],
    });
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('OfflineMangaDetailScreen displays offline title, chapters and sorting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineMangaDetailScreen(manga: testManga),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Solo Leveling (Offline)'), findsWidgets);
    expect(find.text('ARMAZENAMENTO OFFLINE'), findsOneWidget);
    expect(find.text('Pronto para leitura sem internet'), findsOneWidget);
    expect(find.text('Capítulos Salvos (2)'), findsOneWidget);
    expect(find.text('Ler Capítulo 1 (Offline)'), findsOneWidget);

    // Find chapters 1 and 2
    expect(find.text('Capítulo 1 (PT-BR)'), findsOneWidget);
    expect(find.text('Capítulo 2 (PT-BR)'), findsOneWidget);

    // Toggle sorting
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    // Verify sort icon changed to downward
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });
}
