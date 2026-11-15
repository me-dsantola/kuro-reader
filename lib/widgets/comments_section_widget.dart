import 'dart:async';
import 'package:flutter/material.dart';
import '../models/comment_models.dart';
import '../models/manga_models.dart';
import '../screens/auth_screen.dart';
import '../services/cloud_auth_service.dart';
import '../services/comments_service.dart';
import '../services/profile_palette_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/yomi_blobatar_studio.dart';
import '../widgets/yomi_brand_widgets.dart';

String formatCommentRelativeTime(int epochMs) {
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(epochMs),
  );
  if (diff.inSeconds < 60) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays < 30) return 'há ${diff.inDays}d';
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return '$day/$month/${dt.year}';
}

/// Abre o painel de comentários do capítulo em modal bottom sheet sem interferir
/// na posição de leitura atual (paginado ou webtoon).
Future<void> showChapterCommentsSheet(
  BuildContext context, {
  required Chapter chapter,
  required String mangaTitle,
  required ProfileAdaptivePalette palette,
  CommentsService? service,
  VoidCallback? onRequestSignIn,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.48,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.forum_rounded,
                        color: palette.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Comentários · Cap. ${chapter.chapterNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              mangaTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.soft.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar comentários',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      16 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: YomiCommentsSection(
                      targetId: chapter.id,
                      targetType: CommentTargetType.chapter,
                      title: 'Discussão do capítulo',
                      palette: palette,
                      lazyLoadUntilExpanded: false,
                      embeddedInSheet: true,
                      service: service,
                      onRequestSignIn: onRequestSignIn,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class YomiCommentsSection extends StatefulWidget {
  final String targetId;
  final CommentTargetType targetType;
  final String title;
  final ProfileAdaptivePalette palette;
  final bool lazyLoadUntilExpanded;
  final bool embeddedInSheet;
  final CommentsService? service;
  final VoidCallback? onRequestSignIn;

  const YomiCommentsSection({
    super.key,
    required this.targetId,
    this.targetType = CommentTargetType.manga,
    this.title = 'Comentários',
    required this.palette,
    this.lazyLoadUntilExpanded = true,
    this.embeddedInSheet = false,
    this.service,
    this.onRequestSignIn,
  });

  @override
  State<YomiCommentsSection> createState() => _YomiCommentsSectionState();
}

class _YomiCommentsSectionState extends State<YomiCommentsSection> {
  final TextEditingController _composerController = TextEditingController();
  final Set<String> _revealedSpoilers = <String>{};
  final Set<String> _likingIds = <String>{};
  final Set<String> _deletingIds = <String>{};

  late bool _expanded;
  bool _hasRequestedLoad = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _submitting = false;
  bool _isSpoiler = false;
  String? _loadError;
  String? _submitError;

  List<YomiComment> _comments = const [];
  int _totalCount = 0;
  int? _nextCursor;
  bool _hasMore = false;

  CommentsService get _service => widget.service ?? CommentsService.instance;

  String get _canonicalTargetId => normalizeCommentTargetId(
    widget.targetId,
    targetType: widget.targetType,
  );

  @override
  void initState() {
    super.initState();
    _expanded = !widget.lazyLoadUntilExpanded;
    final draft = _service.loadDraft(
      targetId: widget.targetId,
      targetType: widget.targetType,
    );
    if (draft.isNotEmpty) {
      _composerController.text = draft;
    }
    CloudAuthService.currentUser.addListener(_onAuthChanged);
    if (_expanded) {
      unawaited(_loadInitial());
    }
  }

  @override
  void didUpdateWidget(covariant YomiCommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetId != widget.targetId ||
        oldWidget.targetType != widget.targetType) {
      _hasRequestedLoad = false;
      _comments = const [];
      _totalCount = 0;
      _nextCursor = null;
      _hasMore = false;
      _loadError = null;
      _submitError = null;
      _revealedSpoilers.clear();
      _composerController.text = _service.loadDraft(
        targetId: widget.targetId,
        targetType: widget.targetType,
      );
      if (_expanded) {
        unawaited(_loadInitial());
      }
    }
  }

  @override
  void dispose() {
    CloudAuthService.currentUser.removeListener(_onAuthChanged);
    _composerController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _expandAndLoad() {
    if (_expanded && _hasRequestedLoad) return;
    setState(() => _expanded = true);
    if (!_hasRequestedLoad) {
      unawaited(_loadInitial());
    }
  }

  Future<void> _loadInitial() async {
    if (_canonicalTargetId.isEmpty) return;
    _hasRequestedLoad = true;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _service.fetchCommentsPage(
        targetId: widget.targetId,
        targetType: widget.targetType,
      );
      if (!mounted) return;
      setState(() {
        _comments = page.comments;
        _totalCount = page.totalCount;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError =
            'Não foi possível carregar os comentários. Verifique sua conexão.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchCommentsPage(
        targetId: widget.targetId,
        targetType: widget.targetType,
        cursorCreatedAt: _nextCursor,
      );
      if (!mounted) return;
      final seenIds = _comments.map((c) => c.id).toSet();
      setState(() {
        _comments = [
          ..._comments,
          ...page.comments.where((c) => seenIds.add(c.id)),
        ];
        _totalCount = page.totalCount > _comments.length
            ? page.totalCount
            : _comments.length;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      AppFeedback.message(
        context,
        'Não foi possível carregar mais comentários agora.',
      );
    }
  }

  void _promptSignIn() {
    if (widget.onRequestSignIn != null) {
      widget.onRequestSignIn!();
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (routeContext) => KuroAuthScreen(
              onAuthenticated: () => Navigator.of(routeContext).pop(),
            ),
          ),
        )
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    final rawText = _composerController.text;
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      setState(() => _submitError = 'Escreva um comentário antes de enviar.');
      return;
    }
    if (trimmed.length > CommentsService.maxCommentLength) {
      setState(
        () => _submitError =
            'Máximo de ${CommentsService.maxCommentLength} caracteres.',
      );
      return;
    }
    if (_service.resolveCurrentUserIdentity() == null) {
      _promptSignIn();
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final created = await _service.postComment(
        targetId: widget.targetId,
        targetType: widget.targetType,
        text: trimmed,
        isSpoiler: _isSpoiler,
      );
      if (!mounted) return;
      setState(() {
        _comments = [created, ..._comments];
        _totalCount = _totalCount + 1;
        _composerController.clear();
        _isSpoiler = false;
        _submitting = false;
      });
      AppFeedback.message(context, 'Comentário publicado!');
    } on CommentAuthRequiredException {
      if (!mounted) return;
      setState(() => _submitting = false);
      _promptSignIn();
    } catch (_) {
      // Nunca mascarar falha criando item falso na lista; preserva o texto digitado.
      unawaited(
        _service.saveDraft(
          targetId: widget.targetId,
          targetType: widget.targetType,
          text: rawText,
        ),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError =
            'Não foi possível publicar. Seu texto foi mantido para tentar novamente.';
      });
      AppFeedback.message(
        context,
        'Falha ao enviar comentário. Texto preservado.',
      );
    }
  }

  Future<void> _handleToggleLike(YomiComment comment) async {
    final identity = _service.resolveCurrentUserIdentity();
    if (identity == null) {
      _promptSignIn();
      return;
    }
    if (_likingIds.contains(comment.id)) return;

    setState(() => _likingIds.add(comment.id));
    try {
      final result = await _service.toggleLikeComment(comment.id);
      if (!mounted) return;
      setState(() {
        _comments = _comments
            .map(
              (c) => c.id == comment.id
                  ? c.copyWith(likes: result.likes, likedBy: result.likedBy)
                  : c,
            )
            .toList();
      });
    } catch (_) {
      if (mounted) {
        AppFeedback.message(context, 'Não foi possível atualizar a curtida.');
      }
    } finally {
      if (mounted) {
        setState(() => _likingIds.remove(comment.id));
      }
    }
  }

  Future<void> _confirmAndDelete(YomiComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.palette.surface,
        title: const Text('Excluir comentário?'),
        content: const Text(
          'Esta ação removerá seu comentário permanentemente para todos os leitores.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingIds.add(comment.id));
    try {
      await _service.deleteComment(comment.id);
      if (!mounted) return;
      setState(() {
        _comments = _comments.where((c) => c.id != comment.id).toList();
        _totalCount = _totalCount > 0 ? _totalCount - 1 : 0;
      });
      AppFeedback.message(context, 'Comentário excluído.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.message(
        context,
        e is CommentPermissionDeniedException
            ? e.message
            : 'Não foi possível excluir o comentário.',
      );
    } finally {
      if (mounted) {
        setState(() => _deletingIds.remove(comment.id));
      }
    }
  }

  Widget _buildAvatar(YomiComment comment, bool reduceMotion) {
    final hue = hueFromHexColor(comment.mascotColorId);
    final synthProfile = UserProfile(
      name: comment.userName,
      blobatarName: comment.userName,
      blobatarSeed: comment.userName,
      blobatarShape: comment.mascotShapeId ?? 'auto',
      blobatarExpression: comment.mascotExpressionId ?? 'happy',
      blobatarHue: hue,
      blobatarBackground: 'squircle',
      blobatarAnimated: !reduceMotion,
      blobatarInteractive: false,
    );

    final blobWidget = YomiProfileBlobatar(
      profile: synthProfile,
      size: 36,
      adaptiveHue: hue ?? widget.palette.hue,
      interactiveCycleOnTap: false,
    );

    final hasMascotMeta =
        comment.mascotColorId != null ||
        comment.mascotExpressionId != null ||
        comment.mascotShapeId != null;

    if (!hasMascotMeta &&
        comment.userPhotoUrl != null &&
        comment.userPhotoUrl!.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          comment.userPhotoUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => blobWidget,
        ),
      );
    }

    return SizedBox(width: 36, height: 36, child: blobWidget);
  }

  Widget _buildComposer(CommentAuthorIdentity? identity) {
    final palette = widget.palette;
    if (identity == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: YomiPalette.pitchBlack.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: palette.soft),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Entre na sua conta YOMI para comentar e curtir.',
                style: TextStyle(fontSize: 12.5, color: Colors.white70),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              onPressed: _promptSignIn,
              child: const Text('Entrar'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YomiPalette.pitchBlack.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _submitError != null
              ? Colors.redAccent.withValues(alpha: 0.55)
              : palette.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _composerController,
            enabled: !_submitting,
            maxLines: 4,
            minLines: 2,
            maxLength: CommentsService.maxCommentLength,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            onChanged: (val) {
              if (_submitError != null) {
                setState(() => _submitError = null);
              }
              unawaited(
                _service.saveDraft(
                  targetId: widget.targetId,
                  targetType: widget.targetType,
                  text: val,
                ),
              );
            },
            decoration: InputDecoration(
              hintText: widget.targetType == CommentTargetType.chapter
                  ? 'Compartilhe o que achou deste capítulo...'
                  : 'Compartilhe sua opinião sobre esta obra...',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
              ),
              border: InputBorder.none,
              counterStyle: const TextStyle(
                fontSize: 10.5,
                color: Colors.white38,
              ),
              isDense: true,
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 6),
            Text(
              _submitError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                selected: _isSpoiler,
                label: const Text('Spoiler', style: TextStyle(fontSize: 11.5)),
                avatar: Icon(
                  _isSpoiler
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 15,
                  color: _isSpoiler ? Colors.amberAccent : Colors.white70,
                ),
                backgroundColor: palette.surface,
                selectedColor: Colors.amber.withValues(alpha: 0.2),
                side: BorderSide(
                  color: _isSpoiler ? Colors.amberAccent : Colors.white24,
                ),
                onSelected: _submitting
                    ? null
                    : (val) => setState(() => _isSpoiler = val),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onPressed: _submitting ? null : _handleSubmit,
                icon: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(_submitting ? 'Enviando...' : 'Publicar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(
    YomiComment comment,
    CommentAuthorIdentity? identity,
    bool reduceMotion,
  ) {
    final palette = widget.palette;
    final currentUid = identity?.userId;
    final isMine = currentUid != null && comment.userId == currentUid;
    final isLiked = comment.isLikedBy(currentUid);
    final isRevealed = _revealedSpoilers.contains(comment.id);
    final spoilerHidden = comment.isSpoiler && !isRevealed;
    final likeBusy = _likingIds.contains(comment.id);
    final deleteBusy = _deletingIds.contains(comment.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YomiPalette.pitchBlack.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMine
              ? palette.primary.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildAvatar(comment, reduceMotion),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            comment.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: palette.primary.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'VOCÊ',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: palette.soft,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      formatCommentRelativeTime(comment.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              if (comment.isSpoiler)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'SPOILER',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.amberAccent,
                    ),
                  ),
                ),
              if (isMine)
                IconButton(
                  tooltip: 'Excluir comentário',
                  visualDensity: VisualDensity.compact,
                  onPressed: deleteBusy
                      ? null
                      : () => _confirmAndDelete(comment),
                  icon: deleteBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (spoilerHidden)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () =>
                  setState(() => _revealedSpoilers.add(comment.id)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amberAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      size: 16,
                      color: Colors.amberAccent,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Este comentário contém spoilers · Toque para revelar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.text,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: Colors.white,
                  ),
                ),
                if (comment.isSpoiler)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      onTap: () =>
                          setState(() => _revealedSpoilers.remove(comment.id)),
                      child: const Text(
                        'Ocultar spoiler',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amberAccent,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: likeBusy ? null : () => _handleToggleLike(comment),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isLiked
                        ? palette.primary.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isLiked
                          ? palette.primary.withValues(alpha: 0.55)
                          : Colors.white12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 15,
                        color: isLiked ? palette.primary : Colors.white70,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${comment.likes}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isLiked ? palette.soft : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final identity = _service.resolveCurrentUserIdentity();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (!_expanded) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _expandAndLoad,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.forum_outlined, color: palette.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Toque para ver ou publicar comentários da comunidade',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.soft.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.expand_more_rounded, color: palette.secondary),
              ],
            ),
          ),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embeddedInSheet) ...[
          Row(
            children: [
              Icon(Icons.forum_rounded, color: palette.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.title}${_hasRequestedLoad && !_loading ? ' ($_totalCount)' : ''}',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar comentários',
                onPressed: _loading ? null : _loadInitial,
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 19,
                  color: palette.secondary,
                ),
              ),
              if (widget.lazyLoadUntilExpanded)
                IconButton(
                  tooltip: 'Recolher comentários',
                  onPressed: () => setState(() => _expanded = false),
                  icon: const Icon(
                    Icons.expand_less_rounded,
                    color: Colors.white54,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_totalCount ${_totalCount == 1 ? 'comentário' : 'comentários'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: palette.soft,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loading ? null : _loadInitial,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Atualizar'),
                ),
              ],
            ),
          ),
        _buildComposer(identity),
        const SizedBox(height: 14),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: CircularProgressIndicator(color: palette.primary),
            ),
          )
        else if (_loadError != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  color: Colors.redAccent,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loadInitial,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          )
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 32,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ainda não há comentários aqui. Seja o primeiro a opinar!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.white54),
                ),
              ],
            ),
          )
        else ...[
          for (final comment in _comments)
            _buildCommentItem(comment, identity, reduceMotion),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.soft,
                  side: BorderSide(
                    color: palette.primary.withValues(alpha: 0.4),
                  ),
                ),
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.primary,
                        ),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  _loadingMore
                      ? 'Carregando...'
                      : 'Carregar mais comentários',
                ),
              ),
            ),
        ],
      ],
    );

    if (widget.embeddedInSheet) return content;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.primary.withValues(alpha: 0.26)),
      ),
      child: content,
    );
  }
}
