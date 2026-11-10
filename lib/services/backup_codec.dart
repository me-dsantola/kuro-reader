import 'dart:convert';

/// Validates local YOMI exports before a single value is written to Hive.
/// This is a transport format (Base64 JSON), NOT encryption.
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
      jsonText = raw.startsWith('{')
          ? raw
          : utf8.decode(base64Decode(raw));
    } on FormatException {
      throw const FormatException('Formato do backup inválido');
    }

    final parsed = jsonDecode(jsonText);
    if (parsed is! Map) throw const FormatException('Backup deve ser um objeto');
    final data = Map<String, dynamic>.from(parsed);

    final version = data['version'];
    if (version != null &&
        (version is! int || version < 1 || version > currentVersion)) {
      throw const FormatException('Versão de backup incompatível');
    }
    if (data['favorites'] is! Map && data['history'] is! Map &&
        data['profile'] is! Map) {
      throw const FormatException('Backup sem dados reconhecíveis');
    }

    for (final name in ['favorites', 'history', 'settings', 'profile']) {
      final value = data[name];
      if (value != null && value is! Map) {
        throw FormatException('Campo $name inválido');
      }
      if (value is Map && value.length > 250000) {
        throw FormatException('Campo $name excede limite de entradas');
      }
    }

    final favorites = data['favorites'];
    if (favorites is Map) {
      for (final entry in favorites.entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('Favorito inválido no backup');
        }
        final manga = entry.value as Map;
        if (manga['id'] is! String || manga['title'] is! String) {
          throw const FormatException('Dados de favorito incompletos');
        }
      }
    }
    final history = data['history'];
    if (history is Map && history.keys.any((k) => k is! String)) {
      throw const FormatException('Chave inválida no histórico');
    }
    return data;
  }

  static String encode(Map<String, dynamic> data) =>
      base64Encode(utf8.encode(jsonEncode(data)));
}
