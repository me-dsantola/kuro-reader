import 'dart:collection';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/manga_models.dart';
import 'device_state_service.dart';

class _DiskPage {
  final File file;
  final int size;
  final int generation;
  const _DiskPage(this.file, this.size, this.generation);
}

class _RateLimitedPage extends FormatException {
  const _RateLimitedPage()
    : super('A fonte limitou as requisições. Tente novamente mais tarde.');
}

/// Chapter-scoped caches shared by both reading modes. The optional disk
/// directory must be private, temporary, and created exclusively for this session.
class ReaderImageSession {
  final List<String> localPaths;
  List<String> _urls;
  final Map<String, String> headers;
  final Future<List<String>> Function()? reloadUrls;
  final int maxCacheBytes;
  final int maxDiskCacheBytes;
  final Future<Directory> Function()? createCacheDirectory;
  final http.Client _client;
  final Map<int, Uint8List> _cache = {};
  final Map<int, _DiskPage> _diskCache = {};
  final Map<int, int> _generations = {};
  final _pending = <int, Future<Uint8List>>{};
  final _waiting = Queue<Future<void> Function()>();
  int _active = 0;
  int _cacheBytes = 0;
  int _diskBytes = 0;
  int _sourceRevision = 0;
  bool _closed = false;
  bool _diskDisabled = false;
  Future<void>? _refreshing;
  Future<Directory>? _diskDirectory;
  Future<void> _diskTail = Future<void>.value();

