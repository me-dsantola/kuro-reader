import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kuro_reader/services/appearance_controller.dart';
import 'package:kuro_reader/services/storage_service.dart';
import 'package:kuro_reader/services/backup_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yomi_appearance_');
    Hive.init(directory.path);
    for (final name in [
      StorageService.favBoxName,
      StorageService.historyBoxName,
      StorageService.downloadsBoxName,
      StorageService.settingsBoxName,
    ]) {
      await Hive.openBox(name);
    }
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test(
    'appearance persists and restores with local backup without losing legacy defaults',
    () async {
      final appearance = AppearanceController()..start();
      expect(appearance.value.style, InterfaceStyle.enso);
      expect(appearance.value.autoHideMenus, isTrue);
      await appearance.setStyle(InterfaceStyle.glass);
      await appearance.setAutoHide(false);
      final backup = StorageService.exportFullBackupJson();
      await appearance.setStyle(InterfaceStyle.enso);
      await appearance.setAutoHide(true);
      expect(await StorageService.importFullBackupJson(backup), isTrue);
      appearance.refresh();
      expect(appearance.value.style, InterfaceStyle.glass);
      expect(appearance.value.autoHideMenus, isFalse);
      expect(
        () => BackupCodec.decode(
          '{"favorites":{},"settings":{"interface_style":"unknown"}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BackupCodec.decode(
          '{"favorites":{},"settings":{"auto_hide_menus":"yes"}}',
        ),
        throwsFormatException,
      );
      appearance.dispose();
    },
  );
}
