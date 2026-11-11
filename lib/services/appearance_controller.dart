import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'storage_service.dart';

enum InterfaceStyle { enso, glass }

@immutable
class AppearancePreferences {
  final InterfaceStyle style;
  final bool autoHideMenus;
  const AppearancePreferences({
    this.style = InterfaceStyle.glass,
    this.autoHideMenus = true,
  });
}

class AppearanceController extends ValueNotifier<AppearancePreferences> {
  static final instance = AppearanceController();
  StreamSubscription<BoxEvent>? _subscription;
  AppearanceController() : super(const AppearancePreferences());

  void start() {
    refresh();
    _subscription ??= StorageService.settingsBox.watch().listen((event) {
      if (event.key == 'interface_style' || event.key == 'auto_hide_menus') {
        refresh();
      }
    });
  }

  void refresh() {
    if (!Hive.isBoxOpen(StorageService.settingsBoxName)) return;
    final box = StorageService.settingsBox;
    final rawStyle = box.get('interface_style');
    final style = rawStyle == 'enso'
        ? InterfaceStyle.enso
        : InterfaceStyle.glass;
    final autoHide = box.get('auto_hide_menus', defaultValue: true) != false;
    if (value.style != style || value.autoHideMenus != autoHide) {
      value = AppearancePreferences(style: style, autoHideMenus: autoHide);
    }
  }

  Future<void> setStyle(InterfaceStyle style) async {
    await StorageService.settingsBox.put('interface_style', style.name);
    refresh();
  }

  Future<void> setAutoHide(bool enabled) async {
    await StorageService.settingsBox.put('auto_hide_menus', enabled);
    refresh();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
