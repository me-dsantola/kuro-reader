import 'dart:ui' as ui;

/// Reads encoded metadata without decoding every chapter page to a bitmap.
class LocalPageDimensions {
  static Future<Map<int, double>> read(List<String> paths) async {
    final ratios = <int, double>{};
    for (var i = 0; i < paths.length; i++) {
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      try {
        buffer = await ui.ImmutableBuffer.fromFilePath(paths[i]);
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 0 && descriptor.height > 0) {
          ratios[i] = descriptor.width / descriptor.height;
        }
      } catch (_) {
        // A damaged page keeps a stable estimated extent and a retry action.
      } finally {
        descriptor?.dispose();
        buffer?.dispose();
      }
    }
    return ratios;
  }
}
