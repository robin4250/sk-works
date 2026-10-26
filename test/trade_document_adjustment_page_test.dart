import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shared/trade_document_adjustment_repository.dart';
import 'package:sk_works/features/shared/trade_document_adjustment_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/trade_document_adjustment_model.dart';
import 'package:sk_works/features/shared/trade_document_adjustment_page.dart';

const company = '11111111-1111-4111-8111-111111111111';
const party = '22222222-2222-4222-8222-222222222222';
const entry = '33333333-3333-4333-8333-333333333333';
const commandId = '44444444-4444-4444-8444-444444444444';
const month = '2026-10-01';

TradeDocumentAdjustmentCommand command({int amount = 100}) => TradeDocumentAdjustmentCommand(
  commandId: commandId, companyId: company, kind: TradeDocumentAdjustmentKind.invoice,
  partyId: party, month: month, expectedVersion: 0, action: TradeDocumentAdjustmentAction.add,
  calculationMode: TradeDocumentAdjustmentCalculationMode.settlementYen,
  sign: TradeDocumentAdjustmentSign.plus, title: '調整', amountYen: amount,
  recurrence: TradeDocumentAdjustmentRecurrence.once);

class FakePort implements TradeDocumentAdjustmentPort {
  bool ready = true, locked = false, unknown = false, wrongScope = false;
  String taxMode = 'settlement_yen';
  int calls = 0, lookups = 0;
  final requests = <TradeDocumentAdjustmentCommand>[];
  final previews = <TradeDocumentAdjustmentPreview>[];
  TradeDocumentAdjustmentCommand? received;
  TradeDocumentAdjustmentReceipt? receipt;
  @override
  Future<TradeDocumentAdjustmentWorkspace> load({required String companyId,
    required TradeDocumentAdjustmentKind kind, required String month, String? partyId}) async =>
    TradeDocumentAdjustmentWorkspace(companyId: companyId, kind: kind, month: month,
      parties: [TradeDocumentAdjustmentParty(id: party, companyId: companyId, kind: kind, name: '対象会社')],
      entries: [], partyId: wrongScope ? null : partyId, version: receipt?.version ?? 0,
      ready: ready, locked: locked, canEdit: true, taxMode: taxMode, chargeSites: [],
      supportedModes: taxMode == 'unknown' ? {} : {TradeDocumentAdjustmentCalculationMode.settlementYen});
  @override
  Future<TradeDocumentAdjustmentPreview> preview(TradeDocumentAdjustmentCommand command) async =>
    TradeDocumentAdjustmentPreview(request: command.toJson(), token: 'preview', baseTotalYen: 1000, resultTotalYen: 1100);
  @override
  Future<TradeDocumentAdjustmentReceipt> apply(TradeDocumentAdjustmentCommand command, {required TradeDocumentAdjustmentPreview preview}) async {
    calls++; received = command; requests.add(command); previews.add(preview);
    receipt = TradeDocumentAdjustmentReceipt(request: command.toJson(), applied: true, version: 1, entryId: entry, previewToken: 'preview', resultTotalYen: 1100);
    if (unknown) { throw TimeoutException('unknown'); }
    return receipt!;
  }
  bool wrongHistoryScope = false;
  final historyCursors = <int?>[];
  @override
  Future<TradeDocumentAdjustmentHistory> history({required String companyId,
    required TradeDocumentAdjustmentKind kind, required String partyId, required String month, int? beforeId}) async {
    historyCursors.add(beforeId);
    return TradeDocumentAdjustmentHistory(companyId: companyId, kind: kind,
      partyId: wrongHistoryScope ? companyId : partyId, month: month,
      entries: [TradeDocumentAdjustmentHistoryEntry(id: beforeId == null ? 102 : 101,
        commandId: commandId, actorId: company, createdAt: DateTime.utc(2026, 10, 26),
        action: TradeDocumentAdjustmentAction.add, title: '記録項目', beforeTotalYen: 1000,
        afterTotalYen: 1100, changedMonths: [month])], hasMore: beforeId == null);
  }
  @override
  Future<TradeDocumentAdjustmentReceipt?> lookup(TradeDocumentAdjustmentCommand command) async {
    lookups++; expect(identical(command, received), isTrue); return receipt;
  }
}

