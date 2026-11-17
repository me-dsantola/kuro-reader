import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/widgets/yomi_bloub_companion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every native action retains the selected silhouette', () async {
    final atlas = await BloubAtlas.load();
    final clips = atlas.data['clips'] as Map<String, dynamic>;
    for (final state in clips.keys) {
      if (state == 'thinking') {
        continue; // Intentional three-dot loading symbol.
      }
      for (final t in [0.0, .8, 2.49, 2.51, 4.0]) {
        final circle = atlas.sampleBody(state, t, 'cercle');
        for (final shape in [
          'galet',
          'squircle',
          'capsule',
          'triangle',
          'hexagone',
          'nuage',
          'goutte',
        ]) {
          final custom = atlas.sampleBody(state, t, shape);
          expect(custom.length, 128);
          expect(custom.every((n) => n.isFinite), isTrue);
          final difference = List.generate(
            128,
            (i) => (custom[i] - circle[i]).abs(),
          ).reduce((a, b) => a > b ? a : b);
          expect(
            difference,
            greaterThan(1),
            reason: '$shape must not become a circle in $state at $t',
          );
        }
      }
    }
  });
  test(
    'loading becomes three small circles without replacing the saved shape',
    () async {
      final atlas = await BloubAtlas.load();
      expect(atlas.data['symbolStates'], contains('thinking'));
      for (final shape in ['cercle', 'goutte', 'triangle']) {
        final loading = atlas.sampleBody('thinking', 1.2, shape);
        final xs = [for (var i = 0; i < loading.length; i += 2) loading[i]];
        final width =
            xs.reduce((a, b) => a > b ? a : b) -
            xs.reduce((a, b) => a < b ? a : b);
        expect(width, inInclusiveRange(30, 42));
        final frame = (atlas.data['clips'] as Map)['thinking'][29] as Map;
        expect(frame['d'], hasLength(2)); // Center is the body; two side dots.
        expect(atlas.sampleBody('idle', 0, shape), isNot(loading));
      }
    },
  );
  testWidgets(
    'loading returns from three dots to the selected body without a cut',
    (tester) async {
      await tester.runAsync(() => BloubAtlas.load());
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: YomiBloubCompanion(
                size: 300,
                shape: 'triangle',
                context: BloubContext.library,
                loading: true,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final dynamic painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(YomiBloubCompanion),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter;
      double width(dynamic frame) {
        final body = frame.body as List<double>;
        final xs = [for (var i = 0; i < body.length; i += 2) body[i]];
        return xs.reduce((a, b) => a > b ? a : b) -
            xs.reduce((a, b) => a < b ? a : b);
      }

      expect(width(painter.frame()), inInclusiveRange(30, 42));
      expect(painter.frame().dots, hasLength(2));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 64));
      }
      expect(
        width(painter.frame()),
        inInclusiveRange(30, 42),
        reason: 'Stay in loading until the operation ends',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: YomiBloubCompanion(
                size: 300,
                shape: 'triangle',
                context: BloubContext.library,
                loading: false,
              ),
            ),
          ),
        ),
      );
      var previous = List<double>.from(painter.frame().body as List<double>);
      for (var i = 0; i < 230; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final body = painter.frame().body as List<double>;
        final step = List.generate(
          body.length,
          (j) => (body[j] - previous[j]).abs(),
        ).reduce((a, b) => a > b ? a : b);
        expect(
          step,
          lessThan(12),
          reason: 'Loading exit must interpolate every frame',
        );
        previous = List<double>.from(body);
      }
      expect(width(painter.frame()), greaterThan(100));
      expect(painter.frame().dots, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('idle never starts unrelated actions while the user waits', (
    tester,
  ) async {
    await tester.runAsync(() => BloubAtlas.load());
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: YomiBloubCompanion(
              size: 200,
              context: BloubContext.profile,
              interactive: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    final dynamic painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(YomiBloubCompanion),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter;
    final eyes = [
      for (final eye in painter.frame().eyes) List<double>.from(eye),
    ];
    for (var i = 0; i < 1600; i++) {
      await tester.pump(const Duration(milliseconds: 64));
      final dynamic frame = painter.frame();
      expect(frame.dots, isEmpty);
      expect(frame.arcs, isEmpty);
      for (var eye = 0; eye < eyes.length; eye++) {
        expect(frame.eyes[eye][0], closeTo(eyes[eye][0], .001));
        expect(frame.eyes[eye][1], lessThanOrEqualTo(eyes[eye][1] + .001));
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
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
