import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/services/scroll_chrome_controller.dart';
import 'package:kuro_reader/widgets/scroll_chrome_bar.dart';

void main() {
  testWidgets(
    'chrome ignores jumpTo, hides on reading down and returns on reverse scroll',
    (tester) async {
      final chrome = ScrollChromeController();
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollNotification>(
              onNotification: chrome.onScroll,
              child: ListView.builder(
                controller: scroll,
                itemCount: 80,
                itemBuilder: (_, i) =>
                    SizedBox(height: 60, child: Text('Item $i')),
              ),
            ),
            bottomNavigationBar: ListenableBuilder(
              listenable: chrome,
              builder: (_, _) => ScrollChromeBar(
                visible: chrome.visible,
                child: const SizedBox(
                  height: 80,
                  child: Center(child: Text('Navigation')),
                ),
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      expect(chrome.visible, isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(chrome.visible, isFalse);
      expect(find.text('Navigation').hitTestable(), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(chrome.visible, isTrue);
      expect(find.text('Navigation').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      chrome.dispose();
      scroll.dispose();
    },
  );

  testWidgets('horizontal carousels never collapse vertical navigation', (
    tester,
  ) async {
    final chrome = ScrollChromeController();
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationListener<ScrollNotification>(
          onNotification: chrome.onScroll,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(width: 160, child: Text('$i')),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(chrome.visible, isTrue);
    await tester.pumpWidget(const SizedBox());
    chrome.dispose();
  });

  testWidgets('reduced motion removes the hidden bar immediately', (
    tester,
  ) async {
    var visible = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return Scaffold(
              bottomNavigationBar: ScrollChromeBar(
                visible: visible,
                child: const SizedBox(height: 80, child: Text('Navigation')),
              ),
            );
          },
        ),
      ),
    );
    update(() => visible = false);
    await tester.pump();
    expect(tester.getSize(find.byType(ScrollChromeBar)).height, 0);
    expect(find.text('Navigation').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
