import 'dart:io';
import 'dart:ui' as ui;

/// Decodes only a tiny frame, rejecting HTML and damaged payloads without
/// retaining full-size chapter bitmaps in the download manager.
class ImageFileValidator {
  static Future<bool> isCompleteImage(File file) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      if (!await file.exists() || await file.length() == 0) return false;
      buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 || descriptor.height <= 0) return false;
      codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width < 16 ? descriptor.width : 16,
      );
      image = (await codec.getNextFrame()).image;
      return image.width > 0 && image.height > 0;
    } catch (_) {
      return false;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
