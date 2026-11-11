import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kuro_reader/main.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/screens/home_tabs.dart';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/widgets/privacy_shield.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final manga = Manga(
    id: 'offline-work',
    title: 'Obra offline',
    description: '',
    status: 'ONGOING',
    tags: const [],
  );
  final chapter = Chapter(
    id: 'offline-chapter',
    chapterNumber: '1',
    title: 'Capítulo inicial',
    language: 'PT-BR',
    pages: 1,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yomi_regression_');
    Hive.init(directory.path);
    for (final name in [
      StorageService.favBoxName,
      StorageService.historyBoxName,
      StorageService.downloadsBoxName,
      StorageService.settingsBoxName,
    ]) {
      await Hive.openBox(name);
    }
    StorageService.nsfwModeNotifier.value = NsfwDisplayMode.hidden;
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'offline navigation does not mark the selected chapter completed',
    (tester) async {
      await tester.runAsync(() async {
        await StorageService.downloadsBox.put(chapter.id, {
          'manga': manga.toMap(),
          'chapter': chapter.toMap(),
          'paths': ['${directory.path}/page.png'],
        });
      });
      final observer = _NavigationObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: const DownloadsScreen(),
        ),
      );
      await tester.tap(find.byType(ListTile));
      expect(observer.pushes, 2);
      expect(StorageService.isChapterRead(chapter.id), isFalse);
      expect(StorageService.computeReadingMetrics().totalChaptersRead, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('privacy shield covers pushed routes and clears on resume', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) => PrivacyShield(child: child!),
        home: const Scaffold(body: Text('Início')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(body: Text('Conteúdo privado do leitor')),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Proteção de Privacidade Ativa'), findsOneWidget);
    final semantics = tester.widget<ExcludeSemantics>(
      find
          .descendant(
            of: find.byType(PrivacyShield),
            matching: find.byType(ExcludeSemantics),
          )
          .first,
    );
    expect(semantics.excluding, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Proteção de Privacidade Ativa'), findsNothing);
    expect(find.text('Conteúdo privado do leitor'), findsOneWidget);

    await tester.runAsync(
      () => StorageService.setPrivacyProtectionEnabled(false),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Proteção de Privacidade Ativa'), findsNothing);
    await tester.runAsync(
      () => StorageService.setPrivacyProtectionEnabled(true),
    );
  });

  testWidgets(
    'failed storage startup shows recovery instead of accessing boxes',
    (tester) async {
      await tester.runAsync(() => Hive.close());
      await tester.pumpWidget(const YomiApp(storageReady: false));
      await tester.pump();
      expect(find.text('Não foi possível abrir seus dados'), findsOneWidget);
      expect(find.byType(MainNavigationShell), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'backup settings provide automatic device backup and manual export option',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.scrollUntilVisible(
        find.text('Backup automático ativo no seu aparelho'),
        350,
      );
      expect(
        find.text('Backup automático ativo no seu aparelho'),
        findsOneWidget,
      );
      expect(find.text('Salvar no Aparelho'), findsOneWidget);
      expect(find.text('Restaurar do Aparelho'), findsOneWidget);
    },
  );
}

class _NavigationObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}
