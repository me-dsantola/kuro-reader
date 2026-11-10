import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../services/reader_image_session.dart';

class ReaderPageProvider extends ImageProvider<ReaderPageProvider> {
  final ReaderImageSession session;
  final int index;
  final int attempt;
  const ReaderPageProvider(this.session, this.index, {this.attempt = 0});

  @override
  Future<ReaderPageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ReaderPageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await session.pageBytes(index);
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // A valid image signature does not prove the payload is decodable.
      await session.invalidate(index);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPageProvider &&
      identical(session, other.session) &&
      index == other.index &&
      attempt == other.attempt;

  @override
  int get hashCode => Object.hash(session, index, attempt);
}
