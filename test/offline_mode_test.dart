import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/main.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/screens/home_tabs.dart';
import 'package:kuro_reader/screens/reader_screen.dart';
import 'package:kuro_reader/services/appearance_controller.dart';
import 'package:kuro_reader/services/device_state_service.dart';
import 'package:kuro_reader/services/mangadex_service.dart';
import 'package:kuro_reader/services/observed_http.dart';
import 'package:kuro_reader/services/reader_image_session.dart';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/services/profile_palette_service.dart';
import 'package:kuro_reader/widgets/reader_toolbar.dart';
import 'package:kuro_reader/widgets/app_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final device = DeviceStateService.instance;
  final manga = Manga(
    id: 'saved-work',
    title: 'Leitura salva',
    description: '',
    status: 'ONGOING',
    tags: const [],
  );
  final chapter = Chapter(
    id: 'saved-chapter',
    chapterNumber: '1',
    title: 'Início',
    language: 'PT-BR',
    pages: 1,
  );
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAgCAIAAACU62+bAAAAHElEQVR4nGN4KOtBEmIY1TCqYVTDqIZRDSNBAwBtMowfZv2fjwAAAABJRU5ErkJggg==',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yomi_offline_');
    Hive.init(directory.path);
    for (final name in [
      StorageService.favBoxName,
      StorageService.historyBoxName,
      StorageService.settingsBoxName,
      StorageService.downloadsBoxName,
    ]) {
      await Hive.openBox(name);
    }
    await StorageService.updateUserProfile(
      const UserProfile(name: 'Leitor de teste', isConfigured: true),
    );
    device.applyNativeState({'internet': 'online'});
    AppearanceController.instance.refresh();
  });

  tearDown(() async {
    AppFeedback.dismiss();
    device.applyNativeState({'internet': 'unknown'});
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('network availability handles no connection and recovery', () {
    final service = DeviceStateService();
    service.applyConnectivity([ConnectivityResult.none]);
    expect(service.isOffline, isTrue);
    service.applyConnectivity([
      ConnectivityResult.wifi,
      ConnectivityResult.vpn,
    ]);
    expect(service.value.internet, InternetState.online);
    service.dispose();
  });

  test('Blobatar interaction and color preferences survive saved profile', () {
    const original = UserProfile(
      blobatarInteractive: false,
      blobatarHue: 173,
      customAccentColor: 0xFF14B8A6,
    );
    final restored = UserProfile.fromMap(original.toMap());
    expect(restored.blobatarInteractive, isFalse);
    expect(restored.blobatarHue, 173);
    expect(restored.customAccentColor, 0xFF14B8A6);
    expect(UserProfile.fromMap({'name': 'Legado'}).blobatarInteractive, isTrue);
  });

  testWidgets(
    'Android queries state on start and resumes its event subscription',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const query = MethodChannel('yomi/device_state_query');
      const events = MethodChannel('yomi/device_state');
      var online = false;
      var subscribed = false;
      messenger.setMockMethodCallHandler(
        query,
        (_) async => {'internet': online ? 'online' : 'offline'},
      );
      messenger.setMockMethodCallHandler(events, (call) async {
        subscribed = call.method == 'listen';
        return null;
      });
      final service = DeviceStateService()..start();
      await tester.pump();
      expect(service.isOffline, isTrue);
      expect(subscribed, isTrue);
      online = true;
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(service.value.internet, InternetState.online);
      service.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(query, null);
      messenger.setMockMethodCallHandler(events, null);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('offline discovery uses downloads and makes no HTTP requests', () async {
    final cachedOnly = Chapter(
      id: 'not-downloaded',
      chapterNumber: '2',
      title: '',
      language: 'PT-BR',
      pages: 1,
    );
    await StorageService.cacheMangaChapters(manga.id, [chapter, cachedOnly]);
    await StorageService.downloadsBox.put(chapter.id, {
      'manga': manga.toMap(),
      'chapter': chapter.toMap(),
      'paths': ['${directory.path}/page.png'],
    });
    device.applyNativeState({'internet': 'offline'});
    var calls = 0;
    await http.runWithClient(
      () async {
        final result = await MangaDexService.discoverAllSourcesForManga(manga);
        expect(result[manga.source]!.map((c) => c.id), [chapter.id]);
        await expectLater(
          ObservedHttp.get(Uri.parse('https://example.com')),
          throwsA(isA<http.ClientException>()),
        );
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    expect(calls, 0);
  });

  test(
    'cached reading pages remain available offline without network retries',
    () async {
      var calls = 0;
      final session = ReaderImageSession(
        urls: ['https://pages.example/1.png', 'https://pages.example/2.png'],
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes(png, 200);
        }),
      );
      expect(await session.pageBytes(0), png);
      device.applyNativeState({'internet': 'offline'});
      expect(await session.pageBytes(0), png);
      await expectLater(session.pageBytes(1), throwsStateError);
      expect(calls, 1);
      session.close();
    },
  );

  testWidgets(
    'offline exposes only library and profile; reconnect refreshes home',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var catalogCalls = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(),
              home: const MainNavigationShell(),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Início'), findsOneWidget);
          expect(find.text('Offline'), findsNothing);
          final initialCalls = catalogCalls;
          device.applyNativeState({'internet': 'offline'});
          await tester.pumpAndSettle();
          expect(
            find.textContaining('funcionalidades reduzidas'),
            findsOneWidget,
          );
          expect(find.text('Início'), findsNothing);
          expect(find.text('Explorar'), findsNothing);
          expect(find.text('Biblioteca'), findsOneWidget);
          expect(find.text('Perfil'), findsOneWidget);
          expect(find.text('Baixados'), findsOneWidget);
          await tester.tap(find.text('Perfil'));
          await tester.pumpAndSettle();
          expect(find.byType(ProfileDashboardScreen), findsOneWidget);
          expect(catalogCalls, initialCalls);
          device.applyNativeState({'internet': 'online'});
          await tester.pumpAndSettle();
          expect(find.text('Início'), findsOneWidget);
          expect(find.text('Explorar'), findsOneWidget);
          expect(
            find.textContaining('funcionalidades reduzidas'),
            findsNothing,
          );
          await tester.tap(find.text('Início'));
          await tester.pump();
          final fade = tester
              .widgetList<FadeTransition>(find.byType(FadeTransition))
              .where((widget) => widget.opacity is AnimationController)
              .first;
          expect(fade.opacity.value, lessThan(1));
          await tester.pumpAndSettle();
          expect(catalogCalls, greaterThan(initialCalls));
          AppFeedback.dismiss();
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        },
        () => MockClient((_) async {
          catalogCalls++;
          return http.Response('{"data":[],"total":0}', 200);
        }),
      );
    },
  );

  testWidgets('downloaded chapter renders offline without HTTP', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final path = '${directory.path}/page.png';
      await File(path).writeAsBytes(png);
      await StorageService.downloadsBox.put(chapter.id, {
        'manga': manga.toMap(),
        'chapter': chapter.toMap(),
        'paths': [path],
      });
      await StorageService.cacheMangaChapters(manga.id, [chapter]);
    });
    device.applyNativeState({'internet': 'offline'});
    var requests = 0;
    await http.runWithClient(
      () async {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: ReaderScreen(
                manga: manga,
                chapter: chapter,
                allChapters: [chapter],
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
        }
        await tester.pumpAndSettle();
        expect(
          tester.widget<ReaderToolbar>(find.byType(ReaderToolbar)).offline,
          isTrue,
        );
        expect(requests, 0);
        expect(StorageService.isChapterRead(chapter.id), isFalse);
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        expect(tester.takeException(), isNull);
      },
      () => MockClient((_) async {
        requests++;
        throw http.ClientException('network forbidden');
      }),
    );
  });

  testWidgets('reader controls react to artwork and profile preferences', (
    tester,
  ) async {
    final colors = ProfileAdaptivePalette.fromColor(Colors.teal);
    Widget toolbar() => MaterialApp(
      home: Scaffold(
        body: ReaderToolbar(
          palette: colors,
          title: 'Leitura',
          chapter: '1',
          page: 0,
          total: 1,
          offline: true,
          webtoon: true,
          onBack: () {},
          onMode: () {},
          onComplete: () {},
        ),
      ),
    );
    await tester.pumpWidget(toolbar());
    expect(
      tester.widget<Icon>(find.byIcon(Icons.view_carousel_rounded)).color,
      colors.secondary,
    );
    await tester.runAsync(
      () => AppearanceController.instance.setReactiveReader(false),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Icon>(find.byIcon(Icons.view_carousel_rounded)).color,
      ProfilePaletteService.paletteNotifier.value.secondary,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('alerts are dismissible popups with no Snackbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () =>
                  AppFeedback.message(context, 'Erro ao abrir capítulo.'),
              child: const Text('Avisar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Avisar'));
    await tester.pump();
    expect(find.text('Erro ao abrir capítulo.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byTooltip('Fechar aviso'));
    await tester.pump();
    expect(find.text('Erro ao abrir capítulo.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
