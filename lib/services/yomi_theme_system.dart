import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'storage_service.dart';

enum YomiThemeId {
  whiteMinimalist('white_minimalist', 'Branco Minimalista'),
  graphite('graphite', 'Cinza Grafite'),
  amoled('amoled', 'Preto AMOLED'),
  nightBlue('night_blue', 'Azul Noturno'),
  nebulaPurple('nebula_purple', 'Roxo Nebulosa'),
  emeraldGreen('emerald_green', 'Verde Esmeralda'),
  crimsonRed('crimson_red', 'Vermelho Carmesim'),
  sepia('sepia', 'Sépia');

  final String key;
  final String label;
  const YomiThemeId(this.key, this.label);

  static YomiThemeId fromKey(String? key) {
    if (key == null) return YomiThemeId.amoled;
    for (final id in YomiThemeId.values) {
      if (id.key == key || id.name == key) return id;
    }
    return YomiThemeId.amoled;
  }
}

@immutable
class YomiThemeTokens {
  final YomiThemeId id;
  final String name;
  final bool isLight;
  final Color background;
  final Color surface;
  final Color cardSurface;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color accentPrimary;
  final Color accentSecondary;

  const YomiThemeTokens({
    required this.id,
    required this.name,
    required this.isLight,
    required this.background,
    required this.surface,
    required this.cardSurface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.accentPrimary,
    required this.accentSecondary,
  });

  Brightness get brightness => isLight ? Brightness.light : Brightness.dark;

  YomiThemeTokens copyWith({
    Color? accentPrimary,
    Color? accentSecondary,
  }) {
    return YomiThemeTokens(
      id: id,
      name: name,
      isLight: isLight,
      background: background,
      surface: surface,
      cardSurface: cardSurface,
      surfaceElevated: surfaceElevated,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      border: border,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentSecondary: accentSecondary ?? this.accentSecondary,
    );
  }

  /// Adapta exclusivamente os detalhes (acentos) à cor extraída da obra,
  /// preservando rigorosamente o fundo e a identidade da superfície do tema base.
  YomiThemeTokens withReactiveAccent(Color? rawColor, {required bool enabled}) {
    if (!enabled || rawColor == null) return this;

    final tunedPrimary = _tuneForContrast(rawColor, isLight);
    final hsv = HSVColor.fromColor(tunedPrimary);
    final tunedSecondary = HSVColor.fromAHSV(
      1.0,
      (hsv.hue + 14.0) % 360.0,
      (hsv.saturation * 0.75).clamp(0.40, 0.85),
      isLight ? (hsv.value * 1.15).clamp(0.60, 0.95) : 0.96,
    ).toColor();

    return copyWith(
      accentPrimary: tunedPrimary,
      accentSecondary: tunedSecondary,
    );
  }

  static Color _tuneForContrast(Color color, bool isLightTheme) {
    final hsv = HSVColor.fromColor(color);
    if (isLightTheme) {
      // Em temas claros (fundo branco/sépia), garantir tom mais escuro e saturado (contraste mínimo 3:1)
      final v = hsv.value.clamp(0.35, 0.65);
      final s = hsv.saturation.clamp(0.70, 1.0);
      return HSVColor.fromAHSV(1.0, hsv.hue, s, v).toColor();
    } else {
      // Em temas escuros (AMOLED/Grafite), garantir luminosidade vívida contra o preto
      final v = hsv.value.clamp(0.82, 0.98);
      final s = hsv.saturation.clamp(0.65, 0.95);
      return HSVColor.fromAHSV(1.0, hsv.hue, s, v).toColor();
    }
  }

  static const YomiThemeTokens whiteMinimalist = YomiThemeTokens(
    id: YomiThemeId.whiteMinimalist,
    name: 'Branco Minimalista',
    isLight: true,
    background: Color(0xFFF8F9FA),
    surface: Color(0xFFFFFFFF),
    cardSurface: Color(0xFFF1F3F5),
    surfaceElevated: Color(0xFFE9ECEF),
    textPrimary: Color(0xFF18191B),
    textSecondary: Color(0xFF5F6672),
    border: Color(0xFFDFE3E8),
    accentPrimary: Color(0xFFE11D48),
    accentSecondary: Color(0xFFF43F5E),
  );

