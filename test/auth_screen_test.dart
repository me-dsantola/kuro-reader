import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/screens/auth_screen.dart';
import 'package:kuro_reader/services/cloud_auth_service.dart';
import 'package:kuro_reader/widgets/yomi_brand_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('KuroAuthScreen renders clean minimalist UI, vector brand logo and Google Sign-In button', (tester) async {
    CloudAuthService.bypassAuthForTesting = false;
    var authenticatedCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: KuroAuthScreen(
          onAuthenticated: () {
            authenticatedCalled = true;
          },
        ),
      ),
    );

    expect(find.text('YOMI'), findsOneWidget);
    expect(find.text('Sua biblioteca definitiva de mangás.'), findsOneWidget);
    expect(find.text('Continuar com o Google'), findsOneWidget);
    expect(find.byType(YomiBrandSvgLogo), findsOneWidget);
    expect(authenticatedCalled, isFalse);

    CloudAuthService.bypassAuthForTesting = true;
  });
}
