import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'storage_service.dart';

enum InterfaceStyle { enso, glass }

@immutable
class AppearancePreferences {
  final InterfaceStyle style;
  final bool autoHideMenus;
  final bool tabTransitions;
  final bool reactiveReader;
  const AppearancePreferences({
    this.style = InterfaceStyle.glass,
    this.autoHideMenus = true,
    this.tabTransitions = true,
    this.reactiveReader = true,
  });
}

class AppearanceController extends ValueNotifier<AppearancePreferences> {
  static final instance = AppearanceController();
  StreamSubscription<BoxEvent>? _subscription;
  AppearanceController() : super(const AppearancePreferences());

  void start() {
    refresh();
    _subscription ??= StorageService.settingsBox.watch().listen((event) {
      if ([
        'interface_style',
        'auto_hide_menus',
        'tab_transitions',
        'reactive_reader',
      ].contains(event.key)) {
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
    final transitions = box.get('tab_transitions', defaultValue: true) != false;
    final reactive = box.get('reactive_reader', defaultValue: true) != false;
    if (value.style != style ||
        value.autoHideMenus != autoHide ||
        value.tabTransitions != transitions ||
        value.reactiveReader != reactive) {
      value = AppearancePreferences(
        style: style,
        autoHideMenus: autoHide,
        tabTransitions: transitions,
        reactiveReader: reactive,
      );
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

  Future<void> setTabTransitions(bool enabled) async {
    await StorageService.settingsBox.put('tab_transitions', enabled);
    refresh();
  }

  Future<void> setReactiveReader(bool enabled) async {
    await StorageService.settingsBox.put('reactive_reader', enabled);
    refresh();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