  static const YomiThemeTokens graphite = YomiThemeTokens(
    id: YomiThemeId.graphite,
    name: 'Cinza Grafite',
    isLight: false,
    background: Color(0xFF1E1F22),
    surface: Color(0xFF2B2D31),
    cardSurface: Color(0xFF313338),
    surfaceElevated: Color(0xFF383A40),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFF949BA4),
    border: Color(0x33FFFFFF),
    accentPrimary: Color(0xFFE11D48),
    accentSecondary: Color(0xFFF472B6),
  );

  static const YomiThemeTokens amoled = YomiThemeTokens(
    id: YomiThemeId.amoled,
    name: 'Preto AMOLED',
    isLight: false,
    background: Color(0xFF070709),
    surface: Color(0xFF0F0F14),
    cardSurface: Color(0xFF121217),
    surfaceElevated: Color(0xFF181820),
    textPrimary: Color(0xFFFAFAFA),
    textSecondary: Color(0xFF9E9EA7),
    border: Color(0x24FFFFFF),
    accentPrimary: Color(0xFFE11D48),
    accentSecondary: Color(0xFFF472B6),
  );

  static const YomiThemeTokens nightBlue = YomiThemeTokens(
    id: YomiThemeId.nightBlue,
    name: 'Azul Noturno',
    isLight: false,
    background: Color(0xFF080E1E),
    surface: Color(0xFF101C38),
    cardSurface: Color(0xFF17264C),
    surfaceElevated: Color(0xFF1E3260),
    textPrimary: Color(0xFFF0F6FF),
    textSecondary: Color(0xFF8BA5CC),
    border: Color(0x3338BDF8),
    accentPrimary: Color(0xFF38BDF8),
    accentSecondary: Color(0xFF7DD3FC),
  );

  static const YomiThemeTokens nebulaPurple = YomiThemeTokens(
    id: YomiThemeId.nebulaPurple,
    name: 'Roxo Nebulosa',
    isLight: false,
    background: Color(0xFF10071A),
    surface: Color(0xFF1D0E2E),
    cardSurface: Color(0xFF27133D),
    surfaceElevated: Color(0xFF341A52),
    textPrimary: Color(0xFFF9F5FF),
    textSecondary: Color(0xFFBFABDE),
    border: Color(0x33C084FC),
    accentPrimary: Color(0xFFC084FC),
    accentSecondary: Color(0xFFE9D5FF),
  );

  static const YomiThemeTokens emeraldGreen = YomiThemeTokens(
    id: YomiThemeId.emeraldGreen,
    name: 'Verde Esmeralda',
    isLight: false,
    background: Color(0xFF06140E),
    surface: Color(0xFF0E241B),
    cardSurface: Color(0xFF143326),
    surfaceElevated: Color(0xFF1B4232),
    textPrimary: Color(0xFFF0FDF4),
    textSecondary: Color(0xFF86EFAC),
    border: Color(0x3334D399),
    accentPrimary: Color(0xFF10B981),
    accentSecondary: Color(0xFF34D399),
  );

  static const YomiThemeTokens crimsonRed = YomiThemeTokens(
    id: YomiThemeId.crimsonRed,
    name: 'Vermelho Carmesim',
    isLight: false,
    background: Color(0xFF140508),
    surface: Color(0xFF22090F),
    cardSurface: Color(0xFF2B0C14),
    surfaceElevated: Color(0xFF3B101B),
    textPrimary: Color(0xFFFFF1F2),
    textSecondary: Color(0xFFFDA4AF),
    border: Color(0x33F43F5E),
    accentPrimary: Color(0xFFE11D48),
    accentSecondary: Color(0xFFFB7185),
  );

  static const YomiThemeTokens sepia = YomiThemeTokens(
    id: YomiThemeId.sepia,
    name: 'Sépia',
    isLight: true,
    background: Color(0xFFF4ECD8),
    surface: Color(0xFFEBE0C8),
    cardSurface: Color(0xFFE2D4BA),
    surfaceElevated: Color(0xFFD6C6A8),
    textPrimary: Color(0xFF2B211B),
    textSecondary: Color(0xFF6E5D52),
    border: Color(0xFFD0BF9F),
    accentPrimary: Color(0xFFA65D2D),
    accentSecondary: Color(0xFFC47B46),
  );

  static YomiThemeTokens forId(YomiThemeId id) {
    return switch (id) {
      YomiThemeId.whiteMinimalist => whiteMinimalist,
      YomiThemeId.graphite => graphite,
      YomiThemeId.amoled => amoled,
      YomiThemeId.nightBlue => nightBlue,
      YomiThemeId.nebulaPurple => nebulaPurple,
      YomiThemeId.emeraldGreen => emeraldGreen,
      YomiThemeId.crimsonRed => crimsonRed,
      YomiThemeId.sepia => sepia,
    };
  }
}

