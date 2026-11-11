import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/services/device_state_service.dart';
import 'package:kuro_reader/widgets/adaptive_app_shell.dart';

void main() {
  test('battery and connection observations remain independent', () {
    final service = DeviceStateService();
    service.applyNativeState({'batteryPercent': 15, 'internet': 'offline'});
    expect(service.value.lowBattery, isTrue);
    expect(service.value.internet, InternetState.offline);
    service.applyNativeState({
      'batteryPercent': 15,
      'charging': true,
      'internet': 'online',
    });
    expect(service.value.lowBattery, isFalse);
    expect(service.value.internet, InternetState.online);
    service.applyNativeState({'batteryPercent': -1, 'powerSaving': true});
    expect(service.value.batteryPercent, isNull);
    expect(service.value.reduceEffects, isTrue);
    expect(service.value.internet, InternetState.unknown);
    service.dispose();
  });

  testWidgets(
    'delayed requests show slow feedback and fast responses recover',
    (tester) async {
      final service = DeviceStateService();
      final pending = Completer<int>();
      final request = service.observe(() => pending.future);
      await tester.pump(const Duration(seconds: 3));
      expect(service.value.slow, isTrue);
      expect(service.value.internet, InternetState.unknown);
      pending.complete(1);
      expect(await request, 1);
      await service.observe(() async => 2);
      await service.observe(() async => 3);
      expect(service.value.slow, isFalse);
      await expectLater(
        service.observe(() => Future<int>.error(StateError('provider down'))),
        throwsStateError,
      );
      expect(service.value.internet, InternetState.unknown);
      service.dispose();
    },
  );

  testWidgets(
    'offline and low battery stay visible above routes and restore appearance',
    (tester) async {
      final service = DeviceStateService();
      var reduced = false;
      service.applyNativeState({'batteryPercent': 5, 'internet': 'offline'});
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AdaptiveAppShell(service: service, child: child!),
          home: Builder(
            builder: (context) {
              reduced =
                  MediaQuery.disableAnimationsOf(context) &&
                  MediaQuery.highContrastOf(context);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(body: Text('Leitor')),
                      ),
                    ),
                    child: const Text('Abrir leitor'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(find.textContaining('Sem internet'), findsOneWidget);
      expect(find.textContaining('Bateria 5%'), findsOneWidget);
      expect(reduced, isTrue);
      await tester.tap(find.text('Abrir leitor'));
      await tester.pumpAndSettle();
      expect(find.text('Leitor'), findsOneWidget);
      expect(find.textContaining('Sem internet'), findsOneWidget);
      service.applyNativeState({'batteryPercent': 80, 'internet': 'online'});
      await tester.pumpAndSettle();
      expect(find.textContaining('Sem internet'), findsNothing);
      expect(find.textContaining('Bateria 5%'), findsNothing);
      expect(find.text('Leitor'), findsOneWidget);
      expect(
        MediaQuery.disableAnimationsOf(tester.element(find.text('Leitor'))),
        isFalse,
      );
      service.applyNativeState({'powerSaving': true});
      await tester.pump();
      expect(find.textContaining('Economia de energia'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('Economia de energia'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );
}