  ReaderImageSession({
    this.localPaths = const [],
    List<String> urls = const [],
    this.headers = const {},
    this.reloadUrls,
    this.maxCacheBytes = 24 * 1024 * 1024,
    this.maxDiskCacheBytes = 96 * 1024 * 1024,
    this.createCacheDirectory,
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
    final generation = _generations[index] ?? 0;
    late final Future<Uint8List> task;
    task = () async {
      try {
        final disk = await _loadFromDisk(index, generation);
        final Uint8List bytes =
            disk ?? await _limited<Uint8List>(() => _read(index));
        if (!_closed &&
            generation == (_generations[index] ?? 0) &&
            localPaths.isEmpty) {
          _remember(index, bytes);
          if (disk == null) await _storeOnDisk(index, generation, bytes);
        }
        return bytes;
      } finally {
        if (identical(_pending[index], task)) _pending.remove(index);
      }
    }();
    _pending[index] = task;
    return task;
  }

  void _remember(int index, Uint8List bytes) {
    if (bytes.length > maxCacheBytes) return;
    final previous = _cache.remove(index);
    if (previous != null) _cacheBytes -= previous.length;
    while (_cache.isNotEmpty && _cacheBytes + bytes.length > maxCacheBytes) {
      _cacheBytes -= _cache.remove(_cache.keys.first)!.length;
    }
    _cache[index] = bytes;
    _cacheBytes += bytes.length;
  }

  Future<T> _withDisk<T>(Future<T> Function() action) {
    final task = _diskTail.then((_) => action());
    _diskTail = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<Uint8List?> _loadFromDisk(int index, int generation) =>
      _withDisk(() async {
        final entry = _diskCache.remove(index);
        if (entry == null) return null;
        if (_closed || entry.generation != generation) {
          await _removeDiskFile(entry);
          return null;
        }
        try {
          final bytes = await entry.file.readAsBytes();
          if (bytes.length != entry.size || !_isImage(bytes)) {
            await _removeDiskFile(entry);
            return null;
          }
          _diskCache[index] = entry;
          return bytes;
        } catch (_) {
          await _removeDiskFile(entry);
          return null;
        }
      });

  Future<void> _removeDiskFile(_DiskPage entry) async {
    _diskBytes -= entry.size;
    try {
      if (await entry.file.exists()) await entry.file.delete();
    } catch (_) {
      // Stop writing if old files cannot be removed, keeping the physical
      // footprint bounded even when the cache directory becomes unavailable.
      _diskDisabled = true;
    }
  }

  Future<void> _storeOnDisk(
    int index,
    int generation,
    Uint8List bytes,
  ) => _withDisk(() async {
    final factory = createCacheDirectory;
    if (_closed ||
        _diskDisabled ||
        factory == null ||
        maxDiskCacheBytes <= 0 ||
        bytes.length > maxDiskCacheBytes) {
      return;
    }
    try {
      final directory = await (_diskDirectory ??= Future.sync(factory));
      if (_closed || generation != (_generations[index] ?? 0)) return;
      final previous = _diskCache.remove(index);
      if (previous != null) await _removeDiskFile(previous);
      while (!_diskDisabled &&
          _diskCache.isNotEmpty &&
          _diskBytes + bytes.length > maxDiskCacheBytes) {
        await _removeDiskFile(_diskCache.remove(_diskCache.keys.first)!);
      }
      if (_diskDisabled) return;
      final file = File('${directory.path}/$index-$generation.bin');
      await file.writeAsBytes(bytes);
      if (_closed || generation != (_generations[index] ?? 0)) {
        await file.delete();
        return;
      }
      _diskCache[index] = _DiskPage(file, bytes.length, generation);
      _diskBytes += bytes.length;
    } catch (_) {
      // Optional caching must never turn a successful page into a read error.
      _diskDisabled = true;
    }
  });

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
    final revision = _sourceRevision;
    final originalUrl = _urls[index];
    try {
      return await _readOnline(originalUrl);
    } on _RateLimitedPage {
      rethrow;
    } on FormatException {
      if (_closed || reloadUrls == null) rethrow;
      // Expired CDN addresses can affect several visible pages together.
      // Share their metadata refresh and retry only if the URL actually changed.
      if (revision == _sourceRevision) await _refreshUrls();
      if (!_closed && _urls[index] != originalUrl) {
        return _readOnline(_urls[index]);
      }
      rethrow;
    }
  }

  Future<Uint8List> _readOnline(String rawUrl) async {
    for (final url in yomiCandidateImageUrls(rawUrl)) {
      if (_closed) throw StateError('Leitor encerrado');
      try {
        final response = await DeviceStateService.instance.observe(
          () => _client
              .get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 12)),
        );
        if (response.statusCode == 429) throw const _RateLimitedPage();
        final bytes = response.bodyBytes;
        if (response.statusCode == 200 && _isImage(bytes)) return bytes;
      } on _RateLimitedPage {
        rethrow;
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

  /// Invalidates failed decodes as well as network failures. An older in-flight
  /// request may finish for its old consumer, but cannot repopulate this cache.
  Future<void> invalidate(int index) async {
    _generations[index] = (_generations[index] ?? 0) + 1;
    _pending.remove(index);
    final previous = _cache.remove(index);
    if (previous != null) _cacheBytes -= previous.length;
    await _withDisk(() async {
      final entry = _diskCache.remove(index);
      if (entry != null) await _removeDiskFile(entry);
    });
  }

  Future<void> _refreshUrls() async {
    if (reloadUrls == null || _closed) return;
    final task = _refreshing ??= () async {
      final updated = await reloadUrls!();
      if (!_closed && updated.length == _urls.length) {
        _urls = List.of(updated);
        _sourceRevision++;
      }
    }();
    try {
      await task;
    } catch (_) {
      // Existing URLs can still work if the metadata API is temporarily offline.
    } finally {
      if (identical(_refreshing, task)) _refreshing = null;
    }
  }

  Future<void> retry(int index) async {
    await invalidate(index);
    if (localPaths.isEmpty) await _refreshUrls();
  }

  void close() {
    _closed = true;
    _client.close();
    _cache.clear();
    _cacheBytes = 0;
    _drain();
    unawaited(
      _withDisk(() async {
        _diskCache.clear();
        _diskBytes = 0;
        final directory = _diskDirectory;
        if (directory != null) {
          try {
            await (await directory).delete(recursive: true);
          } catch (_) {
            // The OS may have already cleared this private temporary directory.
          }
        }
      }),
    );
  }
}
