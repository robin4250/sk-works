import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
// Pin-compatible fake for the native raster boundary, not a real PDF renderer.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/domain/company_seal_design.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/features/shared/trade_document_touch_editor_page.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'trade_document_touch_editor_test.dart' as fixture;

class _Printing extends PrintingPlatform {
  int rasterCalls = 0;
  Uint8List? pdf;
  Completer<PdfRaster>? pending;
  bool fail = false;
  @override Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) async* {
    rasterCalls++;
    pdf = document;
    if (fail) throw StateError('native raster unavailable');
    yield pending == null ? _pixel() : await pending!.future;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
PdfRaster _pixel() => PdfRaster(1, 1, Uint8List.fromList([255, 0, 0, 255]));
Future<void> _wait(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 200 && !condition(); index++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!condition()) {
    final status = find.byKey(const Key('trade-input-seal-status'));
    debugPrint('seal-preview wait status: ${status.evaluate().isEmpty ? 'no status' : tester.widget<Text>(status).data}');
  }
  expect(condition(), isTrue);
}
Finder get seal => find.byKey(const Key('trade-input-own-seal'));
Map<String, dynamic> _payload({bool order = true, bool enabled = true}) {
  final value = fixture.body();
  value['kind'] = order ? 'order' : 'acceptance';
  value['acceptance_text'] = '乙は、{order_date}付の注文書の条件で請け負います。';
  value['company_seal_enabled'] = enabled;
  return value;
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Warm the existing static asset futures outside individual widget FakeAsync
  // zones, so one completed test cannot leave another waiting in its old zone.
  setUpAll(() async {
    await CompanySealPdf.loadFont();
    await CompanySealPdf.loadStyleFont('png_sumida_v1_standard');
  });
  late PrintingPlatform original;
  late _Printing printing;
  setUp(() { original = PrintingPlatform.instance; printing = _Printing(); PrintingPlatform.instance = printing; });
  tearDown(() { PrintingPlatform.instance = original; });
  for (final order in [true, false]) {
    testWidgets('saved issuer seal appears on ${order ? 'order' : 'acceptance'} input without losing company tap', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
      final value = _payload(order: order);
      final before = value['company_seal_snapshot'].toString();
      await fixture.mount(tester, payload: value);
      await _wait(tester, () => seal.evaluate().isNotEmpty);
      final nameBox = tester.getRect(find.byKey(const Key('trade-input-issuer-name')));
      final sealBox = tester.getRect(find.byKey(const Key('trade-input-seal-position')));
      expect(sealBox.left, lessThan(nameBox.right));
      expect(sealBox.right, greaterThan(nameBox.right));
      expect((sealBox.center.dx - nameBox.right).abs(), lessThan(1));
      expect((sealBox.center.dy - nameBox.center.dy).abs(), lessThan(1));
      expect(printing.rasterCalls, 1);
      expect(String.fromCharCodes(printing.pdf!.take(5)), '%PDF-');
      expect(value['company_seal_snapshot'].toString(), before);
      expect(find.bySemanticsLabel('自社登録角印のプレビュー・相手の承認印ではありません'), findsOneWidget);
      await tester.tap(fixture.target('issuer')); await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('自社の登録住所')), findsOneWidget);
      expect(tester.takeException(), isNull);
      } finally { semantics.dispose(); }
    });
  }
  testWidgets('large company text on narrow portrait keeps seal preview and company detail tap usable', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.devicePixelRatio = 1; tester.view.physicalSize = const Size(428, 926);
    addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
    final value = _payload();
    final name = List.filled(16, '長').join();
    value['issuer']['name'] = name;
    value['company_seal_snapshot'] = {'version': 1, 'style': 'legacy', 'name': name};
    final scope = fixture.Scope();
    final draft = TradeDocumentFormDraft.fromPayload(value, allowAmountEditing: true);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(428, 926), textScaler: TextScaler.linear(2)),
      child: TradeDocumentTouchEditorPage(initial: draft, canEdit: true,
        requireScope: scope.check, scopeChanges: scope,
        buildPreview: (_) async => Uint8List(0), onSave: (_) async {}))));
    await _wait(tester, () => seal.evaluate().isNotEmpty);
    await tester.tap(fixture.target('issuer')); await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(name)), findsOneWidget);
    expect(tester.takeException(), isNull);
    final close = find.byKey(const Key('trade-touch-company-close'));
    expect(tester.getBottomRight(close).dy, lessThanOrEqualTo(926));
    await tester.tap(close); await tester.pumpAndSettle();
    expect(seal, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); scope.dispose();
  });
  testWidgets('OFF and missing old metadata never invent an issuer stamp', (tester) async {
    await fixture.mount(tester, payload: _payload(enabled: false));
    expect(seal, findsNothing); expect(printing.rasterCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    final value = _payload()..remove('company_seal_snapshot');
    await fixture.mount(tester, payload: value);
    await tester.pumpAndSettle();
    expect(seal, findsNothing); expect(printing.rasterCalls, 0);
    expect(find.text('角印を確認できません'), findsOneWidget);
  });
  testWidgets('mismatched saved company seal is not replaced by current issuer or partner name', (tester) async {
    final value = _payload();
    value['company_seal_snapshot'] = {'version': 1, 'style': 'legacy', 'name': '別会社'};
    await fixture.mount(tester, payload: value); await tester.pumpAndSettle();
    expect(seal, findsNothing); expect(printing.rasterCalls, 0);
    expect(find.text('角印を確認できません'), findsOneWidget);
    expect(value['company_seal_snapshot']['name'], '別会社');
  });
  testWidgets('approved PNG style goes through the same hash-checked PDF component', (tester) async {
    final value = _payload();
    value['issuer']['name'] = CompanySealDesign.companyName;
    value['company_seal_snapshot'] = {'version': 1, 'style': 'png_sumida_v1_standard',
      'name': CompanySealDesign.companyName, 'company_id': CompanySealDesign.companyId};
    await fixture.mount(tester, payload: value);
    await _wait(tester, () => seal.evaluate().isNotEmpty);
    expect(printing.rasterCalls, 1);
    expect(RegExp(r'/Subtype\s*/Image\b').hasMatch(String.fromCharCodes(printing.pdf!)), isTrue,
      reason: 'The actual seal PDF must retain an image XObject');
  });
  testWidgets('uploaded PNG remains bound to its stored company and hash', (tester) async {
    const png = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALUlEQVR4nO3OIQEAAAwEoetf+hdjBoWlVat9mYCAgICAgICAgICAgICAwHfgAIP/+kx2iamjAAAAAElFTkSuQmCC';
    final value = _payload();
    value['company_seal_snapshot'] = {'version': 2, 'style': 'uploaded_png', 'name': '登録自社',
      'company_id': '00000000-0000-0000-0000-000000000001',
      'png_version_id': '00000000-0000-0000-0000-000000000002', 'png_base64': png,
      'png_sha256': '30ca1a5ef40b92ff14e0d5f9b4a2a9930ae2013a6cd9d7c4b636e3e70daa58fc'};
    await fixture.mount(tester, payload: value);
    await _wait(tester, () => seal.evaluate().isNotEmpty);
    expect(RegExp(r'/Subtype\s*/Image\b').hasMatch(String.fromCharCodes(printing.pdf!)), isTrue,
      reason: 'The actual seal PDF must retain an image XObject');
    expect(value['company_seal_snapshot']['png_base64'], png);
  });
  testWidgets('failed native seal preview shows unavailable rather than a synthetic stamp', (tester) async {
    printing.fail = true;
    await fixture.mount(tester, payload: _payload());
    await _wait(tester, () => find.text('角印を確認できません').evaluate().isNotEmpty);
    expect(seal, findsNothing);
    await tester.tap(fixture.target('issuer')); await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('自社の登録住所')), findsOneWidget);
  });
  testWidgets('scope retirement during native raster wait cannot publish retained stamp bytes', (tester) async {
    printing.pending = Completer<PdfRaster>();
    final h = await fixture.mount(tester, payload: _payload());
    await _wait(tester, () => printing.rasterCalls == 1);
    h.scope.revoke(); await tester.pump();
    printing.pending!.complete(_pixel());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(seal, findsNothing); expect(find.textContaining('入力を停止'), findsOneWidget);
    h.scope.restore(); await tester.pumpAndSettle();
    expect(seal, findsNothing); expect(h.saves, isEmpty);
  });
  testWidgets('changing the draft snapshot in the same editor State permanently retires pending seal output', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    printing.pending = Completer<PdfRaster>();
    final scope = fixture.Scope();
    final initial = ValueNotifier(TradeDocumentFormDraft.fromPayload(_payload(), allowAmountEditing: true));
    await tester.pumpWidget(MaterialApp(home: ValueListenableBuilder<TradeDocumentFormDraft>(
      valueListenable: initial, builder: (_, draft, _) => TradeDocumentTouchEditorPage(
        initial: draft, canEdit: true, requireScope: scope.check, scopeChanges: scope,
        buildPreview: (_) async => Uint8List(0), onSave: (_) async {}))));
    await _wait(tester, () => printing.rasterCalls == 1);
    final changed = _payload();
    changed['company_seal_snapshot'] = {'version': 1, 'style': 'legacy', 'name': '他の保存印'};
    initial.value = TradeDocumentFormDraft.fromPayload(changed, allowAmountEditing: true);
    await tester.pump();
    printing.pending!.complete(_pixel());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(seal, findsNothing); expect(find.textContaining('入力を停止'), findsOneWidget);
    expect(printing.rasterCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    initial.dispose(); scope.dispose();
  });
  test('invalid saved uploaded hash is rejected before input or native rendering', () {
    final value = _payload();
    value['company_seal_snapshot'] = {'version': 2, 'style': 'uploaded_png', 'name': '登録自社',
      'company_id': '00000000-0000-0000-0000-000000000001',
      'png_version_id': '00000000-0000-0000-0000-000000000002', 'png_base64': 'broken',
      'png_sha256': 'wrong'};
    expect(() => TradeDocumentFormDraft.fromPayload(value, allowAmountEditing: true), throwsFormatException);
    expect(printing.rasterCalls, 0);
  });
  for (final date in ['', '2026-10-01']) {
    testWidgets('acceptance date token is display-only with ${date.isEmpty ? 'a missing-date hint' : 'the entered date'}', (tester) async {
      final value = _payload(order: false, enabled: false)..['order_date'] = date;
      await fixture.mount(tester, payload: value);
      expect(find.textContaining('{order_date}'), findsNothing);
      expect(find.textContaining(date.isEmpty ? '（注文書日を入力）' : '乙は、2026-10-01付'), findsOneWidget);
      expect(value['acceptance_text'], contains('{order_date}'));
      expect(value['order_date'], date);
    });
  }
}
