import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'dart:io';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/services/yomi_theme_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('yomi_theme_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(StorageService.settingsBoxName);
    YomiThemeController.instance.refresh();
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('All 8 official themes have correct tokens and properties', () {
    expect(YomiThemeId.values.length, 8);

    for (final id in YomiThemeId.values) {
      final tokens = YomiThemeTokens.forId(id);
      expect(tokens.id, id);
      expect(tokens.name.isNotEmpty, isTrue);
      expect(tokens.background, isNotNull);
      expect(tokens.surface, isNotNull);
      expect(tokens.cardSurface, isNotNull);
      expect(tokens.textPrimary, isNotNull);
      expect(tokens.accentPrimary, isNotNull);
      expect(tokens.accentSecondary, isNotNull);

      if (tokens.isLight) {
        expect(tokens.brightness, Brightness.light);
      } else {
        expect(tokens.brightness, Brightness.dark);
      }
    }
  });

  test('Theme switching persists to Hive and updates controller', () async {
    final controller = YomiThemeController.instance;

    await controller.setTheme(YomiThemeId.emeraldGreen);
    expect(controller.value.id, YomiThemeId.emeraldGreen);
    expect(
      StorageService.settingsBox.get(YomiThemeController.themeKey),
      'emerald_green',
    );

    await controller.setTheme(YomiThemeId.sepia);
    expect(controller.value.id, YomiThemeId.sepia);
    expect(controller.value.isLight, isTrue);
    expect(
      StorageService.settingsBox.get(YomiThemeController.themeKey),
      'sepia',
    );
  });

  test('Reactive colors adjust accents while preserving base surfaces and backgrounds', () async {
    final controller = YomiThemeController.instance;
    await controller.setTheme(YomiThemeId.amoled);

    final initialBg = controller.value.background;
    final initialSurface = controller.value.surface;

    // Simulate work cover accent color
    const rawArtworkColor = Color(0xFF00E5FF);
    controller.updateReactiveAccent(rawArtworkColor);

    // Background & surface MUST remain strictly intact
    expect(controller.value.background, initialBg);
    expect(controller.value.surface, initialSurface);
    // Accents are dynamically tuned
    expect(controller.value.accentPrimary, isNot(equals(YomiThemeTokens.amoled.accentPrimary)));

    // Disabling reactive colors restores official theme accents
    await controller.setReactiveColors(false);
    expect(controller.reactiveColorsEnabled, isFalse);
    expect(controller.value.accentPrimary, YomiThemeTokens.amoled.accentPrimary);
  });

  test('Ambilight toggle persists and can be queried', () async {
    final controller = YomiThemeController.instance;
    expect(controller.ambilightEnabled, isTrue);

    await controller.setAmbilight(false);
    expect(controller.ambilightEnabled, isFalse);
    expect(
      StorageService.settingsBox.get(YomiThemeController.ambilightKey),
      isFalse,
    );
  });
}