/// Controlador reativo que gerencia o tema global ativo e preferências de cores reativas e ambilight.
class YomiThemeController extends ValueNotifier<YomiThemeTokens> {
  static final instance = YomiThemeController._();

  static const String themeKey = 'active_theme_id';
  static const String reactiveColorsKey = 'reactive_colors_enabled';
  static const String ambilightKey = 'ambilight_enabled';

  bool _reactiveColors = true;
  bool _ambilight = true;
  Color? _activeReactiveColor;

  YomiThemeController._() : super(YomiThemeTokens.amoled);

  bool get reactiveColorsEnabled => _reactiveColors;
  bool get ambilightEnabled => _ambilight;
  Color? get activeReactiveColor => _activeReactiveColor;

  void start() {
    refresh();
    if (Hive.isBoxOpen(StorageService.settingsBoxName)) {
      StorageService.settingsBox.watch().listen((event) {
        if ([themeKey, reactiveColorsKey, ambilightKey].contains(event.key)) {
          refresh();
        }
      });
    }
  }

  void refresh() {
    if (!Hive.isBoxOpen(StorageService.settingsBoxName)) return;
    final box = StorageService.settingsBox;
    final rawTheme = box.get(themeKey, defaultValue: 'amoled') as String?;
    final themeId = YomiThemeId.fromKey(rawTheme);
    _reactiveColors = box.get(reactiveColorsKey, defaultValue: true) != false;
    _ambilight = box.get(ambilightKey, defaultValue: true) != false;

    final baseTokens = YomiThemeTokens.forId(themeId);
    value = baseTokens.withReactiveAccent(
      _activeReactiveColor,
      enabled: _reactiveColors,
    );
  }

  Future<void> setTheme(YomiThemeId themeId) async {
    if (Hive.isBoxOpen(StorageService.settingsBoxName)) {
      await StorageService.settingsBox.put(themeKey, themeId.key);
    }
    refresh();
  }

  Future<void> setReactiveColors(bool enabled) async {
    if (Hive.isBoxOpen(StorageService.settingsBoxName)) {
      await StorageService.settingsBox.put(reactiveColorsKey, enabled);
    }
    refresh();
  }

  Future<void> setAmbilight(bool enabled) async {
    if (Hive.isBoxOpen(StorageService.settingsBoxName)) {
      await StorageService.settingsBox.put(ambilightKey, enabled);
    }
    refresh();
  }

  void updateReactiveAccent(Color? color) {
    if (_activeReactiveColor == color) return;
    _activeReactiveColor = color;
    final baseTokens = YomiThemeTokens.forId(value.id);
    value = baseTokens.withReactiveAccent(color, enabled: _reactiveColors);
  }
}
