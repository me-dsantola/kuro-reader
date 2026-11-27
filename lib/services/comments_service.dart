import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/comment_models.dart';
import 'cloud_auth_service.dart';
import 'profile_palette_service.dart';
import 'storage_service.dart';

class CommentAuthRequiredException implements Exception {
  final String message;
  const CommentAuthRequiredException([
    this.message = 'Entre na sua conta para comentar ou curtir.',
  ]);
  @override
  String toString() => message;
}

class CommentValidationException implements Exception {
  final String message;
  const CommentValidationException(this.message);
  @override
  String toString() => message;
}

class CommentPermissionDeniedException implements Exception {
  final String message;
  const CommentPermissionDeniedException([
    this.message = 'Você só pode excluir seus próprios comentários.',
  ]);
  @override
  String toString() => message;
}

class CommentNotFoundException implements Exception {
  final String message;
  const CommentNotFoundException([
    this.message = 'Este comentário não está mais disponível.',
  ]);
  @override
  String toString() => message;
}

@immutable
class CommentAuthorIdentity {
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String? mascotColorId;
  final String? mascotExpressionId;
  final String? mascotShapeId;

  const CommentAuthorIdentity({
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    this.mascotColorId,
    this.mascotExpressionId,
    this.mascotShapeId,
  });
}

abstract class CommentsStoreAdapter {
  Future<List<MapEntry<String, Map<String, dynamic>>>> fetchCommentsRaw({
    required List<String> targetIdCandidates,
    required CommentTargetType targetType,
  });

  Future<String> createComment(Map<String, dynamic> payload);

  Future<({bool liked, int likes, List<String> likedBy})> toggleLike({
    required String commentId,
    required String userId,
  });

  Future<void> deleteComment({
    required String commentId,
    required String userId,
  });
}

class FirestoreCommentsStoreAdapter implements CommentsStoreAdapter {
  final FirebaseFirestore? _firestore;

  const FirestoreCommentsStoreAdapter([this._firestore]);

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<MapEntry<String, Map<String, dynamic>>>> fetchCommentsRaw({
    required List<String> targetIdCandidates,
    required CommentTargetType targetType,
  }) async {
    if (targetIdCandidates.isEmpty) return const [];
    final col = _db.collection('comments');
    final Query<Map<String, dynamic>> query = targetIdCandidates.length > 1
        ? col.where('targetId', whereIn: targetIdCandidates.take(10).toList())
        : col.where('targetId', isEqualTo: targetIdCandidates.first);

    final snap = await query.limit(300).get();
    final out = <MapEntry<String, Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final rawType = data['targetType'];
      if (rawType == null ||
          CommentTargetType.fromWire(rawType) == targetType) {
        out.add(MapEntry(doc.id, data));
      }
    }
    return out;
  }

  @override
  Future<String> createComment(Map<String, dynamic> payload) async {
    final docRef = await _db.collection('comments').add(payload);
    return docRef.id;
  }

  @override
  Future<({bool liked, int likes, List<String> likedBy})> toggleLike({
    required String commentId,
    required String userId,
  }) async {
    final ref = _db.collection('comments').doc(commentId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) {
        throw const CommentNotFoundException();
      }
      final data = snap.data()!;
      final rawLikedBy = data['likedBy'];
      final currentLikedBy = <String>[];
      final seen = <String>{};
      if (rawLikedBy is List) {
        for (final item in rawLikedBy) {
          final uid = item?.toString().trim() ?? '';
          if (uid.isNotEmpty && seen.add(uid)) {
            currentLikedBy.add(uid);
          }
        }
      }

      final alreadyLiked = currentLikedBy.contains(userId);
      final nextLikedBy = alreadyLiked
          ? currentLikedBy.where((uid) => uid != userId).toList()
          : [...currentLikedBy, userId];

      tx.update(ref, {
        'likedBy': nextLikedBy,
        'likes': nextLikedBy.length,
      });

      return (
        liked: !alreadyLiked,
        likes: nextLikedBy.length,
        likedBy: List<String>.unmodifiable(nextLikedBy),
      );
    });
  }

  @override
  Future<void> deleteComment({
    required String commentId,
    required String userId,
  }) async {
    final ref = _db.collection('comments').doc(commentId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) {
      throw const CommentNotFoundException();
    }
    final data = snap.data()!;
    final authorId = (data['userId'] ?? data['uid'] ?? '').toString().trim();
    if (authorId != userId) {
      throw const CommentPermissionDeniedException();
    }
    await ref.delete();
  }
}

