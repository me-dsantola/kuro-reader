import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/comments_service.dart';
import 'package:kuro_reader/services/profile_palette_service.dart';
import 'package:kuro_reader/widgets/comments_section_widget.dart';
import 'package:kuro_reader/widgets/reader_toolbar.dart';

void main() {
  testWidgets(
    'opening and closing chapter comments modal sheet preserves PageController page index',
    (tester) async {
      final store = InMemoryCommentsStoreAdapter();
      store.seedRawDoc('ch_c1', {
        'targetId': 'chap_99',
        'targetType': 'chapter',
        'userId': 'uid_reader',
        'userName': 'Leitor Raiz',
        'mascotColorId': '#55AAFF',
        'mascotExpressionId': 'happy',
        'mascotShapeId': 'auto',
        'text': 'Que cena absurda nessa página!',
        'isSpoiler': false,
        'likes': 2,
        'likedBy': const ['u1', 'u2'],
        'createdAt': DateTime.now().millisecondsSinceEpoch - 60000,
      });

      final service = CommentsService(
        store: store,
        identityResolver: () => const CommentAuthorIdentity(
          userId: 'uid_me',
          userName: 'Eu',
        ),
      );
      final chapter = Chapter(
        id: 'cmk_mdx_chap_99',
        chapterNumber: '12',
        title: 'Reviravolta',
        language: 'PT-BR',
        pages: 20,
      );
      final pageController = PageController(initialPage: 3);
      addTearDown(pageController.dispose);
      final palette = ProfilePaletteService.paletteNotifier.value;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (innerContext) => Stack(
                children: [
                  PageView.builder(
                    controller: pageController,
                    itemCount: 10,
                    itemBuilder: (_, idx) => Center(child: Text('Página $idx')),
                  ),
                  ReaderToolbar(
                    title: 'Obra Teste',
                    chapter: 'Cap. 12',
                    page: 4,
                    total: 10,
                    webtoon: false,
                    offline: false,
                    onBack: () {},
                    onMode: () {},
                    onComplete: () {},
                    onComments: () {
                      showChapterCommentsSheet(
                        innerContext,
                        chapter: chapter,
                        mangaTitle: 'Obra Teste',
                        palette: palette,
                        service: service,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Garante que estamos na página 3 antes de abrir a folha de comentários
      expect(pageController.page?.round(), 3);
      expect(find.text('Página 3'), findsOneWidget);
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.forum_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Comentários · Cap. 12'), findsOneWidget);
      expect(find.text('Que cena absurda nessa página!'), findsOneWidget);

      await tester.tap(find.byTooltip('Fechar comentários'));
      await tester.pumpAndSettle();

      expect(find.text('Comentários · Cap. 12'), findsNothing);
      expect(pageController.page?.round(), 3);
      expect(find.text('Página 3'), findsOneWidget);
    },
  );
}
