import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum CommentTargetType {
  manga('manga'),
  chapter('chapter');

  final String wireValue;
  const CommentTargetType(this.wireValue);

  static CommentTargetType fromWire(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase();
    return normalized == 'chapter'
        ? CommentTargetType.chapter
        : CommentTargetType.manga;
  }
}

final RegExp _legacyMangaPrefixRe = RegExp(
  r'^(cmk_mdx_|hq_mdx_|ani_mdx_|mal_mdx_|cmk_title_)+',
  caseSensitive: false,
);
final RegExp _legacyChapterPrefixRe = RegExp(
  r'^(cmk_mdx_|hq_mdx_|ani_mdx_|mal_mdx_)+',
  caseSensitive: false,
);

/// Normaliza o identificador de alvo (`manga` ou `chapter`) seguindo
/// exatamente a mesma regra do portal Web (`yomi-web`), garantindo que
/// comentários feitos no site e no app apareçam juntos no Firestore.
String normalizeCommentTargetId(
  String targetId, {
  CommentTargetType targetType = CommentTargetType.manga,
}) {
  final trimmed = targetId.trim();
  if (trimmed.isEmpty) return '';
  if (targetType == CommentTargetType.manga) {
    return trimmed.replaceFirst(_legacyMangaPrefixRe, '');
  }
  return trimmed.replaceFirst(_legacyChapterPrefixRe, '');
}

/// Converte timestamps em epoch ms, `Timestamp` do Firestore, mapas `{seconds}`
/// ou strings ISO-8601 para epoch milissegundos.
int parseCommentCreatedAtMs(Object? raw, {int? fallbackMs}) {
  final fallback = fallbackMs ?? DateTime.now().millisecondsSinceEpoch;
  if (raw is int) {
    if (raw > 0 && raw < 100000000000) return raw * 1000;
    return raw;
  }
  if (raw is num && raw.isFinite) {
    if (raw > 0 && raw < 100000000000) return (raw * 1000).round();
    return raw.round();
  }
  if (raw is DateTime) {
    return raw.millisecondsSinceEpoch;
  }
  if (raw is Timestamp) {
    return raw.millisecondsSinceEpoch;
  }
  if (raw is Map) {
    final secs = raw['seconds'] ?? raw['_seconds'];
    if (secs is num && secs.isFinite) {
      final nsRaw = raw['nanoseconds'] ?? raw['_nanoseconds'];
      final ns = nsRaw is num && nsRaw.isFinite ? nsRaw : 0;
      return (secs * 1000 + ns / 1000000).round();
    }
  }
  if (raw is String && raw.trim().isNotEmpty) {
    final asNum = num.tryParse(raw.trim());
    if (asNum != null && asNum.isFinite) {
      return parseCommentCreatedAtMs(asNum, fallbackMs: fallback);
    }
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed != null) return parsed.millisecondsSinceEpoch;
  }
  return fallback;
}

/// Converte cor hexadecimal `#RRGGBB` (`mascotColorId` do portal web)
/// em matiz HSV (`hue` 0..360) compatível com o `Blobatar` do Flutter.
double? hueFromHexColor(String? hex) {
  if (hex == null) return null;
  var clean = hex.trim();
  if (clean.startsWith('#')) clean = clean.substring(1);
  if (clean.length == 8) {
    clean = clean.substring(2);
  }
  if (clean.length != 6) return null;
  final rgb = int.tryParse(clean, radix: 16);
  if (rgb == null) return null;
  final color = Color(0xFF000000 | rgb);
  final hsv = HSVColor.fromColor(color);
  if (hsv.saturation < 0.05) return null;
  return hsv.hue;
}

