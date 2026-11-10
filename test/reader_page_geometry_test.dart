import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/reader_page_geometry.dart';
import 'package:kuro_reader/services/local_page_dimensions.dart';
import 'package:kuro_reader/models/reader_anchor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('page extents do not depend on how many images are mounted', () {
    final geometry = ReaderPageGeometry(10);
    geometry.updateRatios({for (var i = 0; i < 10; i++) i: 0.5}, 360, 0);
    expect(geometry.offsetOf(10, 360), 7200);
    expect(geometry.pageAt(2250, 360), 3);
    expect(geometry.extentAt(3, 360), 720);
  });

  test('new dimensions above the viewport preserve its page and fraction', () {
    final geometry = ReaderPageGeometry(10);
    final offset = geometry.extentAt(0, 360) * 3.5;
    final corrected = geometry.updateRatios(
      {0: 0.25, 1: 0.5, 3: 0.5},
      360,
      offset,
    );
    expect(geometry.pageAt(corrected, 360), 3);
    expect(corrected - geometry.offsetOf(3, 360), 360);
  });

  test(
    'footer position and invalid image metadata are handled without collapse',
    () {
      final geometry = ReaderPageGeometry(2);
      final corrected = geometry.updateRatios(
        {0: 0.5, 1: 0.5},
        360,
        geometry.offsetOf(2, 360) + 50,
      );
      expect(corrected, 1490);
      geometry.updateRatios({0: double.nan, 1: 0, -1: 2, 5: 1}, 360, 0);
      expect(geometry.extentAt(0, 360), 720);
      expect(geometry.extentAt(1, 360), 720);
    },
  );

  test(
    'offline dimensions are read before display and damaged files are isolated',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yomi_dimensions_',
      );
      try {
        final valid = File('${directory.path}/page.png');
        await valid.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAABAAAAAgCAIAAACU62+bAAAAHElEQVR4nGN4KOtBEmIY1TCqYVTDqIZRDSNBAwBtMowfZv2fjwAAAABJRU5ErkJggg==',
          ),
        );
        final damaged = File('${directory.path}/damaged.png');
        await damaged.writeAsString('damaged image');
        final ratios = await LocalPageDimensions.read([
          valid.path,
          damaged.path,
        ]);
        expect(ratios, {0: 0.5});
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('saved chapter anchor restores at a different screen width', () {
    final geometry = ReaderPageGeometry(10)
      ..updateRatios({for (var i = 0; i < 10; i++) i: 0.5}, 360, 0);
    final anchor = geometry.anchorAt(1800, 360);
    final restored = ReaderAnchor.fromMap(anchor.toMap())!;
    expect(restored.page, 2);
    expect(restored.fraction, 0.5);
    expect(geometry.offsetFor(restored, 640), 3200);
    expect(ReaderAnchor.fromMap({'page': -1, 'fraction': 0.5}), isNull);
  });
}
