import 'dart:convert';
import 'dart:math' as math;

/// Validates local exports before any Hive writes. Base64 is not encryption.
class BackupCodec {
  static const int currentVersion = 4;
  static const int maxInputLength = 24 * 1024 * 1024;

  static Map<String, dynamic> decode(String input) {
    final raw = input.trim();
    if (raw.isEmpty || raw.length > maxInputLength) {
      throw const FormatException('Backup vazio ou grande demais');
    }
    final String jsonText;
    try {
      jsonText = raw.startsWith('{') ? raw : utf8.decode(base64Decode(raw));
    } on FormatException {
      throw const FormatException('Formato do backup inválido');
    }
    final data = _map(jsonDecode(jsonText), 'backup');
    _validateTree(data);
    final version = data['version'];
    if (version != null &&
        (version is! int || version < 1 || version > currentVersion)) {
      throw const FormatException('Versão de backup incompatível');
    }
    if (data['favorites'] is! Map &&
        data['history'] is! Map &&
        data['profile'] is! Map) {
      throw const FormatException('Backup sem dados reconhecíveis');
    }
    for (final name in ['favorites', 'history', 'settings', 'profile']) {
      if (data[name] != null) _map(data[name], name);
    }
    final favorites = data['favorites'];
    if (favorites is Map) {
      for (final entry in favorites.entries) {
        if ((entry.key as String).isEmpty) _invalid('favoritos');
        _manga(entry.value, 'favorito');
      }
    }
    final history = data['history'];
    if (history is Map) {
      for (final entry in history.entries) {
        _history(entry.key as String, entry.value);
      }
    }
    final profile = data['profile'];
    if (profile is Map) {
      for (final key in [
        'name',
        'bio',
        'favoriteGenre',
        'avatarImagePath',
        'bannerImagePath',
        'avatarBase64',
        'bannerBase64',
        'blobatarName',
        'blobatarSeed',
        'blobatarShape',
        'blobatarExpression',
        'blobatarBackground',
      ]) {
        _optional(profile, key, (v) => v is String);
      }
      _optional(profile, 'avatarIndex', _nonNegativeInt);
      _optional(profile, 'customAccentColor', (v) => v is int);
      _optional(profile, 'blobatarHue', (v) => v is num && v.isFinite);
      for (final key in [
        'openOnProfileByDefault',
        'isConfigured',
        'useBlobatarAsAvatar',
        'blobatarAnimated',
        'blobatarInteractive',
      ]) {
        _optional(profile, key, (v) => v is bool);
      }
    }
    final settings = data['settings'];
    if (settings is Map) {
      for (final key in [
        'lock_nsfw_on_startup',
        'hide_zero_chapters',
        'data_saver_mode',
        'auto_hide_menus',
        'tab_transitions',
        'reactive_reader',
        'privacy_protection_enabled',
      ]) {
        _optional(settings, key, (v) => v is bool);
      }
      if (settings['user_reading_lists'] != null) {
        final rawLists = settings['user_reading_lists'];
        if (rawLists is! List) _invalid('user_reading_lists');
        for (final rawItem in rawLists) {
          final item = _map(rawItem, 'user_reading_lists');
          if (item['id'] is! String ||
              (item['id'] as String).isEmpty ||
              item['name'] is! String) {
            _invalid('user_reading_lists');
          }
          _optional(item, 'description', (v) => v is String);
          _optional(item, 'createdAt', (v) => v is String);
          final mangas = item['mangas'];
          if (mangas != null) {
            if (mangas is! List) _invalid('mangas');
            for (final m in mangas) {
              _manga(m, 'user_reading_lists.mangas');
            }
          }
        }
      }
    }
    if (settings is Map) {
      _optional(
        settings,
        'interface_style',
        (v) => v == 'enso' || v == 'glass',
      );
    }
    return data;
  }

  static Never _invalid(String field) =>
      throw FormatException('Campo inválido no backup: $field');

