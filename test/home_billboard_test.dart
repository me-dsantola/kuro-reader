import 'dart:convert';
import 'support/network_image_client.dart';
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
import 'package:kuro_reader/screens/reader_screen.dart';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/services/profile_palette_service.dart';
import 'package:kuro_reader/widgets/home_billboard.dart';

class _Routes extends NavigatorObserver {
  Route<dynamic>? last;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    last = route;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAgCAIAAACU62+bAAAAHElEQVR4nGN4KOtBEmIY1TCqYVTDqIZRDSNBAwBtMowfZv2fjwAAAABJRU5ErkJggg==',
  );
  List<Map<String, dynamic>>? previewCatalog;
  final previewAssets = Platform.environment['YOMI_HOME_PREVIEW_ASSETS'];

  setUpAll(() async {
    if (previewAssets != null) {
      previewCatalog =
          (jsonDecode(await File('$previewAssets/catalog.json').readAsString())
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
    directory = await Directory.systemTemp.createTemp('yomi_home_');
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
    final images = previewCatalog == null
        ? [image]
        : [
            for (final entry in previewCatalog!)
              File(entry['cover'] as String).readAsBytesSync(),
          ];
    debugNetworkImageHttpClientProvider = () => FixtureImageClient(images);
  });

  tearDown(() async {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();

    await Hive.close();

    await directory.delete(recursive: true);
  });

  String title(int n) =>
      previewCatalog?[n]['title'] as String? ?? 'Mangá popular $n';

  http.Client catalogClient() => MockClient((request) async {
    if (request.url.path.endsWith('/feed')) {
      return http.Response(
        jsonEncode({
          'total': 1,
          'data': [
            {
              'id': 'first-chapter',
              'attributes': {
                'chapter': '1',
                'translatedLanguage': 'pt-br',
                'pages': 1,
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.contains('/at-home/')) {
      return http.Response(
        jsonEncode({
          'baseUrl': 'https://pages.example',
          'chapter': {
            'hash': 'hash',
            'data': ['0.png'],
            'dataSaver': [],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response(
      jsonEncode({
        'total': 5,
        'data': [
          for (var n = 0; n < 5; n++)
            {
              'id': '11111111-1111-1111-1111-11111111111$n',
              'attributes': {
                'title': {'en': title(n)},
                'description': {
                  'en':
                      previewCatalog?[n]['description'] ??
                      'Uma jornada entre mundos, escolhas e novos poderes.',
                },
                'contentRating': 'safe',
                'status': 'ongoing',
                'tags': [
                  {
                    'attributes': {
                      'name': {'en': 'Ação'},
                    },
                  },
                  {
                    'attributes': {
                      'name': {'en': 'Fantasia'},
                    },
                  },
                ],
              },
              'relationships': [
                {
                  'type': 'cover_art',
                  'attributes': {'fileName': '$n.jpg'},
                },
              ],
            },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  Future<void> home(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    NavigatorObserver? observer,
    Future<ProfileAdaptivePalette> Function(Manga)? paletteResolver,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorObservers: [?observer],
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF070709),
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('home-preview'),
          child: HomeOverviewScreen(
            onExplore: () {},
            onLibrary: () {},
            paletteResolver: paletteResolver,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'popular billboard saves to read later and hints horizontal scrolling',
    (tester) async {
      await http.runWithClient(() async {
        await home(tester);

        expect(find.byType(HomeBillboard), findsOneWidget);
        expect(find.text('Ler Agora'), findsOneWidget);
        expect(find.text('Mangás Populares'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Minha Lista'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });

        await tester.pumpAndSettle();
        expect(
          StorageService.isMangaInReadLater('11111111-1111-1111-1111-111111111110'),
          isTrue,
        );
        expect(find.text('Na Minha Lista'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Na Minha Lista'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(
          StorageService.isMangaInReadLater('11111111-1111-1111-1111-111111111110'),
          isFalse,
        );

        final first = tester.getRect(find.text(title(0)).last);
        final fourth = tester.getRect(find.text(title(3)).last);
        expect(first.left, greaterThanOrEqualTo(16));
        expect(fourth.left, lessThan(374));
        expect(fourth.right, greaterThan(390));
        final target = Platform.environment['YOMI_PREVIEW_DIR'];
        if (target != null) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('home-preview')),
            );
            final rendered = await boundary.toImage(pixelRatio: 2);
            final bytes = await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(target).create(recursive: true);
            await File(
              '$target/home-billboard.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            rendered.dispose();
          });
        }

        await tester.drag(find.byType(ListView).first, const Offset(-240, 0));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text(title(3)).last).left,
          lessThan(fourth.left),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugNetworkImageHttpClientProvider = null;
      }, catalogClient);
    },
  );

  testWidgets('billboard supports narrow screens and doubled text size', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await home(tester, width: 320, scale: 2);
      await tester.ensureVisible(find.text('Minha Lista'));
      expect(find.byType(HomeBillboard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugNetworkImageHttpClientProvider = null;
    }, catalogClient);
  });

  testWidgets('read now opens the first available chapter', (tester) async {
    final routes = _Routes();
    await http.runWithClient(() async {
      await home(tester, observer: routes);

      await tester.runAsync(() async {
        await tester.tap(find.text('Ler Agora'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      final route = routes.last as MaterialPageRoute;
      final reader =
          route.builder(tester.element(find.byType(HomeOverviewScreen)))
              as ReaderScreen;
      expect(reader.chapter.id, 'first-chapter');
      expect(reader.allChapters.first.id, 'first-chapter');
      await tester.pumpWidget(const SizedBox());
      debugNetworkImageHttpClientProvider = null;
      await tester.pump();
    }, catalogClient);
  });

  testWidgets(
    'featured manga rotates automatically and can be selected manually',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await http.runWithClient(() async {
        await home(
          tester,
          paletteResolver: (manga) async => ProfileAdaptivePalette.fromColor(
            manga.id.endsWith('0') ? Colors.teal : Colors.amber,
          ),
        );
        final firstColor = tester
            .widget<HomeBillboard>(find.byType(HomeBillboard))
            .accent;
        final first = tester
            .widget<HomeBillboard>(find.byType(HomeBillboard))
            .manga
            .id;
        await tester.pump(const Duration(seconds: 8));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<HomeBillboard>(find.byType(HomeBillboard)).manga.id,
          isNot(first),
        );
        expect(
          tester.widget<HomeBillboard>(find.byType(HomeBillboard)).accent,
          isNot(firstColor),
        );
        await tester.tap(find.bySemanticsLabel('Destaque 1 de 5'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<HomeBillboard>(find.byType(HomeBillboard)).manga.id,
          first,
        );
        await tester.pumpWidget(const SizedBox());
        debugNetworkImageHttpClientProvider = null;
      }, catalogClient);
      semantics.dispose();
    },
  );
}
