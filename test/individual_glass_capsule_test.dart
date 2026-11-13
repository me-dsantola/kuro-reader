import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/widgets/individual_glass_capsule.dart';

void main() {
  testWidgets('IndividualGlassCapsule renders blur, border and minimum touch target', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: IndividualGlassCapsule(
              isCircle: true,
              width: 48,
              height: 48,
              tooltip: 'Botão de Teste',
              onTap: () => tapped = true,
              child: const Icon(Icons.favorite),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(IndividualGlassCapsule), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    // Verify touch target size
    final renderBox = tester.renderObject<RenderBox>(find.byType(IndividualGlassCapsule));
    expect(renderBox.size.width, greaterThanOrEqualTo(48.0));
    expect(renderBox.size.height, greaterThanOrEqualTo(48.0));

    // Tap action
    await tester.tap(find.byType(IndividualGlassCapsule));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