Future<void> show(WidgetTester tester, FakePort port, {TradeDocumentAdjustmentKind kind = TradeDocumentAdjustmentKind.invoice}) async {
  await tester.pumpWidget(MaterialApp(home: TradeDocumentAdjustmentPage(companyId: company,
    kind: kind, month: month, initialPartyId: party, port: port)));
  await tester.pumpAndSettle();
}

TradeDocumentAdjustmentPreview previewFor(TradeDocumentAdjustmentCommand c) => TradeDocumentAdjustmentPreview(
  request: c.toJson(), token: 'preview', baseTotalYen: 1000, resultTotalYen: 1100);

void main() {
  for (final mode in ['valid', 'wrong_scope', 'wrong_number_type', 'transport', 'rejected', 'history_wrong_scope']) {
    test('SDK adjustment apply is strict and never retries: $mode', () async {
      String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token = '${part({'alg': 'HS256'})}.${part({'sub': company, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
      var calls = 0;
      final c = command();
      final client = SupabaseClient('https://fixture.invalid', 'fixture-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((request) async {
          if (request.url.path == '/auth/v1/token') {
            return http.Response(jsonEncode({'access_token': token, 'refresh_token': 'fixture',
              'token_type': 'bearer', 'expires_in': 3600, 'user': {'id': company,
              'aud': 'authenticated', 'role': 'authenticated', 'email': 'fixture@example.invalid',
              'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}}}),
              200, headers: {'content-type': 'application/json'}, request: request);
          }
          calls++;
          if (mode == 'history_wrong_scope') {
            expect(request.url.path, '/rest/v1/rpc/read_trade_document_adjustment_history');
            expect(jsonDecode(request.body), {'p_company_id': company, 'p_kind': 'invoice',
              'p_party_id': party, 'p_month': month, 'p_before_id': null});
            return http.Response(jsonEncode({'company_id': company, 'kind': 'invoice',
              'party_id': company, 'month': month, 'entries': [], 'has_more': false}),
              200, headers: {'content-type': 'application/json'}, request: request);
          }
          expect(request.url.path, '/rest/v1/rpc/apply_trade_document_adjustment');
          expect(jsonDecode(request.body), {'p_command': c.toJson(), 'p_preview_token': 'preview'});
          expect(request.headers.entries.where((e) => e.key.toLowerCase() == 'authorization').single.value, 'Bearer $token');
          if (mode == 'transport') { throw StateError('fixture failure'); }
          if (mode == 'rejected') { return http.Response(jsonEncode({'code': '40001', 'message': 'private server detail'}),
            409, headers: {'content-type': 'application/json'}, request: request); }
          return http.Response(jsonEncode({'request': mode == 'wrong_scope' ? {...c.toJson(), 'party_id': company} : c.toJson(),
            'applied': true, 'version': mode == 'wrong_number_type' ? '1' : 1,
            'entry_id': entry, 'preview_token': 'preview', 'result_total_yen': 1100}),
            200, headers: {'content-type': 'application/json'}, request: request);
        }));
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture');
      final repository = SupabaseTradeDocumentAdjustmentRepository(client);
      addTearDown(repository.dispose);
      if (mode == 'history_wrong_scope') {
        await expectLater(repository.history(companyId: company, kind: TradeDocumentAdjustmentKind.invoice,
          partyId: party, month: month), throwsFormatException);
      } else if (mode == 'valid') {
        expect((await repository.apply(c, preview: previewFor(c))).resultTotalYen, 1100);
      } else if (mode == 'rejected') {
        await expectLater(repository.apply(c, preview: previewFor(c)), throwsA(isA<TradeDocumentAdjustmentRejected>()));
      } else if (mode == 'transport') {
        await expectLater(repository.apply(c, preview: previewFor(c)), throwsStateError);
      } else {
        await expectLater(repository.apply(c, preview: previewFor(c)), throwsFormatException);
      }
      expect(calls, 1);
      repository.invalidate();
      await expectLater(repository.apply(c, preview: previewFor(c)), throwsStateError);
      expect(calls, 1);
    });
  }

  testWidgets('history is read-only and paginates with last verified id', (tester) async {
    final port = FakePort();
    await tester.pumpWidget(MaterialApp(home: TradeDocumentAdjustmentHistoryPage(companyId: company,
      kind: TradeDocumentAdjustmentKind.invoice, partyId: party, month: month, port: port)));
    await tester.pumpAndSettle();
    expect(find.text('操作者ID $company'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.ensureVisible(find.text('次の100件を読み込む'));
    await tester.tap(find.text('次の100件を読み込む'));
    await tester.pumpAndSettle();
    expect(port.historyCursors, [null, 102]);
    expect(find.text('操作者ID $company'), findsNWidgets(2));
    expect(port.calls, 0);
  });
  testWidgets('history rejects different counterparty response without rendering records', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TradeDocumentAdjustmentHistoryPage(companyId: company,
      kind: TradeDocumentAdjustmentKind.invoice, partyId: party, month: month,
      port: FakePort()..wrongHistoryScope = true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('記録項目'), findsNothing);
    expect(find.text('再読み込み'), findsOneWidget);
  });
  test('positive yen bounds and canonical month are enforced', () {
    expect(() => command(amount: 0), throwsFormatException);
    expect(() => command(amount: 2147483648), throwsFormatException);
    expect(command(amount: 2147483647).amountYen, 2147483647);
    expect(() => tradeDocumentAdjustmentMonth('2026-10-02'), throwsFormatException);
  });
  test('receipt verifies request semantics independent of JSON key ordering', () {
    final request = command();
    final reversed = Map<String, dynamic>.fromEntries(request.toJson().entries.toList().reversed);
    TradeDocumentAdjustmentReceipt(request: reversed, applied: true, version: 1, entryId: entry, previewToken: 'preview', resultTotalYen: 1100).verify(request, previewFor(request));
    expect(() => TradeDocumentAdjustmentReceipt(request: {...reversed, 'party_id': company},
      applied: true, version: 1, entryId: entry, previewToken: 'preview', resultTotalYen: 1100).verify(request, previewFor(request)), throwsFormatException);
    expect(() => TradeDocumentAdjustmentReceipt(request: reversed, applied: true,
      version: 0, entryId: entry, previewToken: 'preview', resultTotalYen: 1100).verify(request, previewFor(request)), throwsFormatException);
  });
  test('workspace rejects other-company and wrong-kind party', () {
    expect(() => TradeDocumentAdjustmentWorkspace(companyId: company, kind: TradeDocumentAdjustmentKind.invoice,
      month: month, parties: [TradeDocumentAdjustmentParty(id: party, companyId: company,
      kind: TradeDocumentAdjustmentKind.paymentCertificate, name: '対象')], entries: [],
      version: 0, ready: true, canEdit: true, taxMode: 'settlement_yen', chargeSites: [],
      supportedModes: {TradeDocumentAdjustmentCalculationMode.settlementYen}), throwsFormatException);
  });
  test('calculation-before-charges invoice requires site and recurring update requires template CAS', () {
    expect(() => TradeDocumentAdjustmentCommand(commandId: commandId, companyId: company,
      kind: TradeDocumentAdjustmentKind.invoice, partyId: party, month: month,
      expectedVersion: 0, action: TradeDocumentAdjustmentAction.add,
      calculationMode: TradeDocumentAdjustmentCalculationMode.beforeCharges,
      sign: TradeDocumentAdjustmentSign.plus, title: '項目', amountYen: 100,
      recurrence: TradeDocumentAdjustmentRecurrence.once), throwsFormatException);
    expect(() => TradeDocumentAdjustmentCommand(commandId: commandId, companyId: company,
      kind: TradeDocumentAdjustmentKind.invoice, partyId: party, month: month,
      expectedVersion: 0, action: TradeDocumentAdjustmentAction.stop, entryId: entry,
      calculationMode: TradeDocumentAdjustmentCalculationMode.settlementYen,
      updateScope: TradeDocumentAdjustmentUpdateScope.fromMonth), throwsFormatException);
    final c = command();
    expect(() => TradeDocumentAdjustmentReceipt(request: c.toJson(), applied: true,
      version: 1, entryId: entry, previewToken: 'different', resultTotalYen: 1100)
      .verify(c, previewFor(c)), throwsFormatException);
  });
  testWidgets('kind controls company label and exact recurrence labels', (tester) async {
    await show(tester, FakePort(), kind: TradeDocumentAdjustmentKind.paymentCertificate);
    expect(find.text('協力会社'), findsOneWidget);
    expect(find.text('今回だけ'), findsOneWidget);
    expect(find.text('毎月'), findsOneWidget);
    expect(find.text('2026年10月'), findsOneWidget);
  });
  testWidgets('unknown tax readiness never enables financial registration', (tester) async {
    final port = FakePort()..taxMode = 'unknown';
    await show(tester, port);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '計算結果を確認'));
    expect(button.onPressed, isNull);
    expect(find.text('この機能は準備中です。'), findsOneWidget);
    expect(port.calls, 0);
  });
  testWidgets('locked document is read-only', (tester) async {
    await show(tester, FakePort()..locked = true);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '計算結果を確認')).onPressed, isNull);
    expect(find.text('確定済みの帳票は変更できません。'), findsOneWidget);
  });
  testWidgets('mismatched read scope is rejected before showing a form', (tester) async {
    await show(tester, FakePort()..wrongScope = true);
    expect(find.text('計算結果を確認'), findsNothing);
    expect(find.text('再読み込み'), findsOneWidget);
  });
  testWidgets('explicit retry reuses same immutable command and preview', (tester) async {
    final port = FakePort()..unknown = true;
    await show(tester, port);
    await tester.tap(find.byType(DropdownButtonFormField<TradeDocumentAdjustmentCalculationMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TradeDocumentAdjustmentCalculationMode.settlementYen.label).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '項目名'), '交通費');
    await tester.enterText(find.widgetWithText(TextField, '金額'), '100');
    await tester.ensureVisible(find.text('計算結果を確認'));
    await tester.tap(find.text('計算結果を確認'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('この計算結果で登録'));
    await tester.tap(find.text('この計算結果で登録'));
    await tester.pumpAndSettle();
    expect(port.calls, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(port.calls, 1); // No automatic retry, including while waiting.
    port.unknown = false;
    await tester.ensureVisible(find.text('同じ内容で保存を再試行'));
    await tester.tap(find.text('同じ内容で保存を再試行'));
    await tester.pumpAndSettle();
    expect(port.calls, 2);
    expect(identical(port.requests[0], port.requests[1]), isTrue);
    expect(port.requests[0].toJson(), port.requests[1].toJson());
    expect(identical(port.previews[0], port.previews[1]), isTrue);
    expect(find.text('登録内容を保存しました。'), findsOneWidget);
  });
  testWidgets('lost acknowledgement retains immutable request and only looks up', (tester) async {
    final port = FakePort()..unknown = true;
    await show(tester, port);
    await tester.tap(find.byType(DropdownButtonFormField<TradeDocumentAdjustmentCalculationMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TradeDocumentAdjustmentCalculationMode.settlementYen.label).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '項目名'), '交通費');
    await tester.enterText(find.widgetWithText(TextField, '金額'), '100');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '計算結果を確認'));
    await tester.tap(find.widgetWithText(FilledButton, '計算結果を確認'));
    await tester.pumpAndSettle();
    expect(port.calls, 0);
    expect(find.text('登録後の合計：1100円'), findsOneWidget);
    await tester.ensureVisible(find.text('この計算結果で登録'));
    await tester.tap(find.text('この計算結果で登録'));
    await tester.pumpAndSettle();
    expect(port.calls, 1);
    expect(find.text('交通費'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, '項目名')).enabled, isFalse);
    await tester.ensureVisible(find.text('保存状態を確認'));
    await tester.tap(find.text('保存状態を確認'));
    await tester.pumpAndSettle();
    expect(port.calls, 1);
    expect(port.lookups, 1);
    expect(find.text('登録内容を保存しました。'), findsOneWidget);
  });
}