/// Serializa um matiz HSV ou `Color` inteiro ARGB para `#RRGGBB` compartilhado
/// com o portal web (`mascotColorId`).
String? hexColorFromProfile({double? hue, int? customAccentColor}) {
  if (hue != null && hue.isFinite && hue >= 0) {
    final normalizedHue = ((hue % 360.0) + 360.0) % 360.0;
    final c = HSVColor.fromAHSV(1.0, normalizedHue, 0.84, 0.94).toColor();
    final r = (c.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }
  if (customAccentColor != null) {
    final hex = (customAccentColor & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    return '#$hex';
  }
  return null;
}

List<String> _normalizeLikedBy(Object? raw) {
  if (raw is! List) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    final uid = item?.toString().trim() ?? '';
    if (uid.isNotEmpty && seen.add(uid)) {
      out.add(uid);
    }
  }
  return List<String>.unmodifiable(out);
}

@immutable
class YomiComment {
  final String id;
  final String targetId;
  final CommentTargetType targetType;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String? mascotColorId;
  final String? mascotExpressionId;
  final String? mascotShapeId;
  final String text;
  final bool isSpoiler;
  final int likes;
  final List<String> likedBy;
  final int createdAt;

  const YomiComment({
    required this.id,
    required this.targetId,
    required this.targetType,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    this.mascotColorId,
    this.mascotExpressionId,
    this.mascotShapeId,
    required this.text,
    this.isSpoiler = false,
    this.likes = 0,
    this.likedBy = const [],
    required this.createdAt,
  });

  bool isLikedBy(String? uid) {
    if (uid == null || uid.trim().isEmpty) return false;
    return likedBy.contains(uid.trim());
  }

  YomiComment copyWith({
    String? id,
    String? targetId,
    CommentTargetType? targetType,
    String? userId,
    String? userName,
    String? userPhotoUrl,
    String? mascotColorId,
    String? mascotExpressionId,
    String? mascotShapeId,
    String? text,
    bool? isSpoiler,
    int? likes,
    List<String>? likedBy,
    int? createdAt,
  }) {
    return YomiComment(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      targetType: targetType ?? this.targetType,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      mascotColorId: mascotColorId ?? this.mascotColorId,
      mascotExpressionId: mascotExpressionId ?? this.mascotExpressionId,
      mascotShapeId: mascotShapeId ?? this.mascotShapeId,
      text: text ?? this.text,
      isSpoiler: isSpoiler ?? this.isSpoiler,
      likes: likes ?? this.likes,
      likedBy: likedBy ?? this.likedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory YomiComment.fromFirestoreMap(
    String id,
    Map<String, dynamic> data, {
    String fallbackTargetId = '',
  }) {
    final targetType = CommentTargetType.fromWire(data['targetType']);
    final likedBy = _normalizeLikedBy(data['likedBy']);
    final rawLikes = data['likes'];
    final parsedLikes = rawLikes is num && rawLikes.isFinite
        ? rawLikes.floor()
        : likedBy.length;
    final likes = math.max(likedBy.length, math.max(0, parsedLikes));

    String? cleanOptionalString(Object? value) {
      final str = value?.toString().trim() ?? '';
      return str.isEmpty ? null : str;
    }

    final rawUserId =
        cleanOptionalString(data['userId']) ??
        cleanOptionalString(data['uid']) ??
        '';
    final rawUserName = cleanOptionalString(data['userName']) ?? 'Leitor';
    final rawTarget =
        cleanOptionalString(data['targetId']) ?? fallbackTargetId;

    return YomiComment(
      id: id,
      targetId: normalizeCommentTargetId(rawTarget, targetType: targetType),
      targetType: targetType,
      userId: rawUserId,
      userName: rawUserName,
      userPhotoUrl: cleanOptionalString(data['userPhotoUrl']),
      mascotColorId: cleanOptionalString(data['mascotColorId']),
      mascotExpressionId: cleanOptionalString(data['mascotExpressionId']),
      mascotShapeId: cleanOptionalString(data['mascotShapeId']),
      text: (data['text'] ?? '').toString(),
      isSpoiler: data['isSpoiler'] == true,
      likes: likes,
      likedBy: likedBy,
      createdAt: parseCommentCreatedAtMs(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final map = <String, dynamic>{
      'targetId': normalizeCommentTargetId(targetId, targetType: targetType),
      'targetType': targetType.wireValue,
      'userId': userId.trim(),
      'userName': userName.trim().isEmpty ? 'Leitor YOMI' : userName.trim(),
      'text': text.trim(),
      'isSpoiler': isSpoiler,
      'likes': likedBy.length,
      'likedBy': likedBy,
      'createdAt': createdAt,
    };
    if (userPhotoUrl != null && userPhotoUrl!.trim().isNotEmpty) {
      map['userPhotoUrl'] = userPhotoUrl!.trim();
    }
    if (mascotColorId != null && mascotColorId!.trim().isNotEmpty) {
      map['mascotColorId'] = mascotColorId!.trim();
    }
    if (mascotExpressionId != null && mascotExpressionId!.trim().isNotEmpty) {
      map['mascotExpressionId'] = mascotExpressionId!.trim();
    }
    if (mascotShapeId != null && mascotShapeId!.trim().isNotEmpty) {
      map['mascotShapeId'] = mascotShapeId!.trim();
    }
    return map;
  }
}

@immutable
class CommentsPageResult {
  final List<YomiComment> comments;
  final int? nextCursor;
  final bool hasMore;
  final int totalCount;

  const CommentsPageResult({
    required this.comments,
    this.nextCursor,
    this.hasMore = false,
    this.totalCount = 0,
  });
}
