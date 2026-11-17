import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/widgets/yomi_bloub_companion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native vector states render, transition, respect reduced motion and dispose',
    (tester) async {
      await tester.runAsync(() => BloubAtlas.load());
      final key = GlobalKey();
      Future<void> show(BloubContext context, {bool reduced = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xFF101529),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(800, 600),
                disableAnimations: reduced,
              ),
              child: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: YomiBloubCompanion(size: 300, context: context),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      await show(BloubContext.profile);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      final dynamic painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(YomiBloubCompanion),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter;
      expect(
        painter.frame(),
        isNotNull,
        reason: 'The real atlas must render, not the loading fallback',
      );
      final output = Platform.environment['YOMI_BLOUB_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(output).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await show(BloubContext.complete);
      for (var i = 0; i < 260; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      await show(BloubContext.library, reduced: true);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
