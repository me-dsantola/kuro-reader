import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/reader_page_geometry.dart';
import 'package:kuro_reader/widgets/reader_page_image.dart';
import 'package:kuro_reader/widgets/webtoon_view.dart';
import 'package:kuro_reader/widgets/reader_scroll_controller.dart';
import 'package:kuro_reader/widgets/reader_paged_view.dart';

class _DelayedImage extends ImageProvider<_DelayedImage> {
  final ready = Completer<ui.Image>();
  int loads = 0;
  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _DelayedImage key,
    ImageDecoderCallback decode,
  ) {
    loads++;
    return OneFrameImageStreamCompleter(
      ready.future.then((image) => ImageInfo(image: image.clone())),
    );
  }
}

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFF472B6),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    ReaderPageGeometry geometry,
    ReaderScrollController controller,
    List<_DelayedImage> images, {
    bool offline = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebtoonView(
            geometry: geometry,
            controller: controller,
            onWidth: (_) {},
            localDimensionsKnown: offline,
            footer: const SizedBox(height: 240, child: Text('Fim do capítulo')),
            pageBuilder: (_, index, onRatio) => ReaderPageImage(
              key: ValueKey(index),
              image: images[index],
              pageNumber: index + 1,
              onRatio: onRatio,
              onRetry: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(
    WidgetTester tester,
    ReaderScrollController controller,
  ) async {
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    controller.dispose();
  }

  testWidgets(
    'offline pages retain scroll extent during delayed decode and recycling',
    (tester) async {
      final images = List.generate(24, (_) => _DelayedImage());
      final geometry = ReaderPageGeometry(24)
        ..updateRatios({for (var i = 0; i < 24; i++) i: 0.5}, 360, 0);
      final controller = ReaderScrollController();
      await mount(tester, geometry, controller, images, offline: true);
      final extent = controller.position.maxScrollExtent;
      for (final offset in [2000.0, 10000.0, 4000.0, 0.0]) {
        controller.jumpTo(offset);
        await tester.pump();
        expect(controller.offset, offset);
        expect(controller.position.maxScrollExtent, extent);
      }
      final image = _image(16, 32);
      for (final provider in images) {
        provider.ready.complete(image);
      }
      await tester.pump();
      await tester.pump();
      controller.jumpTo(9000);
      await tester.pump();
      controller.jumpTo(0);
      await tester.pump();
      expect(controller.offset, 0);
      expect(controller.position.maxScrollExtent, extent);
      expect(images.first.loads, 1);
      expect(tester.takeException(), isNull);
      await unmount(tester, controller);
      image.dispose();
    },
  );

  testWidgets(
    'online decode corrects height while preserving the current anchor',
    (tester) async {
      final images = List.generate(12, (_) => _DelayedImage());
      final geometry = ReaderPageGeometry(12);
      final controller = ReaderScrollController();
      await mount(tester, geometry, controller, images);
      controller.jumpTo(900);
      await tester.pump();
      final page = geometry.pageAt(controller.offset, 360);
      final fraction =
          (controller.offset - geometry.offsetOf(page, 360)) /
          geometry.extentAt(page, 360);
      final image = _image(16, 64);
      images.first.ready.complete(image);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(geometry.hasRatio(0), isTrue);
      expect(geometry.pageAt(controller.offset, 360), page);
      final actual =
          (controller.offset - geometry.offsetOf(page, 360)) /
          geometry.extentAt(page, 360);
      expect(actual, closeTo(fraction, 0.001));
      expect(tester.takeException(), isNull);
      await unmount(tester, controller);
      image.dispose();
    },
  );

  testWidgets(
    'late image size does not paint an intervening frame on another page',
    (tester) async {
      final images = List.generate(12, (_) => _DelayedImage());
      final geometry = ReaderPageGeometry(12);
      final controller = ReaderScrollController();
      await mount(tester, geometry, controller, images);
      controller.jumpTo(900);
      await tester.pump();
      final visiblePage = find.byKey(const ValueKey(1));
      final before = tester.getTopLeft(visiblePage).dy;
      final image = _image(16, 64);
      images.first.ready.complete(image);
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump();
        expect(
          tester.getTopLeft(visiblePage).dy,
          closeTo(before, 0.01),
          reason:
              'A late dimension must not flash a different reading position on frame $frame',
        );
      }
      await unmount(tester, controller);
      image.dispose();
    },
  );

  testWidgets(
    'viewport resize preserves the reading page and within-page position',
    (tester) async {
      final images = List.generate(12, (_) => _DelayedImage());
      final geometry = ReaderPageGeometry(12)
        ..updateRatios({for (var i = 0; i < 12; i++) i: 0.5}, 360, 0);
      final controller = ReaderScrollController();
      await mount(tester, geometry, controller, images, offline: true);
      controller.jumpTo(1800); // Middle of page 3 at 360 logical pixels wide.
      await tester.pump();
      tester.view.physicalSize = const Size(640, 480);
      await tester.pump();
      expect(geometry.pageAt(controller.offset, 640), 2);
      expect(controller.offset - geometry.offsetOf(2, 640), closeTo(640, 0.01));
      await unmount(tester, controller);
    },
  );

  testWidgets(
    'returning from paged mode opens the requested page on its first frame',
    (tester) async {
      final controller = ReaderScrollController(initialScrollOffset: 0);
      final images = List.generate(12, (_) => _DelayedImage());
      final geometry = ReaderPageGeometry(12)
        ..updateRatios({for (var i = 0; i < 12; i++) i: 0.5}, 360, 0);
      await mount(tester, geometry, controller, images, offline: true);
      controller.jumpTo(720);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      controller.correctLayoutOffset(geometry.offsetOf(7, 360));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebtoonView(
              geometry: geometry,
              controller: controller,
              onWidth: (_) {},
              localDimensionsKnown: true,
              footer: const SizedBox(height: 240),
              pageBuilder: (_, index, onRatio) => ReaderPageImage(
                key: ValueKey(index),
                image: images[index],
                pageNumber: index + 1,
                onRatio: onRatio,
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      expect(controller.offset, 5040);
      expect(geometry.pageAt(controller.offset, 360), 7);
      await unmount(tester, controller);
    },
  );

  testWidgets(
    'a decoded page gets its real height while a drag is still active',
    (tester) async {
      final images = List.generate(12, (_) => _DelayedImage());
      final geometry = ReaderPageGeometry(12);
      final controller = ReaderScrollController();
      await mount(tester, geometry, controller, images);
      final gesture = await tester.startGesture(const Offset(180, 400));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(controller.position.isScrollingNotifier.value, isTrue);
      final image = _image(16, 64);
      images.first.ready.complete(image);
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump();
      }
      expect(controller.position.isScrollingNotifier.value, isTrue);
      expect(geometry.ratioAt(0), 0.25);
      expect(tester.getSize(find.byKey(const ValueKey(0))).height, 1440);
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await unmount(tester, controller);
      image.dispose();
    },
  );

  testWidgets('paged reader offers retry and recovers a failed image', (
    tester,
  ) async {
    final failed = _DelayedImage();
    final recovered = _DelayedImage();
    final controller = PageController();
    var retry = false;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setLocalState) => ReaderPagedView(
              controller: controller,
              pageCount: 1,
              imageForPage: (_) => retry ? recovered : failed,
              onPageChanged: (_) {},
              onRetry: (_) => setLocalState(() => retry = true),
              onToggleHud: () => taps++,
            ),
          ),
        ),
      ),
    );
    failed.ready.completeError(StateError('temporary network error'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Página 1 indisponível'), findsOneWidget);
    await tester.tap(find.byTooltip('Tentar carregar a página 1 novamente'));
    await tester.pump();
    final image = _image(16, 32);
    recovered.ready.complete(image);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(find.text('Página 1 indisponível'), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    await tester.tap(find.byType(RawImage));
    await tester.pump(const Duration(milliseconds: 350));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    image.dispose();
  });

  testWidgets('a failed image keeps its reserved height and provides retry', (
    tester,
  ) async {
    final provider = _DelayedImage();
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 720,
            child: ReaderPageImage(
              image: provider,
              pageNumber: 1,
              onRatio: (_) {},
              onRetry: () => retries++,
            ),
          ),
        ),
      ),
    );
    final before = tester.getSize(find.byType(ReaderPageImage));
    provider.ready.completeError(StateError('network unavailable'));
    await tester.pump();
    expect(tester.getSize(find.byType(ReaderPageImage)), before);
    await tester.tap(find.byTooltip('Tentar carregar a página 1 novamente'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
  });
}
