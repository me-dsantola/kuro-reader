import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Headers extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List bytes;
  _ImageResponse(this.bytes);
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest extends Fake implements HttpClientRequest {
  final Uint8List bytes;
  _ImageRequest(this.bytes);
  @override
  HttpHeaders get headers => _Headers();
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
}

class FixtureImageClient extends Fake implements HttpClient {
  final List<Uint8List> images;
  FixtureImageClient(this.images);
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final index = int.tryParse(url.pathSegments.last.split('.').first) ?? 0;
    return _ImageRequest(images[index % images.length]);
  }
}
