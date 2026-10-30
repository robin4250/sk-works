import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_compact_controls.dart';
import 'package:sk_works/branding/sko_theme.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('site controls share compact accessible phone height at $scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      var mapped = 0;
      var selected = false;
      await tester.pumpWidget(MaterialApp(theme: SkoTheme.light(SkoTheme.palettes.first), home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: Builder(builder: (context) {
          final height = siteControlHeight(context);
          return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            SiteCompactFilter(height: height, label: const Text('準備中'),
              selected: false, onSelected: (_) => selected = true),
            SiteCompactCard(height: height, name: '江戸川', details: '株式会社秀中 / 進行中',
              onTap: () => opened++),
            Row(children: [
              Expanded(child: SiteCompactAction(height: height, controlKey: 'map',
                icon: const Icon(Icons.map_outlined), label: const Text('現場マップ'),
                onPressed: () => mapped++)),
              const SizedBox(width: 12),
              Expanded(child: SiteCompactAction(height: height, controlKey: 'register',
                icon: const Icon(Icons.add_business), label: const Text('現場登録'), onPressed: null)),
            ]),
          ]));
        })),
      )));
      await tester.pumpAndSettle();
      final height = tester.getSize(find.byType(SiteCompactCard)).height;
      expect(height, greaterThanOrEqualTo(48));
      if (scale == 1) expect(height, 48);
      expect(tester.getSize(find.byType(SiteCompactFilter)).height, height);
      expect(tester.getSize(find.byKey(const ValueKey('map'))).height, height);
      expect(tester.getSize(find.byKey(const ValueKey('register'))).height, height);
      await tester.tap(find.text('江戸川'));
      await tester.tap(find.text('準備中'));
      await tester.tap(find.text('現場マップ'));
      await tester.tap(find.text('現場登録'));
      expect(opened, 1);
      expect(mapped, 1);
      expect(selected, isTrue);
      expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed, isNull);
      expect(find.text('株式会社秀中 / 進行中'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
