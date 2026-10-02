import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/widgets/sko_scroll_chrome.dart';

void main() {
  setUp(() {
    SkoScrollChromeController.visible.value = true;
  });

  testWidgets('vertical scroll hides and restores app bar theme globally',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SkoGlobalScrollChrome(
          child: Scaffold(
            appBar: AppBar(title: const Text('確認')),
            body: ListView.builder(
              itemCount: 50,
              itemBuilder: (_, index) => SizedBox(
                height: 60,
                child: Text('row $index'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(SkoScrollChromeController.visible.value, isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pump();

    expect(SkoScrollChromeController.visible.value, isFalse);
    final hiddenContext = tester.element(find.byType(AppBar));
    expect(Theme.of(hiddenContext).appBarTheme.toolbarHeight, 0);

    await tester.drag(find.byType(ListView), const Offset(0, 180));
    await tester.pump();

    expect(SkoScrollChromeController.visible.value, isTrue);
    final visibleContext = tester.element(find.byType(AppBar));
    expect(
      Theme.of(visibleContext).appBarTheme.toolbarHeight,
      kToolbarHeight,
    );
  });
}