  static Map<String, dynamic> _map(Object? value, String field) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      _invalid(field);
    }
    return Map<String, dynamic>.from(value);
  }

  static void _validateTree(Object? value, [int depth = 0]) {
    if (depth > 32) _invalid('profundidade');
    if (value is Map) {
      if (value.length > 250000) _invalid('quantidade de entradas');
      for (final entry in value.entries) {
        if (entry.key is! String) _invalid('chave');
        _validateTree(entry.value, depth + 1);
      }
    } else if (value is List) {
      if (value.length > 250000) _invalid('quantidade de itens');
      for (final item in value) {
        _validateTree(item, depth + 1);
      }
    } else if (value is num && !value.isFinite) {
      _invalid('número');
    }
  }

  static bool _nonNegativeInt(Object? value) => value is int && value >= 0;
  static bool _strings(Object? value) =>
      value is List && value.every((item) => item is String);

  static void _optional(Map value, String key, bool Function(Object?) accepts) {
    if (value[key] != null && !accepts(value[key])) _invalid(key);
  }

  static void _manga(Object? raw, String field) {
    final value = _map(raw, field);
    if (value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        value['title'] is! String) {
      _invalid(field);
    }
    for (final key in [
      'description',
      'status',
      'coverFileName',
      'directCoverUrl',
      'directHighResCoverUrl',
      'source',
      'updatedAt',
    ]) {
      _optional(value, key, (v) => v is String);
    }
    _optional(value, 'tags', _strings);
    _optional(value, 'isNsfw', (v) => v is bool);
    _optional(value, 'contentRatingKnown', (v) => v is bool);
    _optional(value, 'availableChaptersCount', (v) => v is int && v >= -1);
    final headers = value['customHeaders'];
    if (headers != null &&
        _map(headers, 'customHeaders').values.any((v) => v is! String)) {
      _invalid('customHeaders');
    }
    final chapters = value['preloadedChapters'];
    if (chapters != null) _chapters(chapters);
  }

  static void _chapter(Object? raw) {
    final value = _map(raw, 'capítulo');
    for (final key in [
      'id',
      'source',
      'chapterNumber',
      'title',
      'language',
      'scanlator',
      'volume',
      'externalArchiveId',
    ]) {
      _optional(value, key, (v) => v is String);
    }
    if (value['id'] is! String || (value['id'] as String).isEmpty) {
      _invalid('id do capítulo');
    }
    _optional(value, 'isSpecial', (v) => v is bool);
    _optional(value, 'pages', _nonNegativeInt);
    _optional(value, 'directPageUrls', _strings);
  }

  static void _chapters(Object? value) {
    if (value is! List) _invalid('lista de capítulos');
    for (final chapter in value) {
      _chapter(chapter);
    }
  }

  static void _history(String key, Object? value) {
    if (key.isEmpty) _invalid('chave do histórico');
    if (key.startsWith('page_') || key.startsWith('chapters_count_')) {
      if (!_nonNegativeInt(value)) _invalid(key);
    } else if (key.startsWith('webtoon_anchor_')) {
      final anchor = _map(value, key);
      if (!_nonNegativeInt(anchor['page']) ||
          anchor['fraction'] is! num ||
          !(anchor['fraction'] as num).isFinite ||
          anchor['fraction'] < 0 ||
          anchor['fraction'] > 1) {
        _invalid(key);
      }
    } else if (key.startsWith('webtoon_offset_')) {
      if (value is! num || !value.isFinite || value < 0) _invalid(key);
    } else if (key.startsWith('reading_metric_')) {
      final event = _map(value, key);
      if (event['changedAt'] is! String) _invalid(key);
      _optional(event, 'readAt', (v) => v is String);
      _optional(event, 'mangaId', (v) => v is String);
      _optional(event, 'number', (v) => v is String);
      _optional(event, 'pages', _nonNegativeInt);
    } else if (key.startsWith('read_')) {
      if (value is! bool) _invalid(key);
    } else if (key.startsWith('last_')) {
      _chapter(value);
    } else if (key.startsWith('manga_meta_')) {
      _manga(value, key);
    } else if (key.startsWith('chapters_')) {
      _chapters(value);
    } else if (key == 'recent_reading_list' || key == 'reading_events_log') {
      if (value is! List) _invalid(key);
      for (final raw in value) {
        final item = _map(raw, key);
        if (key == 'recent_reading_list') {
          _manga(item['manga'], key);
          _chapter(item['chapter']);
          _optional(item, 'timestamp', (v) => v is String);
        } else {
          _manga(item['mangaMap'], key);
          _chapter(item['chapterMap']);
          _optional(item, 'pages', _nonNegativeInt);
          for (final field in [
            'chapterId',
            'mangaId',
            'mangaTitle',
            'readAt',
          ]) {
            _optional(item, field, (v) => v is String);
          }
        }
      }
    }
    // Preserve unknown legacy keys; their JSON structure was checked above.
  }

  /// Remove caches efêmeros de capítulos e limita históricos extensos antes de
  /// enviar para a nuvem, mantendo o payload compacto abaixo do limite do Firestore.
  static Map<String, dynamic> stripEphemeralCacheForCloud(
    Map<String, dynamic> data,
  ) {
    final result = Map<String, dynamic>.from(data);
    final rawHistory = data['history'];
    if (rawHistory is Map) {
      final cleanHistory = <String, dynamic>{};
      for (final entry in rawHistory.entries) {
        final key = entry.key.toString();
        if (key.startsWith('chapters_') && !key.startsWith('chapters_count_')) {
          continue;
        }
        if (key == 'recent_reading_list' && entry.value is List) {
          final list = List<dynamic>.from(entry.value as List);
          cleanHistory[key] = list.length > 30 ? list.sublist(0, 30) : list;
          continue;
        }
        if (key == 'reading_events_log' && entry.value is List) {
          final list = List<dynamic>.from(entry.value as List);
          cleanHistory[key] = list.length > 150
              ? list.sublist(list.length - 150)
              : list;
          continue;
        }
        cleanHistory[key] = entry.value;
      }
      result['history'] = cleanHistory;
    }
    return result;
  }

  /// Mescla o snapshot da nuvem com o snapshot local preservando favoritos,
  /// capas, progresso de páginas, capítulos lidos, coleções e perfil mais recente.
  static Map<String, dynamic> mergeCloudAndLocal(
    Map<String, dynamic> cloud,
    Map<String, dynamic> local, {
    required bool cloudIsNewer,
  }) {
    final older = cloudIsNewer ? local : cloud;
    final newer = cloudIsNewer ? cloud : local;
    final merged = <String, dynamic>{...older, ...newer};
    merged['version'] = currentVersion;

    // 1. Favoritos
    final olderFavs = _asStringMap(older['favorites']);
    final newerFavs = _asStringMap(newer['favorites']);
    final mergedFavs = <String, dynamic>{};
    for (final key in {...olderFavs.keys, ...newerFavs.keys}) {
      final oVal = olderFavs[key];
      final nVal = newerFavs[key];
      if (oVal is Map && nVal is Map) {
        mergedFavs[key] = _mergeMangaEntry(
          _asStringMap(oVal),
          _asStringMap(nVal),
        );
      } else {
        mergedFavs[key] = nVal ?? oVal;
      }
    }
    merged['favorites'] = mergedFavs;

    // 2. Histórico & Progresso de Leitura
    final cloudHist = _asStringMap(cloud['history']);
    final localHist = _asStringMap(local['history']);
    final olderHist = cloudIsNewer ? localHist : cloudHist;
    final newerHist = cloudIsNewer ? cloudHist : localHist;
    final mergedHist = <String, dynamic>{};

    for (final key in {...olderHist.keys, ...newerHist.keys}) {
      if (key.startsWith('reading_metric_')) {
        final cloudEvent = _asStringMap(cloudHist[key]);
        final localEvent = _asStringMap(localHist[key]);
        final cloudAt = DateTime.tryParse(
          cloudEvent['changedAt']?.toString() ?? '',
        );
        final localAt = DateTime.tryParse(
          localEvent['changedAt']?.toString() ?? '',
        );
        mergedHist[key] =
            localAt != null && (cloudAt == null || !localAt.isBefore(cloudAt))
            ? localEvent
            : cloudEvent;
      } else if (key.startsWith('read_')) {
        mergedHist[key] = (cloudHist[key] == true) || (localHist[key] == true);
      } else if (key.startsWith('page_')) {
        final cPage = cloudHist[key] is int ? cloudHist[key] as int : -1;
        final lPage = localHist[key] is int ? localHist[key] as int : -1;
        final maxPage = math.max(cPage, lPage);
        if (maxPage >= 0) mergedHist[key] = maxPage;
      } else if (key == 'recent_reading_list') {
        mergedHist[key] = _mergeRecentReadingLists(
          olderHist[key],
          newerHist[key],
        );
      } else if (key == 'reading_events_log') {
        mergedHist[key] = _mergeReadingEvents(olderHist[key], newerHist[key]);
      } else if (key.startsWith('manga_meta_')) {
        final oMeta = olderHist[key];
        final nMeta = newerHist[key];
        if (oMeta is Map && nMeta is Map) {
          mergedHist[key] = _mergeMangaEntry(
            _asStringMap(oMeta),
            _asStringMap(nMeta),
          );
        } else {
          mergedHist[key] = nMeta ?? oMeta;
        }
      } else {
        mergedHist[key] = newerHist.containsKey(key)
            ? newerHist[key]
            : olderHist[key];
      }
    }
    for (final key in mergedHist.keys.toList()) {
      if (!key.startsWith('reading_metric_')) continue;
      final event = _asStringMap(mergedHist[key]);
      if (event['changedAt'] is String) {
        mergedHist['read_${key.substring('reading_metric_'.length)}'] =
            event['readAt'] is String;
      }
    }
    merged['history'] = mergedHist;

    // 3. Configurações & Coleções Personalizadas
    final olderSettings = _asStringMap(older['settings']);
    final newerSettings = _asStringMap(newer['settings']);
    final mergedSettings = <String, dynamic>{
      ...olderSettings,
      ...newerSettings,
    };
    if (olderSettings.containsKey('user_reading_lists') ||
        newerSettings.containsKey('user_reading_lists')) {
      mergedSettings['user_reading_lists'] = _mergeReadingLists(
        olderSettings['user_reading_lists'],
        newerSettings['user_reading_lists'],
      );
    }
    merged['settings'] = mergedSettings;

    // 4. Perfil & Blobatar
    final olderProfile = _asStringMap(older['profile']);
    final newerProfile = _asStringMap(newer['profile']);
    if (olderProfile.isNotEmpty || newerProfile.isNotEmpty) {
      final mergedProfile = <String, dynamic>{...olderProfile};
      for (final entry in newerProfile.entries) {
        if (entry.value != null) {
          mergedProfile[entry.key] = entry.value;
        }
      }
      if (olderProfile['isConfigured'] == true ||
          newerProfile['isConfigured'] == true) {
        mergedProfile['isConfigured'] = true;
      }
      merged['profile'] = mergedProfile;
    }

    return merged;
  }

  static Map<String, dynamic> _asStringMap(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    final out = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.key != null) {
        out[entry.key.toString()] = entry.value;
      }
    }
    return out;
  }

  static Map<String, dynamic> _mergeMangaEntry(
    Map<String, dynamic> older,
    Map<String, dynamic> newer,
  ) {
    final result = <String, dynamic>{...older, ...newer};
    for (final field in const [
      'coverFileName',
      'directCoverUrl',
      'directHighResCoverUrl',
    ]) {
      final newerVal = result[field]?.toString().trim() ?? '';
      final olderVal = older[field]?.toString().trim() ?? '';
      if (newerVal.isEmpty && olderVal.isNotEmpty) {
        result[field] = older[field];
      }
    }
    final newerTags = result['tags'];
    final olderTags = older['tags'];
    if ((newerTags is! List || newerTags.isEmpty) &&
        olderTags is List &&
        olderTags.isNotEmpty) {
      result['tags'] = olderTags;
    }
    return result;
  }

  static List<Map<String, dynamic>> _mergeRecentReadingLists(
    Object? olderRaw,
    Object? newerRaw,
  ) {
    final olderList = olderRaw is List ? olderRaw : const [];
    final newerList = newerRaw is List ? newerRaw : const [];
    final byMangaId = <String, Map<String, dynamic>>{};

    void ingest(Object? item, bool isNewerSide) {
      if (item is! Map) return;
      final map = _asStringMap(item);
      final manga = _asStringMap(map['manga']);
      final mangaId = manga['id']?.toString().trim() ?? '';
      if (mangaId.isEmpty) return;

      final existing = byMangaId[mangaId];
      if (existing == null) {
        byMangaId[mangaId] = {
          ...map,
          'manga': manga,
        };
        return;
      }

      final existingTs =
          DateTime.tryParse(existing['timestamp']?.toString() ?? '');
      final candidateTs =
          DateTime.tryParse(map['timestamp']?.toString() ?? '');
      final pickCandidate = switch ((existingTs, candidateTs)) {
        (final e?, final c?) => c.isAfter(e) || (c == e && isNewerSide),
        (null, _?) => true,
        (_?, null) => false,
        (null, null) => isNewerSide,
      };

      final existingManga = _asStringMap(existing['manga']);
      if (pickCandidate) {
        byMangaId[mangaId] = {
          ...map,
          'manga': _mergeMangaEntry(existingManga, manga),
        };
      } else {
        byMangaId[mangaId] = {
          ...existing,
          'manga': _mergeMangaEntry(manga, existingManga),
        };
      }
    }

    for (final item in olderList) {
      ingest(item, false);
    }
    for (final item in newerList) {
      ingest(item, true);
    }

    final sorted = byMangaId.values.toList()
      ..sort((a, b) {
        final aTs = DateTime.tryParse(a['timestamp']?.toString() ?? '');
        final bTs = DateTime.tryParse(b['timestamp']?.toString() ?? '');
        if (aTs != null && bTs != null) return bTs.compareTo(aTs);
        if (bTs != null) return 1;
        if (aTs != null) return -1;
        return 0;
      });
    return sorted.length > 30 ? sorted.sublist(0, 30) : sorted;
  }

  static List<Map<String, dynamic>> _mergeReadingEvents(
    Object? olderRaw,
    Object? newerRaw,
  ) {
    final olderList = olderRaw is List ? olderRaw : const [];
    final newerList = newerRaw is List ? newerRaw : const [];
    final merged = <Map<String, dynamic>>[];
    final seenChapterIds = <String>{};

    for (final raw in [...olderList, ...newerList]) {
      if (raw is! Map) continue;
      final item = _asStringMap(raw);
      final chapterId = item['chapterId']?.toString().trim() ?? '';
      if (chapterId.isNotEmpty && !seenChapterIds.add(chapterId)) {
        continue;
      }
      merged.add(item);
    }
    return merged.length > 150
        ? merged.sublist(merged.length - 150)
        : merged;
  }

  static List<Map<String, dynamic>> _mergeReadingLists(
    Object? olderRaw,
    Object? newerRaw,
  ) {
    final olderList = olderRaw is List ? olderRaw : const [];
    final newerList = newerRaw is List ? newerRaw : const [];
    final byId = <String, Map<String, dynamic>>{};

    void absorbList(Object? raw, bool preferMeta) {
      if (raw is! Map) return;
      final listMap = _asStringMap(raw);
      final id = listMap['id']?.toString().trim() ?? '';
      if (id.isEmpty) return;

      final existing = byId[id];
      final incomingMangas = listMap['mangas'] is List
          ? (listMap['mangas'] as List).whereType<Map>().map(_asStringMap).toList()
          : <Map<String, dynamic>>[];

      if (existing == null) {
        byId[id] = {
          ...listMap,
          'mangas': incomingMangas,
        };
        return;
      }

      final existingMangas = existing['mangas'] is List
          ? (existing['mangas'] as List).whereType<Map>().map(_asStringMap).toList()
          : <Map<String, dynamic>>[];

      final combinedByMangaId = <String, Map<String, dynamic>>{};
      for (final m in existingMangas) {
        final mid = m['id']?.toString() ?? '';
        if (mid.isNotEmpty) combinedByMangaId[mid] = m;
      }
      for (final m in incomingMangas) {
        final mid = m['id']?.toString() ?? '';
        if (mid.isEmpty) continue;
        final prev = combinedByMangaId[mid];
        combinedByMangaId[mid] = prev == null
            ? m
            : preferMeta
                ? _mergeMangaEntry(prev, m)
                : _mergeMangaEntry(m, prev);
      }

      byId[id] = {
        ...(preferMeta ? {...existing, ...listMap} : {...listMap, ...existing}),
        'mangas': combinedByMangaId.values.toList(),
      };
    }

    for (final raw in newerList) {
      absorbList(raw, true);
    }
    for (final raw in olderList) {
      absorbList(raw, false);
    }

    return byId.values.toList();
  }

  static String encode(Map<String, dynamic> data) =>
      base64Encode(utf8.encode(jsonEncode(data)));
}
