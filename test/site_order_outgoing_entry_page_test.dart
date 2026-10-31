import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
// Pin-compatible native-raster fixture, not a visual or OS-rendering proof.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_touch_editor_page.dart';
import 'package:sk_works/features/sites/site_order_outgoing_entries.dart';
import 'package:sk_works/features/sites/site_order_outgoing_body_factory.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';
import 'package:sk_works/features/sites/site_order_outgoing_entry_page.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';

class _InputSealPrinting extends PrintingPlatform {
  int rasterCalls = 0;
  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) async* {
    rasterCalls++;
    expect(String.fromCharCodes(document.take(5)), '%PDF-');
    yield PdfRaster(1, 1, Uint8List.fromList([255, 0, 0, 255]));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Future<void> _waitForInputSeal(WidgetTester tester) async {
  final seal = find.byKey(const Key('trade-input-own-seal'));
  for (var index = 0; index < 200 && seal.evaluate().isEmpty; index++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(seal, findsOneWidget);
}

String _id(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
Map<String, String> _input() => {
  'work_name': '合成工事',
  'work_address': '合成現場住所',
  'period_start': '2026-10-01',
  'period_end': '2026-10-31',
  'unit_price': '100',
  'quantity': '1',
  'unit': '人日',
  'total_amount_yen': '120',
  'tax_amount_yen': '20',
};

class _Api extends SiteOrderWorkflowApi {
  bool expired = false;
  bool admitted = false;
  int contexts = 0;
  int targetReads = 0;
  bool targetReadUnknown = false;
  Completer<void>? contextBarrier;
  @override
  bool get invalidated => expired;
  @override
  void requireCurrent() {
    if (expired || !admitted) throw StateError('expired or not admitted');
  }

  @override
  Future<void> verify() async {
    if (expired) throw StateError('expired');
    admitted = true;
    requireCurrent();
  }

  @override
  Future<List<SiteOrderRegisteredTarget>> registeredOutgoingTargets(
    String siteId,
  ) async {
    requireCurrent();
    targetReads++;
    if (targetReadUnknown) throw StateError('synthetic target result unknown');
    expect(siteId, _id(3));
    return [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')];
  }

  @override
  Future<Map<String, dynamic>> outgoingContext(
    String siteId,
    String tradeId,
  ) async {
    requireCurrent();
    contexts++;
    await contextBarrier?.future;
    expect(siteId, _id(3));
    expect(tradeId, _id(7));
    return {
      'contract_version': 1,
      'actor_id': _id(1),
      'session_id': _id(4),
      'company_id': _id(2),
      'site_id': siteId,
      'trade_company_id': tradeId,
      'counterparty_company_id': _id(9),
      'connection_fingerprint': 'a' * 64,
      'creates_document': false,
      'records_consent': false,
      'can_send': false,
      'issuer': {
        'name': '合成甲会社',
        'address': '合成甲住所',
        'representative_name': '甲代表',
        'corporate_number': '',
        'phone': '000',
        'fax': '001',
      },
      'counterparty': {
        'name': '正式な合成乙会社',
        'address': '合成乙住所',
        'representative_name': '乙代表',
        'corporate_number': '',
        'phone': '002',
      },
      'site': {
        'name': '合成工事',
        'address': '合成現場住所',
        'period_start': '2026-10-01',
        'period_end': '2026-10-31',
      },
      'own_seal': {
        'snapshot': {'version': 1, 'style': 'legacy', 'name': '合成甲会社'},
        'seal_hash': 'b' * 64,
        'version_id': null,
        'asset_hash': null,
        'version_key': 'synthetic',
        'renderer_contract': 'synthetic',
      },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _inputDone(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('入力を確定'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('入力を確定'));
  await tester.pumpAndSettle();
}

Future<TextField> _inputField(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey('outgoing-input:$key'));
  await tester.scrollUntilVisible(
    finder,
    -250,
    scrollable: find.byType(Scrollable).first,
  );
  return tester.widget<TextField>(finder);
}

Future<void> _selectAndPreview(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('登録表示名').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('注文書を確認'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async { await CompanySealPdf.loadFont(); });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('RAM input requires explicit unit price total and tax; identity patch is rejected', () {
    final input = _input()..['unit_price'] = '';
    expect(
      () => SiteOrderOutgoingEntries(input).validate(),
      throwsFormatException,
    );
    expect(
      () =>
          SiteOrderOutgoingEntries({..._input(), 'company_id': _id(1)})
              .validate(),
      throwsFormatException,
    );
    expect(
      () =>
          SiteOrderOutgoingEntries(_input()..['tax_amount_yen'] = '')
              .validate(),
      throwsFormatException,
    );
    expect(SiteOrderOutgoingEntries(_input()).unitPriceLabel, '100円／人日');
  });
  testWidgets(
    'RAM input precedes target selection and final PDF confirms actual bound company without sending',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final api = _Api();
      SiteOrderReviewedInput? result;
      final rendered = <Map<String, dynamic>>[];
      final targets = [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<SiteOrderReviewedInput>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SiteOrderOutgoingEntryPage(
                      api: api,
                      siteId: _id(3),
                      issueDate: '2026-10-31',
                      targets: targets,
                      initial: _input(),
                      render: (body) async {
                        rendered.add(body);
                        return Uint8List.fromList('%PDF-synthetic'.codeUnits);
                      },
                      previewBuilder: (_) => const Text('合成PDF'),
                    ),
                  ),
                );
              },
              child: const Text('入力画面を開く'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('入力画面を開く'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(api.contexts, 0);
      await _inputDone(tester);
      expect(api.contexts, 0);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      await _selectAndPreview(tester);
      expect(api.contexts, 1);
      expect(find.text('合成PDF'), findsOneWidget);
      expect(rendered.single['counterparty']['name'], '正式な合成乙会社');
      await tester.tap(find.text('注文内容を確認'));
      await tester.pumpAndSettle();
      expect(find.textContaining('正式な合成乙会社'), findsOneWidget);
      expect(find.textContaining('100円／人日'), findsOneWidget);
      await tester.tap(find.text('内容を確認'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.pending.tradeId, _id(7));
      expect(result!.body.containsKey('company_seal_snapshot'), false);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );
  testWidgets(
    'return from selection and final confirmation retains user input',
    (tester) async {
      final api = _Api(),
          targets = [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')];
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingEntryPage(
            api: api,
            siteId: _id(3),
            issueDate: '2026-10-31',
            targets: targets,
            initial: _input(),
            render: (_) async => Uint8List.fromList('%PDF-synthetic'.codeUnits),
            previewBuilder: (_) => const Text('合成PDF'),
          ),
        ),
      );
      await _inputDone(tester);
      await tester.tap(find.text('入力画面に戻る'));
      await tester.pumpAndSettle();
      expect((await _inputField(tester, 'unit_price')).controller!.text, '100');
      await _inputDone(tester);
      await _selectAndPreview(tester);
      await tester.tap(find.text('注文内容を確認'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '入力画面に戻る').last);
      await tester.pumpAndSettle();
      expect((await _inputField(tester, 'work_name')).controller!.text, '合成工事');
      expect(api.contexts, 1);
    },
  );
  testWidgets(
    'shared paper editor changes survive returning to input and rebinding',
    (tester) async {
      final originalPrinting = PrintingPlatform.instance;
      final sealPrinting = _InputSealPrinting();
      PrintingPlatform.instance = sealPrinting;
      addTearDown(() { PrintingPlatform.instance = originalPrinting; });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final api = _Api(),
          targets = [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')];
      final rendered = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingEntryPage(
            api: api,
            siteId: _id(3),
            issueDate: '2026-10-31',
            targets: targets,
            initial: _input(),
            render: (body) async {
              rendered.add(body);
              return Uint8List.fromList('%PDF-synthetic'.codeUnits);
            },
            previewBuilder: (_) => const Text('合成PDF'),
          ),
        ),
      );
      await _inputDone(tester);
      await _selectAndPreview(tester);
      await tester.tap(find.text('プレビューを編集'));
      await tester.pumpAndSettle();
      // The current shared editor has an independent issuer-seal raster Future.
      // Finish that boundary before leaving the route; input-retention remains
      // the contract under test, not native visual correctness.
      await _waitForInputSeal(tester);
      expect(sealPrinting.rasterCalls, 1);
      final editor = tester.widget<TradeDocumentTouchEditorPage>(
        find.byType(TradeDocumentTouchEditorPage),
      );
      final edited = editor.initial.withChanges({
        'work_name': '変更した工事',
        'notes': '保持する備考',
      });
      await editor.onSave(edited.payload);
      Navigator.of(tester.element(find.byType(TradeDocumentTouchEditorPage)))
          .pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('入力画面に戻る'));
      await tester.pumpAndSettle();
      await _inputDone(tester);
      await _selectAndPreview(tester);
      expect(rendered.last['work_name'], '変更した工事');
      expect(rendered.last['notes'], '保持する備考');
      expect(api.contexts, 2);
    },
  );
  testWidgets(
    'scope loss destroys all financial input before any target request',
    (tester) async {
      final api = _Api(),
          targets = [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')];
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingEntryPage(
            api: api,
            siteId: _id(3),
            issueDate: '2026-10-31',
            targets: targets,
            initial: _input(),
          ),
        ),
      );
      api.expired = true;
      api.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(api.contexts, 0);
      expect(find.text('閉じる'), findsOneWidget);
    },
  );
  testWidgets(
    'closing the route retires a delayed binding before PDF rendering',
    (tester) async {
      final api = _Api()..contextBarrier = Completer<void>();
      final targets = [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')];
      var renders = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingEntryPage(
            api: api,
            siteId: _id(3),
            issueDate: '2026-10-31',
            targets: targets,
            initial: _input(),
            render: (_) async {
              renders++;
              return Uint8List.fromList('%PDF-synthetic'.codeUnits);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _inputDone(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登録表示名').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('注文書を確認'));
      await tester.pump();
      expect(api.contexts, 1);
      await tester.pumpWidget(const MaterialApp(home: Text('閉じた画面')));
      api.contextBarrier!.complete();
      await tester.pumpAndSettle();
      expect(renders, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'caller list mutation cannot introduce an unverified dropdown option',
    (tester) async {
      final api = _Api(),
          targets = [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')];
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingEntryPage(
            api: api,
            siteId: _id(3),
            issueDate: '2026-10-31',
            targets: targets,
            initial: _input(),
          ),
        ),
      );
      targets.add(
        const SiteOrderRegisteredTarget(id: 'not-a-company-id', name: '後から追加'),
      );
      await _inputDone(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('後から追加'), findsNothing);
    },
  );
  testWidgets(
    'scope retirement removes recipient and amount from an open confirmation',
    (tester) async {
      final api = _Api(),
          targets = [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')];
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingEntryPage(
            api: api,
            siteId: _id(3),
            issueDate: '2026-10-31',
            targets: targets,
            initial: _input(),
            render: (_) async => Uint8List.fromList('%PDF-synthetic'.codeUnits),
            previewBuilder: (_) => const Text('合成PDF'),
          ),
        ),
      );
      await _inputDone(tester);
      await _selectAndPreview(tester);
      await tester.tap(find.text('注文内容を確認'));
      await tester.pumpAndSettle();
      expect(find.textContaining('正式な合成乙会社'), findsOneWidget);
      api.expired = true;
      api.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.textContaining('正式な合成乙会社'), findsNothing);
      expect(find.textContaining('120円'), findsNothing);
      expect(find.text('画面を開き直してください。'), findsOneWidget);
    },
  );
  testWidgets(
    'normal route loads registered targets only after RAM input confirmation',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingEntryPage(
            api: api,
            siteId: _id(3),
            issueDate: '2026-10-31',
            initial: _input(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.targetReads, 0);
      expect(api.contexts, 0);
      await _inputDone(tester);
      expect(api.targetReads, 1);
      expect(api.contexts, 0);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    },
  );
  testWidgets(
    'unknown directory read preserves input and never reports an empty target list',
    (tester) async {
      final api = _Api()..targetReadUnknown = true;
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingEntryPage(
            api: api,
            siteId: _id(3),
            issueDate: '2026-10-31',
            initial: _input(),
          ),
        ),
      );
      await _inputDone(tester);
      expect(api.targetReads, 1);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('共有先に使える連携済み協力会社はありません。'), findsNothing);
      expect((await _inputField(tester, 'work_name')).controller!.text, '合成工事');
    },
  );
  testWidgets('retired RAM input reopens with retained edits and entirely fresh IDs', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final api = _Api();
    await api.verify();
    final context = await api.outgoingContext(_id(3), _id(7));
    final old = SiteOrderPendingPrepare(siteId: _id(3), documentId: _id(501),
      localId: _id(502), tradeId: _id(7), requestId: _id(503), sessionId: _id(4));
    final factory = SiteOrderOutgoingBodyFactory(verifiedContext: context,
      actorId: _id(1), companyId: _id(2), pending: old,
      termsSnapshot: TradeDocumentTermsSnapshot.reference);
    final draft = SiteOrderOutgoingEntries(_input()).applyTo(
      factory.newEditor(issueDate: '2026-10-31')).withChanges({'notes': '引き継ぐ備考'});
    final retained = SiteOrderReviewedInput(old, factory.canonicalForPrepare(draft), 'a' * 64);
    SiteOrderReviewedInput? returned;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: FilledButton(onPressed: () async {
        returned = await Navigator.push<SiteOrderReviewedInput>(context, MaterialPageRoute(builder: (_) =>
          SiteOrderOutgoingEntryPage(api: api, siteId: _id(3), issueDate: '2026-10-31',
            initialReviewed: retained, targets: [SiteOrderRegisteredTarget(id: _id(7), name: '登録表示名')],
            render: (_) async => Uint8List.fromList('%PDF-synthetic'.codeUnits),
            previewBuilder: (_) => const Text('再確認PDF'))));
      }, child: const Text('再入力を開く'))))));
    await tester.tap(find.text('再入力を開く')); await tester.pumpAndSettle();
    await _inputDone(tester); await _selectAndPreview(tester);
    await tester.tap(find.text('注文内容を確認')); await tester.pumpAndSettle();
    await tester.tap(find.text('内容を確認')); await tester.pumpAndSettle();
    expect(returned, isNotNull);
    expect(returned!.pending.documentId, isNot(old.documentId));
    expect(returned!.pending.localId, isNot(old.localId));
    expect(returned!.pending.requestId, isNot(old.requestId));
    expect(returned!.body['notes'], '引き継ぐ備考');
    expect((returned!.body['form_fields'] as Map)['rows'][0]['unit_price_yen'], 100);
  });

}
