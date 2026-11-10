import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/screens/home_overview_screen.dart';
import 'package:kuro_reader/screens/home_tabs.dart';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/widgets/catalog_sort_menu.dart';
import 'package:kuro_reader/widgets/reader_toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final manga = Manga(
    id: 'recent',
    title: 'Uma jornada entre universos',
    description: '',
    status: 'ONGOING',
    tags: const [],
  );
  final chapter = Chapter(
    id: 'chapter',
    chapterNumber: '164',
    title: '',
    language: 'PT-BR',
    pages: 24,
  );

  setUpAll(() async {
    final fonts = Platform.environment['YOMI_PREVIEW_FONTS'];
    if (fonts != null) {
      final loader = FontLoader('Roboto');
      loader.addFont(
        File(
          '$fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      loader.addFont(
        File('$fonts/Roboto-Bold.ttf').readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          '$fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await icons.load();
    }
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yomi_ui_');
    Hive.init(directory.path);
    for (final name in [
      StorageService.favBoxName,
      StorageService.historyBoxName,
      StorageService.settingsBoxName,
      StorageService.downloadsBoxName,
    ]) {
      await Hive.openBox(name);
    }
    StorageService.nsfwModeNotifier.value = NsfwDisplayMode.hidden;
    await StorageService.recordChapterOpened(manga, chapter);
    await StorageService.saveLastPageIndex(chapter.id, 8);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  ThemeData theme() => ThemeData.dark(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: YomiPalette.pitchBlack,
    colorScheme: const ColorScheme.dark(
      primary: YomiPalette.ensoRed,
      secondary: YomiPalette.sakuraPink,
      surface: YomiPalette.surface,
    ),
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: const AppBarTheme(
      backgroundColor: YomiPalette.pitchBlack,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
  );

  void screen(WidgetTester tester, {double width = 360}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> preview(WidgetTester tester, String name) async {
    final target = Platform.environment['YOMI_PREVIEW_DIR'];
    if (target == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(target).create(recursive: true);
      await File('$target/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('home highlights a cover, saved progress and working shortcuts', (
    tester,
  ) async {
    screen(tester);
    var explore = 0;
    var library = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(),
        home: RepaintBoundary(
          key: const ValueKey('preview'),
          child: HomeOverviewScreen(
            onExplore: () => explore++,
            onLibrary: () => library++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Página 9 de 24'), findsOneWidget);
    expect(find.byType(YomiCoverImage), findsOneWidget);
    expect(find.text('Continuar leitura'), findsOneWidget);
    await preview(tester, 'inicio');
    await tester.ensureVisible(find.text('Explorar'));
    await tester.tap(find.text('Explorar'));
    await tester.tap(find.text('Biblioteca'));
    expect(explore, 1);
    expect(library, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home and shortcuts support a narrow screen with enlarged text', (
    tester,
  ) async {
    screen(tester, width: 320);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: HomeOverviewScreen(onExplore: () {}, onLibrary: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Biblioteca'), 250);
    expect(find.text('Biblioteca'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reader toolbar retains all actions and adapts to system insets',
    (tester) async {
      screen(tester, width: 320);
      var modes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(top: 32),
            ),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('preview'),
            child: Scaffold(
              body: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF392239)),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: ReaderToolbar(
                      title: 'Uma jornada entre universos e histórias',
                      chapter: '164',
                      page: 8,
                      total: 24,
                      offline: true,
                      webtoon: true,
                      onBack: () {},
                      onMode: () => modes++,
                      onComplete: () {},
                      onPrevious: () {},
                      onNext: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await preview(tester, 'barra-leitor');
      expect(find.byTooltip('Capítulo anterior'), findsOneWidget);
      expect(find.byTooltip('Próximo capítulo'), findsOneWidget);
      await tester.tap(find.byTooltip('Usar modo paginado'));
      expect(modes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog sorting preserves scroll position and does not refetch sources',
    (tester) async {
      screen(tester);
      var catalogCalls = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme(), home: const ExploreScreen()),
          );
          await tester.pumpAndSettle();
          final scroll = tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!;
          scroll.jumpTo(400);
          await tester.pumpAndSettle();
          final before = catalogCalls;
          await tester.tap(find.byTooltip('Ordenar catálogo'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('catalog-sort-title')));
          await tester.pumpAndSettle();
          expect(catalogCalls, before);
          expect(scroll.offset, 400);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(CatalogSortMenu), findsOneWidget);
          expect(
            tester.widget<CatalogSortMenu>(find.byType(CatalogSortMenu)).value,
            CatalogOrder.title,
          );
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          if (request.url.host == 'graphql.anilist.co') {
            if (request.body.contains('Page(')) catalogCalls++;
            return http.Response(
              jsonEncode({
                'data': {
                  'Page': {
                    'media': [],
                    'pageInfo': {'hasNextPage': false},
                  },
                },
              }),
              200,
            );
          }
          catalogCalls++;
          final items = request.url.host == 'api.mangadex.org'
              ? [
                  for (var i = 0; i < 24; i++)
                    {
                      'id': 'work-$i',
                      'attributes': {
                        'title': {'en': 'Obra ${24 - i}'},
                        'description': {'en': ''},
                        'latestUploadedChapter': 'chapter',
                        'updatedAt': '2026-11-10T00:00:00Z',
                      },
                      'relationships': [],
                    },
                ]
              : [];
          return http.Response(
            jsonEncode({
              'data': items,
              'total': items.length,
              'pagination': {'has_next_page': false},
            }),
            200,
          );
        }),
      );
    },
  );

  test(
    'title sorting keeps source results intact and does not use estimated counts',
    () {
      final a = Manga(
        id: 'a',
        title: 'Alpha',
        description: '',
        status: '',
        tags: [],
        availableChaptersCount: 0,
      );
      final z = Manga(
        id: 'z',
        title: 'Zeta',
        description: '',
        status: '',
        tags: [],
        availableChaptersCount: 999,
      );
      final original = [z, a];
      expect(orderCatalog(original, CatalogOrder.title), [a, z]);
      expect(orderCatalog(original, CatalogOrder.source), [z, a]);
      expect(original, [z, a]);
    },
  );
}
