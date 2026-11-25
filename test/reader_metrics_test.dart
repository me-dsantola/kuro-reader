import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:kuro_reader/widgets/reader_metrics_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/reader_metrics.dart';
import 'package:kuro_reader/services/backup_codec.dart';

void main() {
  test(
    'sync keeps a newer chapter undo and restores the matching read flag',
    () {
      final merged = BackupCodec.mergeCloudAndLocal(
        {
          'history': {
            'reading_metric_one': {'changedAt': '2026-11-25T15:00:00Z'},
            'read_one': false,
          },
        },
        {
          'history': {
            'reading_metric_one': {
              'changedAt': '2026-11-24T15:00:00Z',
              'readAt': '2026-11-24T15:00:00Z',
            },
            'read_one': true,
          },
        },
        cloudIsNewer: false,
      );
      final history = merged['history'] as Map;
      expect(history['read_one'], false);
      expect(history['reading_metric_one'], {
        'changedAt': '2026-11-25T15:00:00Z',
      });
    },
  );

  testWidgets('monthly preview renders both export proportions on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderMetricsSection(
              metrics: ReaderMetrics(
                chapters: 3,
                minutes: 10,
                library: 1,
                favorites: 1,
                reading: 1,
                completed: 0,
                monthlyChapters: 3,
                monthlyMinutes: 10,
                streak: 2,
                top: [],
                genres: ['Aventura'],
              ),
              profile: UserProfile(name: 'Leitora', blobatarShape: 'cloud'),
              accent: Colors.purple,
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Compartilhar Resumo Mensal'));
    await tester.tap(find.text('Compartilhar Resumo Mensal'));
    await tester.pumpAndSettle();
    final card = find.descendant(
      of: find.byType(FittedBox),
      matching: find.byWidgetPredicate(
        (widget) => widget is RepaintBoundary && widget.key is GlobalKey,
      ),
    );
    Future<void> check(Size size) async {
      expect(tester.getSize(card), size);
      final result = await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(card);
        final image = await boundary.toImage(pixelRatio: 3);
        try {
          return Size(image.width.toDouble(), image.height.toDouble());
        } finally {
          image.dispose();
        }
      });
      expect(result, size * 3);
    }

    await check(const Size(360, 640));
    await tester.tap(find.text('Feed 1:1'));
    await tester.pumpAndSettle();
    await check(const Size(360, 360));
    expect(tester.takeException(), isNull);
  });

  test(
    'combines dated, legacy and undone readings over 30 local days',
    () async {
      final directory = await Directory.systemTemp.createTemp('yomi-metrics');
      Hive.init(directory.path);
      final history = await Hive.openBox('test_metrics');
      addTearDown(() async {
        await history.close();
        await directory.delete(recursive: true);
      });
      final now = DateTime(2026, 11, 25, 15);
      final title = Manga.fromMap({
        'id': 'work',
        'title': 'Obra',
        'tags': ['Ação'],
        'availableChaptersCount': 3,
      });
      Map<String, Object> event(DateTime date, String number) => {
        'mangaId': title.id,
        'readAt': date.toIso8601String(),
        'changedAt': date.toIso8601String(),
        'pages': 30,
        'number': number,
      };
      await history.putAll({
        'manga_meta_work': title.toMap(),
        'reading_metric_one': event(now, '1'),
        'reading_metric_two': event(DateTime(2026, 11, 24, 12), '2'),
        'reading_metric_old': event(DateTime(2026, 10, 26, 12), '3'),
        'reading_metric_undo': {'changedAt': now.toIso8601String()},
        'read_undo': true,
        'read_legacy': true,
      });
      final result = ReaderMetrics.calculate(
        history,
        [title],
        [],
        allowAdult: false,
        clock: now,
      );
      expect(result.chapters, 4);
      expect(result.minutes, 35);
      expect(result.monthlyChapters, 2);
      expect(result.monthlyMinutes, 20);
      expect(result.streak, 2);
      expect(result.library, 1);
      expect(result.completed, 1);
      expect(result.top.single.value, 2);
      expect(result.genres, ['Ação']);
    },
  );
}
