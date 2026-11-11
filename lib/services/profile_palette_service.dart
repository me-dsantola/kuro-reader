import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../blobatar/blobatar.dart' as blob;
import '../models/manga_models.dart';

@immutable
class YomiBannerPreset {
  final String id;
  final String title;
  final String subtitle;
  final Color seedColor;
  final Color secondaryColor;

  const YomiBannerPreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.seedColor,
    required this.secondaryColor,
  });
}

const List<YomiBannerPreset> kYomiBannerPresets = [
  YomiBannerPreset(
    id: 'preset:torii_crimson',
    title: 'Torii Carmesim',
    subtitle: 'Sol vermelho, colinas e pétalas de sakura',
    seedColor: Color(0xFFE11D48),
    secondaryColor: Color(0xFFF472B6),
  ),
  YomiBannerPreset(
    id: 'preset:moonlit_library',
    title: 'Biblioteca da Lua',
    subtitle: 'Estante noturna, pagode e lua cheia',
    seedColor: Color(0xFFDC2626),
    secondaryColor: Color(0xFFFB7185),
  ),
  YomiBannerPreset(
    id: 'preset:seinen_eyes',
    title: 'Olhar Seinen',
    subtitle: 'Painéis de mangá sombrios e foco intenso',
    seedColor: Color(0xFFE11D48),
    secondaryColor: Color(0xFFF43F5E),
  ),
  YomiBannerPreset(
    id: 'preset:sakura_night',
    title: 'Sakura Imperial',
    subtitle: 'Noite estrelada em tons magenta e flor de cerejeira',
    seedColor: Color(0xFFEC4899),
    secondaryColor: Color(0xFFF9A8D4),
  ),
  YomiBannerPreset(
    id: 'preset:cyber_shogun',
    title: 'Neo-Tokyo Violeta',
    subtitle: 'Horizonte urbano neon e lua púrpura',
    seedColor: Color(0xFF8B5CF6),
    secondaryColor: Color(0xFFC084FC),
  ),
  YomiBannerPreset(
    id: 'preset:azure_horizon',
    title: 'Horizonte Azul',
    subtitle: 'Céu noturno profundo e brisa oceânica',
    seedColor: Color(0xFF02A9FF),
    secondaryColor: Color(0xFF38BDF8),
  ),
];

YomiBannerPreset? findBannerPreset(String? rawPath) {
  if (rawPath == null) return null;
  final clean = rawPath.trim();
  for (final preset in kYomiBannerPresets) {
    if (preset.id == clean) return preset;
  }
  return null;
}

@immutable
class ProfileAdaptivePalette {
  final Color primary;
  final Color secondary;
  final Color soft;
  final Color surfaceTint;
  final Color bannerDark;
  final double hue;

  const ProfileAdaptivePalette({
    this.primary = const Color(0xFFE11D48),
    this.secondary = const Color(0xFFF472B6),
    this.soft = const Color(0xFFFBCFE8),
    this.surfaceTint = const Color(0xFF1A1016),
    this.bannerDark = const Color(0xFF240914),
    this.hue = 347.0,
  });

  Color get surface => surfaceTint;

  static const ProfileAdaptivePalette defaultEnso = ProfileAdaptivePalette();

  Color get cardSurface => surfaceTint;
  Color get softTint => soft;

