import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

const fitHelp = 'A4を画面幅に合わせて表示します。プレビュー上で拡大・縮小できます。';
const saveHelp = 'iPhoneでは共有メニューの「ファイルに保存」でPDFを保存できます。';
const stampHelp = '承認印の名字未設定・未確認：既存の印影を保持しています。設定が利用可能な場合は、新しい承認前に本人の名字を入力してください。';

Future<void> showGuidance(WidgetTester tester, {bool surname = false, double textScale = 1}) =>
    tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: Column(children: [
        InvoicePreviewGuidance(needsStampSurname: surname),
        const Expanded(child: SizedBox(key: ValueKey('document-viewport'))),
      ])),
    )));

void main() {
  setUp(() => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'));
  tearDown(() => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'));

  testWidgets('instructions start collapsed and return document space when closed', (tester) async {
    await showGuidance(tester, surname: true);
    expect(find.text('表示・保存の案内'), findsOneWidget);
    expect(find.text(fitHelp), findsNothing);
    expect(find.text(saveHelp), findsNothing);
    expect(find.text(stampHelp), findsNothing);
    final collapsedHeight = tester.getSize(find.byKey(const ValueKey('document-viewport'))).height;
    await tester.tap(find.text('表示・保存の案内'));
    await tester.pumpAndSettle();
    expect(find.text(fitHelp), findsOneWidget);
    expect(find.text(saveHelp), findsOneWidget);
    expect(find.text(stampHelp), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('document-viewport'))).height,
        lessThan(collapsedHeight));
    await tester.tap(find.text('表示・保存の案内'));
    await tester.pumpAndSettle();
    expect(find.text(fitHelp), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('document-viewport'))).height, collapsedHeight);
  });

  testWidgets('configured approvals do not show an unconfigured surname warning', (tester) async {
    await showGuidance(tester);
    await tester.tap(find.text('表示・保存の案内'));
    await tester.pumpAndSettle();
    expect(find.text(fitHelp), findsOneWidget);
    expect(find.text(saveHelp), findsOneWidget);
    expect(find.text(stampHelp), findsNothing);
  });

  testWidgets('expanded instructions scroll within a bound on a small screen with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await showGuidance(tester, surname: true, textScale: 2);
    await tester.tap(find.text('表示・保存の案内'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scroll = find.descendant(of: find.byType(InvoicePreviewGuidance),
        matching: find.byType(SingleChildScrollView));
    expect(tester.getSize(scroll).height, lessThanOrEqualTo(160));
    await tester.drag(scroll, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text(saveHelp).hitTestable(), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('document-viewport'))).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('English guidance uses the same collapsed interaction', (tester) async {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    await showGuidance(tester, surname: true);
    expect(find.text('Display and save help'), findsOneWidget);
    expect(find.text(fitHelp), findsNothing);
    await tester.tap(find.text('Display and save help'));
    await tester.pumpAndSettle();
    expect(find.text('The A4 page fits the screen width. Pinch the preview to zoom in or out.'), findsOneWidget);
    expect(find.text(stampHelp), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
