import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';
import 'package:sk_works/features/daily_reports/signature_entry_frame.dart';

void main() {
  for (final role in ['報告者', '責任者']) {
    for (final size in [const Size(320, 568), const Size(844, 390), const Size(926, 428)]) {
      testWidgets('$role $size has a non-drawing entry and one-tap fullscreen return', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        SignatureResult? saved;
        await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: ListTile(
            subtitle: SignatureEntryFrame(role: role, signerName: '試験記入者'),
            onTap: () async {
              saved = await Navigator.of(context).push<SignatureResult>(
                MaterialPageRoute(fullscreenDialog: true, builder: (_) =>
                  SignatureCapturePage(title: '$roleサイン', initialSignerName: '試験記入者',
                    submitLabel: '確定')));
            },
          ),
        ))));
        expect(find.byKey(const ValueKey('signature-drawing-surface')), findsNothing);
        expect(find.text('$role：試験記入者'), findsOneWidget);
        expect(t.widget<RotatedBox>(find.byKey(const ValueKey('signature-entry-turn-guide'))).quarterTurns,
          size.width < size.height ? 1 : 0);
        await t.tap(find.text('横向きでサインしてください'));
        await t.pumpAndSettle();
        t.view.physicalSize = size.width > size.height ? size : const Size(844, 390);
        await t.pumpAndSettle();
        expect(find.byType(SignatureOrientationGuide), findsNothing);
        final surface = find.byKey(const ValueKey('signature-drawing-surface'));
        expect(surface, findsOneWidget);
        final confirm = find.byKey(const ValueKey('signature-confirm-corner'));
        void expectConfirmBesideFrame() {
          final frame = t.getRect(surface);
          final button = t.getRect(confirm);
          final rail = t.getRect(find.byKey(const ValueKey('signature-confirm-rail')));
          expect(button.left, greaterThanOrEqualTo(frame.right + 12));
          expect(button.left, greaterThanOrEqualTo(rail.left));
          expect(button.right, lessThanOrEqualTo(rail.right));
          expect(button.top, greaterThanOrEqualTo(rail.top));
          expect(button.bottom, lessThanOrEqualTo(rail.bottom));
          expect(button.overlaps(frame), isFalse);
          expect(confirm.hitTestable(), findsOneWidget);
          expect(find.descendant(of: find.byType(AppBar), matching: confirm), findsNothing);
        }
        expectConfirmBesideFrame();
        await t.dragFrom(t.getCenter(surface), const Offset(60, 20));
        await t.pump();
        expectConfirmBesideFrame();
        expect(find.descendant(of: confirm, matching: find.text('確定')), findsOneWidget);
        await t.tap(confirm);
        await t.pumpAndSettle();
        expect(find.byType(SignatureCapturePage), findsNothing);
        expect(find.byType(SignatureEntryFrame), findsOneWidget);
        expect(saved?.signerName, '試験記入者');
        expect(saved?.strokes, isNotEmpty);
        expect(saved!.canvasSize!.width, greaterThan(saved!.canvasSize!.height));
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final role in ['報告者', '責任者']) {
    testWidgets('$role iPhone safe area and keyboard keep confirmation beside ink', (t) async {
      t.view.physicalSize = const Size(926, 428);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      SignatureResult? saved;
      await t.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.fromLTRB(44, 0, 44, 21),
            viewPadding: const EdgeInsets.fromLTRB(44, 0, 44, 21),
            textScaler: TextScaler.linear(1.6)), child: child!),
        home: Builder(builder: (context) => Scaffold(body: TextButton(
          onPressed: () async {
            saved = await Navigator.of(context).push<SignatureResult>(MaterialPageRoute(
              fullscreenDialog: true, builder: (_) => SignatureCapturePage(
                title: '$roleサイン', initialSignerName: '記入者',
                signerNameOptions: const ['記入者'], submitLabel: '確定')));
          }, child: const Text('サインを開く')))),
      ));
      await t.tap(find.text('サインを開く')); await t.pumpAndSettle();
      final surface = find.byKey(const ValueKey('signature-drawing-surface'));
      final confirm = find.byKey(const ValueKey('signature-confirm-corner'));
      expect(t.getRect(surface).width, greaterThan(600));
      await t.dragFrom(t.getCenter(surface), const Offset(70, 15)); await t.pump();
      final rightBefore = t.getRect(confirm).right;
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      await t.pumpAndSettle();
      final button = t.getRect(confirm), frame = t.getRect(surface);
      final rail = t.getRect(find.byKey(const ValueKey('signature-confirm-rail')));
      expect(button.left, greaterThanOrEqualTo(frame.right + 12));
      expect(button.right, closeTo(rightBefore, .1));
      expect(button.right, lessThanOrEqualTo(926 - 44 - 16));
      expect(button.top, greaterThanOrEqualTo(rail.top));
      expect(button.bottom, lessThanOrEqualTo(rail.bottom));
      expect(confirm.hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(confirm); await t.pumpAndSettle();
      expect(saved?.signerName, '記入者'); expect(saved?.strokes, isNotEmpty);
      expect(find.byType(SignatureCapturePage), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('large text keeps rotated entry guidance inside a small frame', (t) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)),
      child: Scaffold(body: ListTile(
        subtitle: SignatureEntryFrame(role: '責任者', signerName: '試験記入者'),
      )),
    )));
    expect(find.text('横向きでサインしてください'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
