import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';
import 'package:sk_works/widgets/sko_orientation_policy.dart';

void main() {
  Finder getSurface() => find.byKey(const ValueKey('signature-drawing-surface'));
  Future<void> landscape(WidgetTester tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  Future<void> route(WidgetTester tester, void Function(SignatureResult?) completed,
      {String name = '本人が入力した氏名'}) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: Column(children: [const Text('元の日報画面'), TextButton(onPressed: () async {
        final result = await Navigator.of(context).push<SignatureResult>(MaterialPageRoute(
          builder: (_) => SignatureCapturePage(initialSignerName: name)));
        completed(result);
      }, child: const Text('サインを開く'))]),
    ))));
    await tester.tap(find.text('サインを開く'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirm returns genuine strokes and requests normal iPhone portrait policy', (tester) async {
    await landscape(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
    tester.view.display.size = const Size(1170, 2532);
    tester.view.display.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(2532, 1170);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.display.resetSize);
    addTearDown(tester.view.display.resetDevicePixelRatio);
    final requests = <List<dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        requests.add(List<dynamic>.from(call.arguments as List));
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await SkoOrientationPolicy.initialize(tester.view);
    SignatureResult? actual;
    await route(tester, (result) { actual = result; });
    await tester.dragFrom(tester.getCenter(getSurface()), const Offset(70, 15));
    await tester.pump();
    await tester.tap(find.text('サインを確定'));
    await tester.pumpAndSettle();
    expect(find.text('元の日報画面'), findsOneWidget);
    expect(actual?.signerName, '本人が入力した氏名');
    expect(actual?.strokes, isNotEmpty);
    expect(actual!.canvasSize!.width, greaterThan(actual!.canvasSize!.height));
    expect(requests.last, ['DeviceOrientation.portraitUp']);
    expect(requests.any((r) => r.contains('DeviceOrientation.landscapeLeft') &&
      r.contains('DeviceOrientation.landscapeRight') &&
      !r.contains('DeviceOrientation.portraitUp')), isTrue);
    expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await SkoOrientationPolicy.initialize(tester.view);
    }
  });

  testWidgets('cancel returns null and leaves the original screen', (tester) async {
    await landscape(tester);
    var completed = false;
    SignatureResult? actual;
    await route(tester, (result) { completed = true; actual = result; });
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(actual, isNull);
    expect(find.text('元の日報画面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty name or missing ink cannot confirm or pop', (tester) async {
    await landscape(tester);
    var completed = false;
    await route(tester, (_) { completed = true; }, name: '');
    await tester.tap(find.text('サインを確定'));
    await tester.pump();
    expect(find.text('現場責任者名を入力してください'), findsOneWidget);
    expect(completed, isFalse);
    // Let the first independent validation message finish before the next one.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '責任者本人');
    await tester.tap(find.text('サインを確定'));
    await tester.pump();
    expect(find.text('サインを入力してください'), findsOneWidget);
    expect(find.byType(SignatureCapturePage), findsOneWidget);
    expect(completed, isFalse);
  });

  testWidgets('portrait after drawing disables confirmation until landscape resumes', (tester) async {
    await landscape(tester);
    var completed = false;
    await route(tester, (_) { completed = true; });
    await tester.dragFrom(tester.getCenter(getSurface()), const Offset(70, 15));
    await tester.pump();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'サインを確定');
    expect(confirm, findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(getSurface(), findsNothing);
    expect(completed, isFalse);
    expect(find.byType(SignatureOrientationGuide), findsOneWidget);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(find.text('元の日報画面'), findsOneWidget);
  });
}