/// Implementação em memória para testes unitários/widget seguindo
/// exatamente a mesma semântica do Firestore.
class InMemoryCommentsStoreAdapter implements CommentsStoreAdapter {
  final Map<String, Map<String, dynamic>> _docs = {};
  int _seq = 0;

  bool simulateNetworkError = false;

  void seedRawDoc(String id, Map<String, dynamic> data) {
    _docs[id] = Map<String, dynamic>.from(data);
  }

  Map<String, dynamic>? getRawDoc(String id) =>
      _docs[id] == null ? null : Map<String, dynamic>.from(_docs[id]!);

  @override
  Future<List<MapEntry<String, Map<String, dynamic>>>> fetchCommentsRaw({
    required List<String> targetIdCandidates,
    required CommentTargetType targetType,
  }) async {
    if (simulateNetworkError) {
      throw Exception('Falha de rede simulada ao buscar comentários');
    }
    final candidateSet = targetIdCandidates.toSet();
    final matches = <MapEntry<String, Map<String, dynamic>>>[];
    for (final entry in _docs.entries) {
      final data = entry.value;
      final tId = (data['targetId'] ?? '').toString().trim();
      final rawType = data['targetType'];
      final typeMatch =
          rawType == null || CommentTargetType.fromWire(rawType) == targetType;
      if (candidateSet.contains(tId) && typeMatch) {
        matches.add(MapEntry(entry.key, Map<String, dynamic>.from(data)));
      }
    }
    return matches;
  }

  @override
  Future<String> createComment(Map<String, dynamic> payload) async {
    if (simulateNetworkError) {
      throw Exception('Falha de rede simulada ao publicar comentário');
    }
    _seq++;
    final id = 'cmt_$_seq';
    _docs[id] = Map<String, dynamic>.from(payload);
    return id;
  }

  @override
  Future<({bool liked, int likes, List<String> likedBy})> toggleLike({
    required String commentId,
    required String userId,
  }) async {
    if (simulateNetworkError) {
      throw Exception('Falha de rede simulada ao curtir comentário');
    }
    final existing = _docs[commentId];
    if (existing == null) throw const CommentNotFoundException();
    final rawList = existing['likedBy'];
    final currentLiked = <String>[];
    final seen = <String>{};
    if (rawList is List) {
      for (final item in rawList) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty && seen.add(s)) currentLiked.add(s);
      }
    }
    final alreadyLiked = currentLiked.contains(userId);
    final nextLiked = alreadyLiked
        ? currentLiked.where((u) => u != userId).toList()
        : [...currentLiked, userId];
    existing['likedBy'] = nextLiked;
    existing['likes'] = nextLiked.length;
    return (
      liked: !alreadyLiked,
      likes: nextLiked.length,
      likedBy: List<String>.unmodifiable(nextLiked),
    );
  }

  @override
  Future<void> deleteComment({
    required String commentId,
    required String userId,
  }) async {
    if (simulateNetworkError) {
      throw Exception('Falha de rede simulada ao excluir comentário');
    }
    final existing = _docs[commentId];
    if (existing == null) throw const CommentNotFoundException();
    final authorId = (existing['userId'] ?? existing['uid'] ?? '')
        .toString()
        .trim();
    if (authorId != userId) {
      throw const CommentPermissionDeniedException();
    }
    _docs.remove(commentId);
  }
}

class CommentsService {
  static const int defaultPageSize = 15;
  static const int maxCommentLength = 800;

  static CommentsService instance = CommentsService();

  CommentsStoreAdapter _store;
  CommentAuthorIdentity? Function()? _identityOverride;

  final Set<String> _inFlightLikes = <String>{};
  final Set<String> _inFlightDeletes = <String>{};
  final Map<String, String> _memoryDrafts = <String, String>{};

  CommentsService({
    CommentsStoreAdapter? store,
    CommentAuthorIdentity? Function()? identityResolver,
  }) : _store = store ?? const FirestoreCommentsStoreAdapter(),
       _identityOverride = identityResolver;

  @visibleForTesting
  void configureForTesting({
    CommentsStoreAdapter? store,
    CommentAuthorIdentity? Function()? identityResolver,
  }) {
    if (store != null) _store = store;
    _identityOverride = identityResolver;
    _inFlightLikes.clear();
    _inFlightDeletes.clear();
    _memoryDrafts.clear();
  }

  @visibleForTesting
  void resetToDefault() {
    _store = const FirestoreCommentsStoreAdapter();
    _identityOverride = null;
    _inFlightLikes.clear();
    _inFlightDeletes.clear();
    _memoryDrafts.clear();
  }

