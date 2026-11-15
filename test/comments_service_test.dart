import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/comment_models.dart';
import 'package:kuro_reader/services/comments_service.dart';
import 'package:kuro_reader/services/profile_palette_service.dart';
import 'package:kuro_reader/widgets/comments_section_widget.dart';

class _SpyCommentsStoreAdapter extends InMemoryCommentsStoreAdapter {
  int fetchCalls = 0;

  @override
  Future<List<MapEntry<String, Map<String, dynamic>>>> fetchCommentsRaw({
    required List<String> targetIdCandidates,
    required CommentTargetType targetType,
  }) async {
    fetchCalls++;
    return super.fetchCommentsRaw(
      targetIdCandidates: targetIdCandidates,
      targetType: targetType,
    );
  }
}

void main() {

  group('Comment models & web parity helpers', () {
    test('normalizeCommentTargetId strips legacy prefixes consistently', () {
      expect(
        normalizeCommentTargetId(
          'cmk_mdx_abcd-1234',
          targetType: CommentTargetType.manga,
        ),
        'abcd-1234',
      );
      expect(
        normalizeCommentTargetId(
          'hq_mdx_xyz-99',
          targetType: CommentTargetType.manga,
        ),
        'xyz-99',
      );
      expect(
        normalizeCommentTargetId(
          'ani_mdx_12345',
          targetType: CommentTargetType.manga,
        ),
        '12345',
      );
      expect(
        normalizeCommentTargetId(
          'mal_mdx_67890',
          targetType: CommentTargetType.manga,
        ),
        '67890',
      );
      expect(
        normalizeCommentTargetId(
          'cmk_title_solo_leveling',
          targetType: CommentTargetType.manga,
        ),
        'solo_leveling',
      );
      expect(
        normalizeCommentTargetId(
          'cmk_mdx_ch-777',
          targetType: CommentTargetType.chapter,
        ),
        'ch-777',
      );
      expect(
        normalizeCommentTargetId(
          'cmk_title_ch-777',
          targetType: CommentTargetType.chapter,
        ),
        'cmk_title_ch-777',
      );
      expect(normalizeCommentTargetId('   '), '');
    });

    test('parseCommentCreatedAtMs handles epoch, Timestamp, Map and ISO strings', () {
      expect(parseCommentCreatedAtMs(1700000000), 1700000000000);
      expect(parseCommentCreatedAtMs(1700000000123), 1700000000123);
      expect(
        parseCommentCreatedAtMs(Timestamp.fromMillisecondsSinceEpoch(1700000500000)),
        1700000500000,
      );
      expect(
        parseCommentCreatedAtMs({'seconds': 1700000001, 'nanoseconds': 500000000}),
        1700000001500,
      );
      expect(
        parseCommentCreatedAtMs({'_seconds': 1700000002, '_nanoseconds': 250000000}),
        1700000002250,
      );
      expect(
        parseCommentCreatedAtMs('2026-11-15T12:00:00.000Z'),
        DateTime.parse('2026-11-15T12:00:00.000Z').millisecondsSinceEpoch,
      );
    });

    test('hueFromHexColor and hexColorFromProfile roundtrip chroma and ignore gray', () {
      final hex = hexColorFromProfile(hue: 210);
      expect(hex, isNotNull);
      expect(hex, startsWith('#'));
      final parsedHue = hueFromHexColor(hex);
      expect(parsedHue, isNotNull);
      expect(parsedHue!, closeTo(210.0, 2.5));

      expect(hueFromHexColor('#808080'), isNull);
      expect(hexColorFromProfile(customAccentColor: 0xFF7B61FF), '#7B61FF');
    });
  });

  group('CommentsService behavior', () {
    const alice = CommentAuthorIdentity(
      userId: 'uid_alice',
      userName: 'Alice YOMI',
      userPhotoUrl: 'https://example.com/alice.png',
      mascotColorId: '#7B61FF',
      mascotExpressionId: 'happy',
      mascotShapeId: 'cloud',
    );
    const bob = CommentAuthorIdentity(
      userId: 'uid_bob',
      userName: 'Bob YOMI',
      mascotColorId: '#FF5588',
      mascotExpressionId: 'cool',
      mascotShapeId: 'star',
    );

    test('paginates 15 items per page and merges prefixed legacy targetIds', () async {
      final store = InMemoryCommentsStoreAdapter();
      for (var i = 1; i <= 20; i++) {
        store.seedRawDoc('seed_$i', {
          'targetId': i.isEven ? 'cmk_mdx_manga-42' : 'manga-42',
          'targetType': 'manga',
          'userId': 'uid_alice',
          'userName': 'Alice YOMI',
          'text': 'Comentário #$i',
          'isSpoiler': false,
          'likes': 0,
          'likedBy': const <String>[],
          'createdAt': 1700000000000 + i * 1000,
        });
      }

      final service = CommentsService(store: store, identityResolver: () => alice);
      final page1 = await service.fetchCommentsPage(targetId: 'cmk_mdx_manga-42');

      expect(page1.totalCount, 20);
      expect(page1.comments.length, CommentsService.defaultPageSize);
      expect(page1.hasMore, isTrue);
      expect(page1.comments.first.text, 'Comentário #20');
      expect(page1.comments.last.text, 'Comentário #6');
      expect(page1.nextCursor, 1700000006000);

      final page2 = await service.fetchCommentsPage(
        targetId: 'cmk_mdx_manga-42',
        cursorCreatedAt: page1.nextCursor,
      );
      expect(page2.comments.length, 5);
      expect(page2.hasMore, isFalse);
      expect(page2.comments.first.text, 'Comentário #5');
      expect(page2.comments.last.text, 'Comentário #1');
    });

    test('blocks unauthenticated post/like and posts with Blobatar metadata when signed in', () async {
      final store = InMemoryCommentsStoreAdapter();
      final unauthService = CommentsService(store: store, identityResolver: () => null);

      await expectLater(
        () => unauthService.postComment(targetId: 'manga-1', text: 'Oi'),
        throwsA(isA<CommentAuthRequiredException>()),
      );
      await expectLater(
        () => unauthService.toggleLikeComment('any'),
        throwsA(isA<CommentAuthRequiredException>()),
      );

      final authService = CommentsService(store: store, identityResolver: () => alice);
      await authService.saveDraft(targetId: 'manga-1', text: 'Rascunho antigo');
      final created = await authService.postComment(
        targetId: 'hq_mdx_manga-1',
        text: 'Capítulo incrível!',
        isSpoiler: true,
      );

      expect(created.id, isNotEmpty);
      expect(created.targetId, 'manga-1');
      expect(created.userId, 'uid_alice');
      expect(created.mascotColorId, '#7B61FF');
      expect(created.mascotExpressionId, 'happy');
      expect(created.mascotShapeId, 'cloud');
      expect(created.isSpoiler, isTrue);
      expect(authService.loadDraft(targetId: 'manga-1'), '');
    });

    test('toggleLikeComment avoids duplicate UIDs and deleteComment enforces ownership', () async {
      final store = InMemoryCommentsStoreAdapter();
      store.seedRawDoc('c1', {
        'targetId': 'manga-9',
        'targetType': 'manga',
        'userId': 'uid_alice',
        'userName': 'Alice YOMI',
        'text': 'Texto base',
        'isSpoiler': false,
        'likes': 1,
        'likedBy': ['uid_alice', 'uid_alice'],
        'createdAt': 1700000001000,
      });

      final aliceService = CommentsService(store: store, identityResolver: () => alice);
      final bobService = CommentsService(store: store, identityResolver: () => bob);

      final bobLike = await bobService.toggleLikeComment('c1');
      expect(bobLike.liked, isTrue);
      expect(bobLike.likedBy, ['uid_alice', 'uid_bob']);
      expect(bobLike.likes, 2);

      final aliceUnlike = await aliceService.toggleLikeComment('c1');
      expect(aliceUnlike.liked, isFalse);
      expect(aliceUnlike.likedBy, ['uid_bob']);
      expect(aliceUnlike.likes, 1);

      await expectLater(
        () => bobService.deleteComment('c1'),
        throwsA(isA<CommentPermissionDeniedException>()),
      );
      expect(store.getRawDoc('c1'), isNotNull);

      await aliceService.deleteComment('c1');
      expect(store.getRawDoc('c1'), isNull);
    });
  });

  group('YomiCommentsSection widget', () {
    const alice = CommentAuthorIdentity(
      userId: 'uid_alice',
      userName: 'Alice Leitora',
      mascotColorId: '#6C63FF',
      mascotExpressionId: 'love',
      mascotShapeId: 'circle',
    );

    Widget buildHost({
      required CommentsService service,
      bool lazyLoadUntilExpanded = true,
    }) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: YomiCommentsSection(
              targetId: 'cmk_mdx_manga-77',
              targetType: CommentTargetType.manga,
              title: 'Comentários da Obra',
              palette: ProfilePaletteService.paletteNotifier.value,
              lazyLoadUntilExpanded: lazyLoadUntilExpanded,
              service: service,
            ),
          ),
        ),
      );
    }

    testWidgets('lazy loads only after expansion and hides/reveals spoilers', (tester) async {
      final store = _SpyCommentsStoreAdapter();
      store.seedRawDoc('sp_1', {
        'targetId': 'manga-77',
        'targetType': 'manga',
        'userId': 'uid_bob',
        'userName': 'Bob',
        'mascotColorId': '#FF7700',
        'mascotExpressionId': 'cool',
        'mascotShapeId': 'square',
        'text': 'O protagonista vence no final!',
        'isSpoiler': true,
        'likes': 3,
        'likedBy': ['uid_1', 'uid_2', 'uid_3'],
        'createdAt': DateTime.now().millisecondsSinceEpoch - 120000,
      });

      final service = CommentsService(store: store, identityResolver: () => alice);
      await tester.pumpWidget(buildHost(service: service));
      await tester.pumpAndSettle();

      // Antes de expandir, nenhuma consulta ao Firestore deve acontecer
      expect(store.fetchCalls, 0);
      expect(find.text('Comentários da Obra'), findsOneWidget);
      expect(find.text('O protagonista vence no final!'), findsNothing);

      // Expande a seção
      await tester.tap(find.text('Comentários da Obra'));
      await tester.pumpAndSettle();

      expect(store.fetchCalls, 1);
      expect(find.text('SPOILER'), findsOneWidget);
      expect(
        find.text('Este comentário contém spoilers · Toque para revelar'),
        findsOneWidget,
      );
      expect(find.text('O protagonista vence no final!'), findsNothing);

      // Revela spoiler
      await tester.tap(
        find.text('Este comentário contém spoilers · Toque para revelar'),
      );
      await tester.pumpAndSettle();

      expect(find.text('O protagonista vence no final!'), findsOneWidget);
      expect(find.text('Ocultar spoiler'), findsOneWidget);
    });

    testWidgets('preserves typed text and draft on network error without faking post', (tester) async {
      final store = _SpyCommentsStoreAdapter();
      final service = CommentsService(store: store, identityResolver: () => alice);

      await tester.pumpWidget(
        buildHost(service: service, lazyLoadUntilExpanded: false),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      const draftText = 'Comentário importante que não pode ser perdido';
      await tester.enterText(find.byType(TextField), draftText);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );

      store.simulateNetworkError = true;
      await tester.tap(find.text('Publicar'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Falha real preservada: nenhum comentário falso na lista, texto mantido no campo e salvo em rascunho
      expect(find.text(draftText), findsOneWidget);
      expect(
        find.text('Não foi possível publicar. Seu texto foi mantido para tentar novamente.'),
        findsOneWidget,
      );
      expect(service.loadDraft(targetId: 'manga-77'), draftText);

      // Ao recuperar conexão, publica com sucesso e limpa o rascunho
      store.simulateNetworkError = false;
      await tester.tap(find.text('Publicar'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(draftText), findsOneWidget);
      expect(service.loadDraft(targetId: 'manga-77'), '');
      expect(store.getRawDoc('cmt_1'), isNotNull);

      // Esvazia timers visuais/toast antes do tearDown
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
