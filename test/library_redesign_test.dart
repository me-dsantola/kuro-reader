import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kuro_reader/main.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/screens/home_tabs.dart';
import 'package:kuro_reader/services/library_progress.dart';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/services/device_state_service.dart';
import 'package:kuro_reader/services/profile_palette_service.dart';
import 'package:kuro_reader/widgets/yomi_blobatar_studio.dart';
import 'support/network_image_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<Manga> mangas;
  List<Map<String, dynamic>>? covers;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAgCAIAAACU62+bAAAAHElEQVR4nGN4KOtBEmIY1TCqYVTDqIZRDSNBAwBtMowfZv2fjwAAAABJRU5ErkJggg==',
  );

  setUpAll(() async {
    final assets = Platform.environment['YOMI_HOME_PREVIEW_ASSETS'];
    if (assets != null) {
      covers =
          (jsonDecode(await File('$assets/catalog.json').readAsString())
                  as List)
              .cast<Map<String, dynamic>>();
    }
    final fonts = Platform.environment['YOMI_PREVIEW_FONTS'];
    if (fonts != null) {
      final loader = FontLoader('Roboto');
      for (final name in [
        'roboto-regular.ttf',
        'roboto-bold.ttf',
        'roboto-black.ttf',
      ]) {
        loader.addFont(
          File('$fonts/$name').readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          '$fonts/materialicons-regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await icons.load();
    }
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yomi_library_');
    Hive.init(directory.path);
    for (final name in [
      StorageService.favBoxName,
      StorageService.historyBoxName,
      StorageService.settingsBoxName,
      StorageService.downloadsBoxName,
    ]) {
      await Hive.openBox(name);
    }
    DeviceStateService.instance.applyNativeState({'internet': 'online'});
    StorageService.nsfwModeNotifier.value = NsfwDisplayMode.hidden;
    await StorageService.updateUserProfile(
      const UserProfile(
        name: 'Leitor',
        openOnProfileByDefault: true,
        customAccentColor: 0xFF14B8A6,
      ),
    );
    ProfilePaletteService.paletteNotifier.value =
        ProfileAdaptivePalette.fromColor(Colors.teal);
    mangas = [
      for (var i = 0; i < 3; i++)
        Manga(
          id: 'work-$i',
          title:
              covers?[i]['title'] as String? ??
              ['Aniquilação', 'Leitura concluída', 'Nova jornada'][i],
          description: '',
          status: 'ONGOING',
          tags: const [],
          availableChaptersCount: i == 1 ? 2 : 4,
          directCoverUrl: 'https://covers.example/$i.jpg',
        ),
    ];
    for (final manga in mangas) {
      await StorageService.toggleFavorite(manga);
    }
    List<Chapter> chapters(int work, int count) => [
      for (var n = 1; n <= count; n++)
        Chapter(
          id: 'work-$work-ch-$n',
          chapterNumber: '$n',
          title: '',
          language: 'PT-BR',
          pages: 10,
        ),
    ];
    final first = chapters(0, 4);
    final completed = chapters(1, 2);
    await StorageService.cacheMangaChapters(mangas[0].id, first);
    await StorageService.cacheMangaChapters(mangas[1].id, completed);
    for (final chapter in completed) {
      await StorageService.markChapterAsRead(mangas[1], chapter);
    }
    await StorageService.markChapterAsRead(mangas[0], first.first);
    await StorageService.recordChapterOpened(mangas[0], first[1]);
    await StorageService.saveLastPageIndex(first[1].id, 4);
    final images = covers == null
        ? [png]
        : [
            for (final cover in covers!)
              File(cover['cover'] as String).readAsBytesSync(),
          ];
    debugNetworkImageHttpClientProvider = () => FixtureImageClient(images);
  });

  tearDown(() async {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    DeviceStateService.instance.applyNativeState({'internet': 'unknown'});
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    double scale = 1,
    double width = 390,
    bool shell = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('library-preview'),
          child: shell
              ? const MainNavigationShell()
              : LibraryScreen(onExplore: () {}),
        ),
      ),
    );
    if (shell) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Biblioteca').last);
    }
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
  }

  test(
    'progress counts completed chapters and saved page without duplicates',
    () {
      expect(LibraryProgress.forManga(mangas[0]).fraction, 0.375);
      expect(LibraryProgress.forManga(mangas[0]).completed, isFalse);
      expect(LibraryProgress.forManga(mangas[1]).completed, isTrue);
      expect(LibraryProgress.forManga(mangas[2]).fraction, 0);
      final alias = Chapter(
        id: 'english-alias',
        chapterNumber: '1.0',
        title: '',
        language: 'EN',
        pages: 10,
      );
      expect(
        LibraryProgress.forManga(
          mangas[0].copyWith(preloadedChapters: [alias]),
        ).fraction,
        0.375,
      );
    },
  );

  test('a partial cache cannot turn a whole work into completed', () async {
    final chapter = Chapter(
      id: 'partial',
      chapterNumber: '1',
      title: '',
      language: 'PT-BR',
      pages: 10,
    );
    await StorageService.cacheMangaChapters(mangas[2].id, [chapter]);
    await StorageService.markChapterAsRead(mangas[2], chapter);
    final progress = LibraryProgress.forManga(mangas[2]);
    expect(progress.fraction, 0.25);
    expect(progress.completed, isFalse);
  });

  testWidgets('library reference layout preserves tabs and reactive theme', (
    tester,
  ) async {
    await mount(tester, shell: true);
    expect(find.text('Minha Biblioteca'), findsOneWidget);
    expect(find.text('Baixados'), findsOneWidget);
    expect(find.text('CONTINUE LENDO'), findsOneWidget);
    expect(find.text('38% lido'), findsOneWidget);
    expect(find.text('100% concluído'), findsOneWidget);
    expect(
      find
          .byType(CustomPaint)
          .evaluate()
          .where(
            (element) =>
                element.widget is CustomPaint &&
                (element.widget as CustomPaint).painter
                    is YomiMoonlitLibraryBackdropPainter,
          ),
      isEmpty,
    );
    final target = Platform.environment['YOMI_PREVIEW_DIR'];
    if (target != null) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('library-preview')),
        );
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(target).create(recursive: true);
        await File(
          '$target/library-redesign.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets('chips use reading state and search matches accents', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'aniquilacao');
    await tester.pumpAndSettle();
    expect(find.text(mangas[0].title), findsWidgets);
    expect(find.text(mangas[1].title), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.ensureVisible(find.text('Concluídas'));
    await tester.tap(find.text('Concluídas'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text(mangas[1].title), findsOneWidget);
    expect(find.text(mangas[0].title), findsNothing);
    await tester.ensureVisible(find.text('Lendo'));
    await tester.tap(find.text('Lendo'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text(mangas[0].title), findsWidgets);
    expect(find.text(mangas[1].title), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing profile colors recolors search tabs and progress', (
    tester,
  ) async {
    await mount(tester);
    final palette = ProfileAdaptivePalette.fromColor(Colors.deepOrange);
    ProfilePaletteService.paletteNotifier.value = palette;
    await tester.pump();
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).indicatorColor,
      palette.primary,
    );
    final input = tester.widget<TextField>(find.byType(TextField));
    expect((input.decoration!.prefixIcon! as Icon).color, palette.primary);
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .every((indicator) => indicator.color == palette.primary),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets('library supports narrow screens with enlarged text', (
    tester,
  ) async {
    await mount(tester, width: 320, scale: 2);
    await tester.scrollUntilVisible(
      find.text('Adicione novas obras'),
      250,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('Adicione novas obras'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });

  test('three default banners are real bundled assets', () async {
    final banners = kYomiBannerPresets
        .where((preset) => preset.assetPath != null)
        .toList();
    expect(banners.map((b) => b.title), [
      'Horizonte distante',
      'Lua vermelha',
      'Portal da noite',
    ]);
    for (final banner in banners) {
      expect(
        (await rootBundle.load(banner.assetPath!)).lengthInBytes,
        greaterThan(1000),
      );
    }
  });
}