  CommentAuthorIdentity? resolveCurrentUserIdentity() {
    if (_identityOverride != null) {
      return _identityOverride!();
    }
    User? user = CloudAuthService.currentUser.value;
    if (user == null && CloudAuthService.isFirebaseAvailable.value) {
      try {
        user = FirebaseAuth.instance.currentUser;
      } catch (_) {}
    }
    if (user == null || user.uid.trim().isEmpty) return null;

    final profile = StorageService.userProfile;
    final profileName = profile.name.trim();
    final firebaseName = user.displayName?.trim() ?? '';
    final resolvedName = profileName.isNotEmpty && profileName != 'Leitor YOMI'
        ? profileName
        : (firebaseName.isNotEmpty ? firebaseName : 'Leitor YOMI');
    final clippedName = resolvedName.length > 100
        ? resolvedName.substring(0, 100)
        : resolvedName;

    final palette = ProfilePaletteService.paletteNotifier.value;
    final effectiveHue =
        (profile.blobatarHue != null && profile.blobatarHue! >= 0)
        ? profile.blobatarHue
        : profile.blobatarHue == null ? profile.seedHue : palette.hue;
    final mascotColorId = hexColorFromProfile(
      hue: effectiveHue,
      customAccentColor: profile.customAccentColor,
    );

    final photo = (profile.avatarImagePath?.startsWith('http') ?? false)
        ? profile.avatarImagePath
        : user.photoURL;

    return CommentAuthorIdentity(
      userId: user.uid.trim(),
      userName: clippedName,
      userPhotoUrl: (photo != null && photo.trim().isNotEmpty)
          ? photo.trim()
          : null,
      mascotColorId: mascotColorId,
      mascotExpressionId: profile.blobatarExpression.trim().isEmpty
          ? 'happy'
          : profile.blobatarExpression.trim(),
      mascotShapeId: profile.blobatarShape.trim().isEmpty
          ? 'auto'
          : profile.blobatarShape.trim(),
    );
  }

  Future<CommentsPageResult> fetchCommentsPage({
    required String targetId,
    CommentTargetType targetType = CommentTargetType.manga,
    int pageSize = defaultPageSize,
    int? cursorCreatedAt,
  }) async {
    final trimmed = targetId.trim();
    final canonicalId = normalizeCommentTargetId(
      trimmed,
      targetType: targetType,
    );
    if (canonicalId.isEmpty) {
      return const CommentsPageResult(
        comments: [],
        nextCursor: null,
        hasMore: false,
        totalCount: 0,
      );
    }

    final candidates = <String>{canonicalId, trimmed}
      ..removeWhere((element) => element.isEmpty);

    final rawEntries = await _store.fetchCommentsRaw(
      targetIdCandidates: candidates.toList(),
      targetType: targetType,
    );

    final byId = <String, YomiComment>{};
    for (final entry in rawEntries) {
      final comment = YomiComment.fromFirestoreMap(
        entry.key,
        entry.value,
        fallbackTargetId: canonicalId,
      );
      if (comment.targetType == targetType &&
          comment.targetId == canonicalId &&
          comment.text.trim().isNotEmpty) {
        byId[entry.key] = comment;
      }
    }

    final sorted = byId.values.toList()
      ..sort((a, b) {
        final cmp = b.createdAt.compareTo(a.createdAt);
        return cmp != 0 ? cmp : b.id.compareTo(a.id);
      });

    final clampedSize = pageSize.clamp(1, 100);
    final filtered = cursorCreatedAt != null
        ? sorted.where((c) => c.createdAt < cursorCreatedAt).toList()
        : sorted;
    final pageItems = filtered.take(clampedSize).toList();
    final hasMore = filtered.length > pageItems.length;
    final nextCursor = hasMore && pageItems.isNotEmpty
        ? pageItems.last.createdAt
        : null;

    return CommentsPageResult(
      comments: pageItems,
      nextCursor: nextCursor,
      hasMore: hasMore,
      totalCount: sorted.length,
    );
  }

