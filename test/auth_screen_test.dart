import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/screens/auth_screen.dart';
import 'package:kuro_reader/services/cloud_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('KuroAuthScreen renders welcome UI and Google Sign-In button', (tester) async {
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

    expect(find.text('Continuar com o Google'), findsOneWidget);
    expect(find.text('Backup e Sincronização em Nuvem'), findsOneWidget);
    expect(find.text('Experiência Offline Completa'), findsOneWidget);
    expect(find.text('Perfil Personalizado & Mascote'), findsOneWidget);
    expect(authenticatedCalled, isFalse);

    CloudAuthService.bypassAuthForTesting = true;
  });
}