  factory ProfileAdaptivePalette.fromColor(Color seedColor) {
    final hsv = HSVColor.fromColor(seedColor);
    final bool isAchromatic = hsv.saturation < 0.12;
    final double h = isAchromatic ? 347.0 : hsv.hue;
    final double s = isAchromatic ? 0.82 : hsv.saturation.clamp(0.65, 0.90);
    final double v = isAchromatic ? 0.88 : hsv.value.clamp(0.82, 0.96);

    final primary = HSVColor.fromAHSV(1.0, h, s, v).toColor();
    final secondary = HSVColor.fromAHSV(
      1.0,
      (h + 10.0) % 360.0,
      (s * 0.62).clamp(0.38, 0.72),
      0.95,
    ).toColor();
    final soft = HSVColor.fromAHSV(1.0, h, 0.26, 0.98).toColor();
    final surfaceTint = Color.lerp(const Color(0xFF121217), primary, 0.14)!;
    final bannerDark = Color.lerp(const Color(0xFF070709), primary, 0.24)!;

    return ProfileAdaptivePalette(
      primary: primary,
      secondary: secondary,
      soft: soft,
      surfaceTint: surfaceTint,
      bannerDark: bannerDark,
      hue: h,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileAdaptivePalette &&
          other.primary == primary &&
          other.secondary == secondary &&
          other.soft == soft &&
          other.surfaceTint == surfaceTint &&
          other.bannerDark == bannerDark &&
          other.hue == hue;

  @override
  int get hashCode => Object.hash(
    primary,
    secondary,
    soft,
    surfaceTint,
    bannerDark,
    hue,
  );
}

class ProfilePaletteService {
  static final Map<String, ProfileAdaptivePalette> _cache = {};

  /// Global notifier that drives adaptive theme colors across ALL pages and the YOMI logo.
  static final ValueNotifier<ProfileAdaptivePalette> paletteNotifier =
      ValueNotifier<ProfileAdaptivePalette>(ProfileAdaptivePalette.defaultEnso);

  static ValueListenable<UserProfile>? _boundProfileNotifier;

  static void bindToProfileNotifier(
    ValueListenable<UserProfile> profileListenable,
  ) {
    if (identical(_boundProfileNotifier, profileListenable)) {
      refreshGlobalPalette(profileListenable.value);
      return;
    }
    _boundProfileNotifier?.removeListener(_onBoundProfileChanged);
    _boundProfileNotifier = profileListenable;
    _boundProfileNotifier!.addListener(_onBoundProfileChanged);
    refreshGlobalPalette(profileListenable.value);
  }

  static void _onBoundProfileChanged() {
    final notifier = _boundProfileNotifier;
    if (notifier != null) {
      refreshGlobalPalette(notifier.value);
    }
  }

  static Future<void> refreshGlobalPalette(UserProfile profile) async {
    paletteNotifier.value = synchronousFallbackFor(profile);
    final resolved = await resolveForProfile(profile);
    if (_boundProfileNotifier == null ||
        _boundProfileNotifier!.value.toMap().toString() ==
            profile.toMap().toString()) {
      paletteNotifier.value = resolved;
    }
  }

  static ImageProvider? resolveImageProvider(String? rawSource) {
    if (rawSource == null) return null;
    final src = rawSource.trim();
    if (src.isEmpty || src.startsWith('preset:')) return null;

    if (src.startsWith('data:image/')) {
      final comma = src.indexOf(',');
      if (comma != -1 && comma + 1 < src.length) {
        try {
          final bytes = base64Decode(src.substring(comma + 1));
          return MemoryImage(bytes);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    if (src.startsWith('http://') || src.startsWith('https://')) {
      final safeUrl = yomiSafeImageUrl(src);
      if (safeUrl.isEmpty) return null;
      return NetworkImage(safeUrl);
    }

    if (!kIsWeb) {
      final cleanPath = src.startsWith('file://')
          ? Uri.tryParse(src)?.toFilePath() ?? src
          : src;
      final file = File(cleanPath);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return null;
  }

  static ProfileAdaptivePalette synchronousFallbackFor(UserProfile profile) {
    if (profile.customAccentColor != null) {
      return ProfileAdaptivePalette.fromColor(
        Color(profile.customAccentColor! | 0xFF000000),
      );
    }
    final avatarKey = profile.avatarImagePath?.trim() ?? '';
    if (avatarKey.isNotEmpty && _cache.containsKey(avatarKey)) {
      return _cache[avatarKey]!;
    }
    final bannerKey = profile.bannerImagePath?.trim() ?? '';
    final preset = findBannerPreset(bannerKey);
    if (preset != null && avatarKey.isEmpty && !profile.useBlobatarAsAvatar) {
      return ProfileAdaptivePalette.fromColor(preset.seedColor);
    }
    if (bannerKey.isNotEmpty && _cache.containsKey(bannerKey)) {
      return _cache[bannerKey]!;
    }
    if (profile.useBlobatarAsAvatar || avatarKey.isEmpty) {
      try {
        final resolved = blob.resolve(
          profile.effectiveBlobatarSeed,
          blob.BlobatarOptions(
            hue: profile.blobatarHue != null && profile.blobatarHue! >= 0
                ? profile.blobatarHue
                : null,
          ),
        );
        final headHex = resolved.palette[blob.colorHead];
        if (headHex != null && headHex.startsWith('#') && headHex.length == 7) {
          final colorInt = int.tryParse(headHex.substring(1), radix: 16);
          if (colorInt != null) {
            return ProfileAdaptivePalette.fromColor(
              Color(colorInt | 0xFF000000),
            );
          }
        }
      } catch (_) {}
    }
    if (preset != null) {
      return ProfileAdaptivePalette.fromColor(preset.seedColor);
    }
    return const ProfileAdaptivePalette();
  }

  static Future<ProfileAdaptivePalette> resolveForProfile(
    UserProfile profile,
  ) async {
    if (profile.customAccentColor != null) {
      return ProfileAdaptivePalette.fromColor(
        Color(profile.customAccentColor! | 0xFF000000),
      );
    }

    // 1. Try extracting dominant vibrant color from the profile photo first.
    final avatarSrc = profile.avatarImagePath?.trim();
    if (avatarSrc != null && avatarSrc.isNotEmpty && !profile.useBlobatarAsAvatar) {
      final fromAvatar = await _extractFromSource(
        avatarSrc,
        allowLowSaturation: false,
      );
      if (fromAvatar != null) return fromAvatar;
    }

    // 2. If the profile photo is monochrome/greyscale or unset, try the banner image or preset next.
    final bannerSrc = profile.bannerImagePath?.trim();
    final bannerPreset = findBannerPreset(bannerSrc);
    if (bannerSrc != null &&
        bannerSrc.isNotEmpty &&
        !bannerSrc.startsWith('preset:')) {
      final fromBanner = await _extractFromSource(
        bannerSrc,
        allowLowSaturation: true,
      );
      if (fromBanner != null) return fromBanner;
    }

    // 3. Re-try avatar allowing subtle tints if banner wasn't an image.
    if (avatarSrc != null && avatarSrc.isNotEmpty && !profile.useBlobatarAsAvatar) {
      final subtleAvatar = await _extractFromSource(
        avatarSrc,
        allowLowSaturation: true,
      );
      if (subtleAvatar != null) return subtleAvatar;
    }

    if (bannerPreset != null && !profile.useBlobatarAsAvatar) {
      return ProfileAdaptivePalette.fromColor(bannerPreset.seedColor);
    }

    return synchronousFallbackFor(profile);
  }

  /// Synchronous initial palette for a [Manga] detail screen before async cover extraction finishes.
  static ProfileAdaptivePalette synchronousFallbackForManga(Manga manga) {
    final mangaCacheKey = 'manga:${manga.compositeId}';
    if (_cache.containsKey(mangaCacheKey)) {
      return _cache[mangaCacheKey]!;
    }
    for (final url in manga.getAllCandidateCoverUrls(highRes: false)) {
      if (_cache.containsKey(url)) {
        return _cache[url]!;
      }
    }
    return paletteNotifier.value;
  }

  /// Extracts a vibrant adaptive palette directly from the [manga]'s cover image.
  static Future<ProfileAdaptivePalette> resolveForManga(Manga manga) async {
    final mangaCacheKey = 'manga:${manga.compositeId}';
    if (_cache.containsKey(mangaCacheKey)) {
      return _cache[mangaCacheKey]!;
    }

    final candidates = manga
        .getAllCandidateCoverUrls(highRes: false)
        .take(3)
        .toList();

    for (final url in candidates) {
      final vibrant = await _extractFromSource(
        url,
        allowLowSaturation: false,
      );
      if (vibrant != null) {
        _cache[mangaCacheKey] = vibrant;
        return vibrant;
      }
    }

    for (final url in candidates) {
      final subtle = await _extractFromSource(
        url,
        allowLowSaturation: true,
      );
      if (subtle != null) {
        _cache[mangaCacheKey] = subtle;
        return subtle;
      }
    }

    return paletteNotifier.value;
  }

  static Future<ProfileAdaptivePalette?> _extractFromSource(
    String source, {
    required bool allowLowSaturation,
  }) async {
    final cacheKey = '$source|$allowLowSaturation';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    final baseProvider = resolveImageProvider(source);
    if (baseProvider == null) return null;

    final provider = ResizeImage(baseProvider, width: 48, height: 48);
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    final timer = Timer(const Duration(seconds: 4), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!completer.isCompleted) {
          completer.complete(info.image);
        }
      },
      onError: (Object _, StackTrace? _) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);

    try {
      final image = await completer.future;
      if (image == null) return null;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;

      final bytes = byteData.buffer.asUint8List();
      const int bins = 24;
      final List<double> binWeights = List.filled(bins, 0.0);
      final List<double> binR = List.filled(bins, 0.0);
      final List<double> binG = List.filled(bins, 0.0);
      final List<double> binB = List.filled(bins, 0.0);

      for (int i = 0; i + 3 < bytes.length; i += 4) {
        final int a = bytes[i + 3];
        if (a < 120) continue;
        final int r = bytes[i];
        final int g = bytes[i + 1];
        final int b = bytes[i + 2];

        final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
        if (hsv.value < 0.14 || hsv.value > 0.97) continue;
        if (hsv.saturation < (allowLowSaturation ? 0.08 : 0.18)) continue;

        final double weight =
            math.pow(hsv.saturation, 1.4).toDouble() *
            (0.4 + 0.6 * math.sin(hsv.value * math.pi));
        final int bin = ((hsv.hue / 360.0) * bins).floor().clamp(0, bins - 1);
        binWeights[bin] += weight;
        binR[bin] += r * weight;
        binG[bin] += g * weight;
        binB[bin] += b * weight;
      }

      int bestBin = -1;
      double bestWeight = 0.0;
      for (int b = 0; b < bins; b++) {
        if (binWeights[b] > bestWeight) {
          bestWeight = binWeights[b];
          bestBin = b;
        }
      }

      if (bestBin == -1 || bestWeight <= 0.05) {
        return null;
      }

      final int avgR = (binR[bestBin] / bestWeight).round().clamp(0, 255);
      final int avgG = (binG[bestBin] / bestWeight).round().clamp(0, 255);
      final int avgB = (binB[bestBin] / bestWeight).round().clamp(0, 255);
      final palette = ProfileAdaptivePalette.fromColor(
        Color.fromARGB(255, avgR, avgG, avgB),
      );
      _cache[cacheKey] = palette;
      _cache[source] = palette;
      return palette;
    } catch (_) {
      return null;
    } finally {
      timer.cancel();
      stream.removeListener(listener);
    }
  }
}

class ProfileImagePicker {
  static const MethodChannel _channel = MethodChannel('yomi/image_picker');

  /// Opens the native device image picker (Android Gallery or Windows File Dialog)
  /// and copies the selected image into the app's persistent local directory.
  static Future<String?> pickLocalImage({required String slot}) async {
    if (kIsWeb) return null;

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final String? pickedPath = await _channel.invokeMethod<String>(
          'pickImage',
        );
        if (pickedPath != null && pickedPath.trim().isNotEmpty) {
          return await _persistLocalCopy(pickedPath.trim(), slot: slot);
        }
        return null;
      }

      if (defaultTargetPlatform == TargetPlatform.windows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-STA',
          '-Command',
          '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; '
              'Add-Type -AssemblyName System.Windows.Forms; '
              '\$owner = New-Object System.Windows.Forms.Form; '
              '\$owner.TopMost = \$true; '
              '\$dlg = New-Object System.Windows.Forms.OpenFileDialog; '
              '\$dlg.Title = "Selecionar imagem para o YOMI"; '
              '\$dlg.Filter = "Imagens (*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp)|*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp|Todos os arquivos (*.*)|*.*"; '
              'if (\$dlg.ShowDialog(\$owner) -eq [System.Windows.Forms.DialogResult]::OK) { '
              '  [Console]::Out.WriteLine(\$dlg.FileName) '
              '} '
              '\$owner.Dispose()',
        ]);
        final selected = result.stdout.toString().trim();
        if (selected.isNotEmpty && File(selected).existsSync()) {
          return await _persistLocalCopy(selected, slot: slot);
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<String> _persistLocalCopy(
    String sourcePath, {
    required String slot,
  }) async {
    try {
      final srcFile = File(sourcePath);
      if (!srcFile.existsSync()) return sourcePath;
      final supportDir = await getApplicationSupportDirectory();
      final mediaDir = Directory('${supportDir.path}/profile_media');
      if (!mediaDir.existsSync()) {
        await mediaDir.create(recursive: true);
      }
      final extIndex = sourcePath.lastIndexOf('.');
      final ext = extIndex != -1 && extIndex < sourcePath.length - 1
          ? sourcePath.substring(extIndex)
          : '.jpg';
      final targetPath =
          '${mediaDir.path}/${slot}_${DateTime.now().millisecondsSinceEpoch}$ext';
      await srcFile.copy(targetPath);
      return targetPath;
    } catch (_) {
      return sourcePath;
    }
  }
}
