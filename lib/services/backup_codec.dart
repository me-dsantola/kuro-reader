import 'dart:convert';

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
      'externalArchiveId',
    ]) {
      _optional(value, key, (v) => v is String);
    }
    if (value['id'] is! String || (value['id'] as String).isEmpty) {
      _invalid('id do capítulo');
    }
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

  static String encode(Map<String, dynamic> data) =>
      base64Encode(utf8.encode(jsonEncode(data)));
}
