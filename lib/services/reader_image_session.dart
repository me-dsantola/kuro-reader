import 'device_state_service.dart';
import 'dart:collection';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/manga_models.dart';

/// Chapter-scoped compressed image cache shared by both reading modes.
/// Decoded bitmaps remain managed by Flutter's separately bounded image cache.
class ReaderImageSession {
  final List<String> localPaths;
  List<String> _urls;
  final Map<String, String> headers;
  final Future<List<String>> Function()? reloadUrls;
  final int maxCacheBytes;
  final http.Client _client;
  final Map<int, Uint8List> _cache = <int, Uint8List>{};
  final _pending = <int, Future<Uint8List>>{};
  final _waiting = Queue<Future<void> Function()>();
  int _active = 0;
  int _cacheBytes = 0;
  bool _closed = false;
  Future<void>? _refreshing;

  ReaderImageSession({
    this.localPaths = const [],
    List<String> urls = const [],
    this.headers = const {},
    this.reloadUrls,
    this.maxCacheBytes = 24 * 1024 * 1024,
    http.Client? client,
  }) : _urls = List.of(urls),
       _client = client ?? http.Client();

  int get pageCount => localPaths.isNotEmpty ? localPaths.length : _urls.length;

  Future<Uint8List> pageBytes(int index) {
    if (_closed) return Future.error(StateError('Leitor encerrado'));
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return Future.value(cached);
    }
    final pending = _pending[index];
    if (pending != null) return pending;
    late final Future<Uint8List> task;
    task = () async {
      try {
        final bytes = await _limited(() => _read(index));
        if (!_closed && localPaths.isEmpty && bytes.length <= maxCacheBytes) {
          while (_cache.isNotEmpty &&
              _cacheBytes + bytes.length > maxCacheBytes) {
            _cacheBytes -= _cache.remove(_cache.keys.first)!.length;
          }
          _cache[index] = bytes;
          _cacheBytes += bytes.length;
        }
        return bytes;
      } finally {
        if (identical(_pending[index], task)) _pending.remove(index);
      }
    }();
    _pending[index] = task;
    return task;
  }

  Future<T> _limited<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    Future<void> run() async {
      try {
        if (_closed) throw StateError('Leitor encerrado');
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _active--;
        _drain();
      }
    }

    _waiting.add(run);
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_active < 3 && _waiting.isNotEmpty) {
      _active++;
      _waiting.removeFirst()();
    }
  }

  Future<Uint8List> _read(int index) async {
    RangeError.checkValidIndex(
      index,
      localPaths.isNotEmpty ? localPaths : _urls,
    );
    if (localPaths.isNotEmpty) return File(localPaths[index]).readAsBytes();
    for (final url in yomiCandidateImageUrls(_urls[index])) {
      if (_closed) throw StateError('Leitor encerrado');
      try {
        final response = await DeviceStateService.instance.observe(() => _client
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 12)));
        final bytes = response.bodyBytes;
        if (response.statusCode == 200 && _isImage(bytes)) return bytes;
        // A rate limit applies to this source, not to one decode attempt.
        if (response.statusCode == 429) break;
      } catch (_) {
        if (_closed) rethrow;
      }
    }
    throw const FormatException('Não foi possível obter a página');
  }

  static bool _isImage(Uint8List b) =>
      b.length >= 12 &&
      ((b[0] == 0xff && b[1] == 0xd8) ||
          (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) ||
          (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) ||
          (b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45));

  Future<void> retry(int index) async {
    final old = _cache.remove(index);
    if (old != null) _cacheBytes -= old.length;
    if (localPaths.isNotEmpty || reloadUrls == null || _closed) return;
    _refreshing ??= () async {
      final updated = await reloadUrls!();
      if (!_closed && updated.length == _urls.length) _urls = List.of(updated);
    }();
    try {
      await _refreshing;
    } catch (_) {
      // A retry can still use the existing URLs if metadata refresh is offline.
    } finally {
      _refreshing = null;
    }
  }

  void close() {
    _closed = true;
    _client.close();
    _cache.clear();
    _cacheBytes = 0;
    // Queued jobs are drained into explicit failures instead of hanging.
    _drain();
  }
}
