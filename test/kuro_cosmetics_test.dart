import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/services/kuro_cosmetics_service.dart';
import 'package:kuro_reader/widgets/yomi_bloub_companion.dart';
import 'package:kuro_reader/widgets/kuro_accessories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KuroCatalog catalog;
  setUpAll(() async {
    catalog = KuroCatalog(
      jsonDecode(await rootBundle.loadString('assets/mascot/cosmetics.json'))
          as Map<String, dynamic>,
    );
  });
  test('season dates and overrides do not bypass claim eligibility', () {
    expect(
      catalog.available('christmas', DateTime.parse('2026-12-01T02:59:59Z')),
      false,
    );
    expect(
      catalog.available('christmas', DateTime.parse('2026-12-01T03:00:00Z')),
      true,
    );
    expect(
      catalog.available('christmas', DateTime.parse('2027-01-01T03:00:00Z')),
      false,
    );
    final now = DateTime.parse('2026-11-17T12:00:00Z');
    expect(catalog.active(now, override: 'christmas')?['id'], 'christmas');
    expect(catalog.available('christmas', now), false);
    expect(
      catalog.active(DateTime.parse('2026-12-30T12:00:00Z'))?['id'],
      'newyear',
    );
  });
  test('permanent wardrobe combines slots and rejects forged ownership', () {
    final e = {
      'aura': 'aurora',
      'scarf': 'winter_scarf',
      'hat': 'santa_hat',
      'floating': 'little_star',
    };
    expect(catalog.sanitize(e, e.values.toSet()), e);
    expect(catalog.sanitize(e, {}), emptyKuroEquipment);
    expect(catalog.sanitize({'hat': 'aurora'}, {'aurora'}), emptyKuroEquipment);
  });
  test('native anchors are finite on customized geometry', () async {
    final atlas = await BloubAtlas.load();
    for (final shape in ['cercle', 'goutte', 'capsule', 'triangle']) {
      final a = KuroAttachmentAnchors.fromBody(
        atlas.sampleBody('idle', 1, shape),
      );
      expect(a.width, greaterThan(20));
      expect(a.top.dy, lessThan(a.center.dy));
      expect(a.rotation.isFinite, true);
    }
  });
  testWidgets(
    'four equipped slots paint and reduced motion keeps the outfit visible',
    (tester) async {
      await tester.runAsync(() => BloubAtlas.load());
      KuroCosmeticsService.instance.catalog = catalog;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: YomiBloubCompanion(
                context: BloubContext.profile,
                size: 200,
                equipment: const {
                  'aura': 'aurora',
                  'scarf': 'winter_scarf',
                  'hat': 'santa_hat',
                  'floating': 'little_star',
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final dynamic painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(YomiBloubCompanion),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter;
      expect(painter.frame().accessoryAlpha, 1);
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
