import 'dart:collection';
import 'package:flutter/material.dart';

@immutable
class FeaturedPalette {
  final Color primary;
  final Color surface;
  final Color onSurface;
  final Color navBackground;
  final Color accent;

  const FeaturedPalette({
    required this.primary,
    required this.surface,
    required this.onSurface,
    required this.navBackground,
    required this.accent,
  });

  factory FeaturedPalette.fromSeed(Color seed, {Brightness brightness = Brightness.dark}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    // Garante contraste suficiente para o header e navegação em qualquer paleta
    final surfaceColor = scheme.surfaceContainerHighest.withOpacity(0.92);
    final isLightSurface = surfaceColor.computeLuminance() > 0.45;
    final foreground = isLightSurface ? const Color(0xFF121216) : const Color(0xFFF5F5F8);

    return FeaturedPalette(
      primary: scheme.primary,
      surface: surfaceColor,
      onSurface: foreground,
      navBackground: Color.alphaBlend(scheme.primary.withOpacity(0.14), scheme.surface),
      accent: scheme.tertiary,
    );
  }

  static FeaturedPalette lerp(FeaturedPalette a, FeaturedPalette b, double t) {
    final surface = Color.lerp(a.surface, b.surface, t)!;
    // Recalcula legibilidade durante toda a transição entre extremos claro/escuro
    final luminance = surface.computeLuminance();
    final safeOnSurface = luminance > 0.25
        ? const Color(0xFF101014)
        : const Color(0xFFFFFFFF);

    return FeaturedPalette(
      primary: Color.lerp(a.primary, b.primary, t)!,
      surface: surface,
      onSurface: safeOnSurface,
      navBackground: Color.lerp(a.navBackground, b.navBackground, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
    );
  }
}

class FeaturedItemData {
  final String id;
  final String title;
  final ImageProvider imageProvider;
  final Color seedColor;

  const FeaturedItemData({
    required this.id,
    required this.title,
    required this.imageProvider,
    required this.seedColor,
  });
}

/// Gerencia cache LRU limitado (máx. 4 entradas) para evitar excesso de memória
/// e prepara imagem + paleta do próximo/anterior destaque antecipadamente.
class FeaturedPreloadController extends ChangeNotifier {
  final int maxCacheEntries;
  final LinkedHashMap<String, FeaturedPalette> _paletteCache = LinkedHashMap();
  final Set<String> _readyImages = <String>{};
  final Set<String> _inFlightPreloads = <String>{};

  FeaturedPreloadController({this.maxCacheEntries = 4});

  bool isItemReady(String id) =>
      _readyImages.contains(id) && _paletteCache.containsKey(id);

  FeaturedPalette getPaletteOrFallback(
      FeaturedItemData item, FeaturedPalette fallback) {
    final cached = _paletteCache.remove(item.id);
    if (cached != null) {
      // Atualiza ordem LRU
      _paletteCache[item.id] = cached;
      return cached;
    }
    return fallback;
  }

  Future<void> warmUpAround({
    required BuildContext context,
    required List<FeaturedItemData> items,
    required int currentIndex,
    Size targetDecodeSize = const Size(720, 420),
  }) async {
    if (items.isEmpty) return;

    final indicesToWarm = <int>{
      currentIndex,
      (currentIndex + 1) % items.length,
      (currentIndex - 1 + items.length) % items.length,
    };

    for (final idx in indicesToWarm) {
      final item = items[idx];
      await _preloadSingle(context, item, targetDecodeSize);
    }
  }

  Future<void> _preloadSingle(
    BuildContext context,
    FeaturedItemData item,
    Size targetDecodeSize,
  ) async {
    if (_inFlightPreloads.contains(item.id) || isItemReady(item.id)) return;
    _inFlightPreloads.add(item.id);

    try {
      // Pré-calcula paleta imediatamente a partir da seed ou metadado sem travar a UI
      if (!_paletteCache.containsKey(item.id)) {
        if (_paletteCache.length >= maxCacheEntries) {
          final oldestKey = _paletteCache.keys.first;
          _paletteCache.remove(oldestKey);
          _readyImages.remove(oldestKey);
        }
        _paletteCache[item.id] = FeaturedPalette.fromSeed(item.seedColor);
      }

      if (context.mounted) {
        final resizedProvider = ResizeImage.resizeIfNeeded(
          targetDecodeSize.width.toInt(),
          null,
          item.imageProvider,
        );
        await precacheImage(resizedProvider, context);
        _readyImages.add(item.id);
        notifyListeners();
      }
    } catch (_) {
      // Mantém apresentação estável usando paleta derivada da seed sem travar a troca
      _readyImages.add(item.id);
    } finally {
      _inFlightPreloads.remove(item.id);
    }
  }
}
