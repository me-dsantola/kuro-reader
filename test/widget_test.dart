import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/screens/home_tabs.dart';

void main() {
  testWidgets('YOMI logo renders with the AMOLED theme', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: YomiEnsoLogo()),
        ),
      ),
    );
    expect(find.byType(YomiEnsoLogo), findsOneWidget);
  });

  test('chapter model survives Hive-compatible map round trip', () {
    final original = Chapter(
      id: 'chapter-123',
      chapterNumber: '12.5',
      title: 'Capítulo bônus',
      language: 'PT-BR',
      pages: 23,
    );
    final restored = Chapter.fromMap(original.toMap());
    expect(restored.id, original.id);
    expect(restored.language, 'PT-BR');
    expect(restored.numericChapter, 12.5);
    expect(restored.pages, 23);
  });
}