  Future<YomiComment> postComment({
    required String targetId,
    CommentTargetType targetType = CommentTargetType.manga,
    required String text,
    bool isSpoiler = false,
  }) async {
    final identity = resolveCurrentUserIdentity();
    if (identity == null) {
      throw const CommentAuthRequiredException(
        'Entre na sua conta para publicar comentários.',
      );
    }

    final canonicalId = normalizeCommentTargetId(
      targetId,
      targetType: targetType,
    );
    if (canonicalId.isEmpty) {
      throw const CommentValidationException('Destino do comentário inválido.');
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const CommentValidationException(
        'Escreva algo antes de publicar.',
      );
    }
    if (trimmed.length > maxCommentLength) {
      throw const CommentValidationException(
        'O comentário excede o limite de $maxCommentLength caracteres.',
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final draftModel = YomiComment(
      id: '',
      targetId: canonicalId,
      targetType: targetType,
      userId: identity.userId,
      userName: identity.userName,
      userPhotoUrl: identity.userPhotoUrl,
      mascotColorId: identity.mascotColorId,
      mascotExpressionId: identity.mascotExpressionId,
      mascotShapeId: identity.mascotShapeId,
      text: trimmed,
      isSpoiler: isSpoiler,
      likes: 0,
      likedBy: const [],
      createdAt: now,
    );

    final createdId = await _store.createComment(draftModel.toFirestoreMap());
    await clearDraft(targetId: canonicalId, targetType: targetType);
    return draftModel.copyWith(id: createdId);
  }

  Future<({bool liked, int likes, List<String> likedBy})> toggleLikeComment(
    String commentId,
  ) async {
    final identity = resolveCurrentUserIdentity();
    if (identity == null) {
      throw const CommentAuthRequiredException(
        'Entre na sua conta para curtir comentários.',
      );
    }
    final cleanId = commentId.trim();
    if (cleanId.isEmpty) {
      throw const CommentValidationException('Comentário inválido.');
    }
    if (!_inFlightLikes.add(cleanId)) {
      throw StateError('Atualização de curtida já em andamento.');
    }
    try {
      return await _store.toggleLike(
        commentId: cleanId,
        userId: identity.userId,
      );
    } finally {
      _inFlightLikes.remove(cleanId);
    }
  }

  bool isLikeInFlight(String commentId) =>
      _inFlightLikes.contains(commentId.trim());

  bool isDeleteInFlight(String commentId) =>
      _inFlightDeletes.contains(commentId.trim());

  Future<void> deleteComment(String commentId) async {
    final identity = resolveCurrentUserIdentity();
    if (identity == null) {
      throw const CommentAuthRequiredException(
        'Entre na sua conta para excluir comentários.',
      );
    }
    final cleanId = commentId.trim();
    if (cleanId.isEmpty) {
      throw const CommentValidationException('Comentário inválido.');
    }
    if (!_inFlightDeletes.add(cleanId)) return;
    try {
      await _store.deleteComment(
        commentId: cleanId,
        userId: identity.userId,
      );
    } finally {
      _inFlightDeletes.remove(cleanId);
    }
  }

  String _draftKey(String targetId, CommentTargetType targetType) {
    final canonical = normalizeCommentTargetId(
      targetId,
      targetType: targetType,
    );
    return 'comment_draft_${targetType.wireValue}_$canonical';
  }

  String loadDraft({
    required String targetId,
    CommentTargetType targetType = CommentTargetType.manga,
  }) {
    final key = _draftKey(targetId, targetType);
    if (_memoryDrafts.containsKey(key)) {
      return _memoryDrafts[key]!;
    }
    if (_store is! InMemoryCommentsStoreAdapter &&
        Hive.isBoxOpen(StorageService.settingsBoxName)) {
      final raw = StorageService.settingsBox.get(key);
      return raw is String ? raw : '';
    }
    return '';
  }

  Future<void> saveDraft({
    required String targetId,
    CommentTargetType targetType = CommentTargetType.manga,
    required String text,
  }) async {
    final key = _draftKey(targetId, targetType);
    if (text.trim().isEmpty) {
      _memoryDrafts.remove(key);
      if (_store is! InMemoryCommentsStoreAdapter &&
          Hive.isBoxOpen(StorageService.settingsBoxName)) {
        await StorageService.settingsBox.delete(key);
      }
    } else {
      _memoryDrafts[key] = text;
      if (_store is! InMemoryCommentsStoreAdapter &&
          Hive.isBoxOpen(StorageService.settingsBoxName)) {
        await StorageService.settingsBox.put(key, text);
      }
    }
  }

  Future<void> clearDraft({
    required String targetId,
    CommentTargetType targetType = CommentTargetType.manga,
  }) async {
    final key = _draftKey(targetId, targetType);
    _memoryDrafts.remove(key);
    if (_store is! InMemoryCommentsStoreAdapter &&
        Hive.isBoxOpen(StorageService.settingsBoxName)) {
      await StorageService.settingsBox.delete(key);
    }
  }
}
