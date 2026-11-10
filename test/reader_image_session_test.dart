import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuro_reader/services/reader_image_session.dart';
import 'package:kuro_reader/widgets/reader_page_provider.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAgCAIAAACU62+bAAAAHElEQVR4nGN4KOtBEmIY1TCqYVTDqIZRDSNBAwBtMowfZv2fjwAAAABJRU5ErkJggg==',
);

Future<ImageInfo> _resolve(ImageProvider provider) {
  final result = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, sync) {
      stream.removeListener(listener);
      result.complete(info);
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      result.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test(
    'revisiting a decoded page after bitmap eviction does not request it again',
    () async {
      var calls = 0;
      final session = ReaderImageSession(
        urls: ['https://pages.example/0.png'],
        client: MockClient((_) async {
          calls++;
          // The simulated source becomes unavailable after the first read.
          return calls == 1
              ? http.Response.bytes(_png, 200)
              : http.Response('offline', 503);
        }),
      );
      try {
        final webtoon = await _resolve(
          ResizeImage(ReaderPageProvider(session, 0), width: 8),
        );
        expect(webtoon.image.width, 8);
        webtoon.dispose();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        final paged = await _resolve(
          ResizeImage(ReaderPageProvider(session, 0), width: 8),
        );
        expect(paged.image.height, 16);
        paged.dispose();
        expect(calls, 1);
      } finally {
        session.close();
      }
    },
  );

  test(
    'local pages never request the network even when a client is available',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yomi_local_session_',
      );
      var calls = 0;
      final file = File('${directory.path}/page.png');
      await file.writeAsBytes(_png);
      final session = ReaderImageSession(
        localPaths: [file.path],
        client: MockClient((_) async {
          calls++;
          return http.Response('offline', 503);
        }),
      );
      try {
        expect(await session.pageBytes(0), _png);
        expect(await session.pageBytes(0), _png);
        expect(calls, 0);
      } finally {
        session.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('concurrent consumers share one page request', () async {
    var calls = 0;
    final session = ReaderImageSession(
      urls: ['https://pages.example/0.png'],
      client: MockClient((_) async {
        calls++;
        return http.Response.bytes(_png, 200);
      }),
    );
    final results = await Future.wait([
      session.pageBytes(0),
      session.pageBytes(0),
    ]);
    expect(results.every((bytes) => identical(bytes, results.first)), isTrue);
    expect(calls, 1);
    session.close();
  });

  test(
    'HTML responses are not cached as images and use the existing fallback',
    () async {
      var calls = 0;
      final session = ReaderImageSession(
        urls: ['https://pages.example/0.png'],
        client: MockClient((request) async {
          calls++;
          return request.url.host == 'pages.example'
              ? http.Response('<html>upstream error</html>', 200)
              : http.Response.bytes(_png, 200);
        }),
      );
      expect(await session.pageBytes(0), _png);
      expect(calls, 2);
      session.close();
    },
  );

  test(
    'an expired page refreshes its source and recovers automatically',
    () async {
      var refreshes = 0;
      final session = ReaderImageSession(
        urls: ['https://old.example/0.png'],
        reloadUrls: () async {
          refreshes++;
          return ['https://fresh.example/0.png'];
        },
        client: MockClient(
          (request) async => request.url.host == 'fresh.example'
              ? http.Response.bytes(_png, 200)
              : http.Response('unavailable', 503),
        ),
      );
      expect(await session.pageBytes(0), _png);
      expect(refreshes, 1);
      session.close();
    },
  );

  test(
    'manual retry remains available after an unsuccessful automatic refresh',
    () async {
      var refreshes = 0;
      final session = ReaderImageSession(
        urls: ['https://old.example/0.png'],
        reloadUrls: () async => [
          ++refreshes == 1
              ? 'https://old.example/0.png'
              : 'https://fresh.example/0.png',
        ],
        client: MockClient(
          (request) async => request.url.host == 'fresh.example'
              ? http.Response.bytes(_png, 200)
              : http.Response('expired', 503),
        ),
      );
      await expectLater(session.pageBytes(0), throwsFormatException);
      await session.retry(0);
      expect(await session.pageBytes(0), _png);
      expect(refreshes, 2);
      session.close();
    },
  );

  test('concurrent expired pages share one metadata refresh', () async {
    var refreshes = 0;
    final ready = Completer<void>();
    final release = Completer<void>();
    final session = ReaderImageSession(
      urls: [for (var i = 0; i < 3; i++) 'https://old.example/$i.png'],
      reloadUrls: () async {
        refreshes++;
        ready.complete();
        await release.future;
        return [for (var i = 0; i < 3; i++) 'https://fresh.example/$i.png'];
      },
      client: MockClient(
        (request) async => request.url.host == 'fresh.example'
            ? http.Response.bytes(_png, 200)
            : http.Response('expired', 503),
      ),
    );
    final pages = Future.wait([
      for (var i = 0; i < 3; i++) session.pageBytes(i),
    ]);
    await ready.future;
    release.complete();
    expect((await pages).length, 3);
    expect(refreshes, 1);
    session.close();
  });

  test('rate limiting stops fallback requests and metadata refresh', () async {
    var calls = 0;
    var refreshes = 0;
    final session = ReaderImageSession(
      urls: ['https://pages.example/0.png'],
      reloadUrls: () async {
        refreshes++;
        return ['https://new.example/0.png'];
      },
      client: MockClient((_) async {
        calls++;
        return http.Response('wait', 429);
      }),
    );
    await expectLater(session.pageBytes(0), throwsFormatException);
    expect(calls, 1);
    expect(refreshes, 0);
    session.close();
  });

  test(
    'disk cache survives memory eviction and closes without orphan files',
    () async {
      final root = await Directory.systemTemp.createTemp('yomi_disk_test_');
      final cleaned = Completer<void>();
      var calls = 0;
      final session = ReaderImageSession(
        urls: ['https://pages.example/0.png', 'https://pages.example/1.png'],
        maxCacheBytes: _png.length,
        createCacheDirectory: () => root.createTemp('session_'),
        client: MockClient((_) async {
          calls++;
          return calls <= 2
              ? http.Response.bytes(_png, 200)
              : http.Response('offline', 503);
        }),
      );
      try {
        await session.pageBytes(0);
        await session.pageBytes(1);
        expect(await session.pageBytes(0), _png);
        expect(calls, 2);
        final directory = (await root.list().toList()).single as Directory;
        final watch = root.watch().listen((event) {
          if (event is FileSystemDeleteEvent && !cleaned.isCompleted)
            cleaned.complete();
        });
        session.close();
        await cleaned.future.timeout(const Duration(seconds: 5));
        await watch.cancel();
        expect(await directory.exists(), isFalse);
        await expectLater(session.pageBytes(0), throwsStateError);
      } finally {
        session.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'unavailable optional disk cache never fails a successful page',
    () async {
      final session = ReaderImageSession(
        urls: ['https://pages.example/0.png'],
        createCacheDirectory: () async =>
            throw const FileSystemException('full'),
        client: MockClient((_) async => http.Response.bytes(_png, 200)),
      );
      expect(await session.pageBytes(0), _png);
      session.close();
    },
  );

  test('a failed decode evicts corrupt bytes before a new attempt', () async {
    var calls = 0;
    final corrupt = _png.sublist(0, 20);
    final session = ReaderImageSession(
      urls: ['https://pages.example/0.png'],
      client: MockClient(
        (_) async => http.Response.bytes(++calls == 1 ? corrupt : _png, 200),
      ),
    );
    await expectLater(
      _resolve(ReaderPageProvider(session, 0)),
      throwsA(anything),
    );
    PaintingBinding.instance.imageCache.clear();
    final image = await _resolve(ReaderPageProvider(session, 0, attempt: 1));
    image.dispose();
    expect(calls, 2);
    session.close();
  });

  test('chapter fetching has at most three active requests', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var active = 0;
    var peak = 0;
    final session = ReaderImageSession(
      urls: [for (var i = 0; i < 6; i++) 'https://pages.example/$i.png'],
      client: MockClient((_) async {
        active++;
        if (active > peak) peak = active;
        if (active == 3 && !started.isCompleted) started.complete();
        await release.future;
        active--;
        return http.Response.bytes(_png, 200);
      }),
    );
    final pages = Future.wait([
      for (var i = 0; i < 6; i++) session.pageBytes(i),
    ]);
    await started.future;
    expect(peak, 3);
    release.complete();
    expect(await pages, hasLength(6));
    expect(peak, 3);
    session.close();
  });

  test(
    'compressed cache evicts the least recently used page within its budget',
    () async {
      final requested = <String>[];
      final session = ReaderImageSession(
        maxCacheBytes: _png.length * 2,
        urls: [for (var i = 0; i < 3; i++) 'https://pages.example/$i.png'],
        client: MockClient((request) async {
          requested.add(request.url.path);
          return http.Response.bytes(_png, 200);
        }),
      );
      await session.pageBytes(0);
      await session.pageBytes(1);
      await session.pageBytes(0); // Keep page 0, evict page 1 next.
      await session.pageBytes(2);
      await session.pageBytes(0);
      await session.pageBytes(1);
      expect(requested, ['/0.png', '/1.png', '/2.png', '/1.png']);
      session.close();
    },
  );

  test(
    'closing a reader releases its cache and rejects new requests',
    () async {
      final session = ReaderImageSession(
        urls: ['https://pages.example/0.png'],
        client: MockClient((_) async => http.Response.bytes(_png, 200)),
      );
      await session.pageBytes(0);
      session.close();
      await expectLater(session.pageBytes(0), throwsStateError);
    },
  );
}
