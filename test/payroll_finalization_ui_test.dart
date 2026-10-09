import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_finalization_repository.dart';
import 'package:sk_works/features/payroll/payroll_finalization_panel.dart';

PayrollStatementRecord statement({int? revision = 4}) => PayrollStatementRecord(
  id: 'statement', companyName: 'Current company', workerName: 'Employee',
  periodStart: DateTime(2026, 10), periodEnd: DateTime(2026, 10, 31),
  grossPay: 100, deductions: 20, netPay: 80, detail: const {}, workflowState: 'draft', revision: revision);
Map<String, dynamic> status({bool ready = true}) => {
  'contract_version': 1, 'statement_id': 'statement', 'revision': 4,
  'period_start': '2026-10-01', 'period_end': '2026-10-31',
  'workflow_state': 'draft', 'snapshot_saved': false, 'can_finalize': ready};
Map<String, dynamic> response() => {'finalized': true, 'revision': 4, 'snapshot': {
  'schema_version': 1, 'statement_id': 'statement', 'revision': 4,
  'period_start': '2026-10-01', 'period_end': '2026-10-31',
  'company_name': 'Saved company', 'worker_name': 'Saved worker', 'issued_at': null,
  'result': {'gross_pay': 100, 'deductions': 20, 'net_pay': 80},
  'detail': {'workflow_state': 'finalized', 'review_confirmed': true, 'revision': 4, 'bank_account': {}},
}};
void main() {
  test('strict snapshot preserves saved names and refuses wrong target and bank disclosure', () {
    final parsed = PayrollFinalizationResult.parse(response(), statement(), 4);
    expect(parsed.statement!.companyName, 'Saved company');
    expect(parsed.statement!.workerName, 'Saved worker');
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (s) => s['statement_id'] = 'other',
      (s) => s['revision'] = 5,
      (s) => s['period_start'] = '2026-09-01',
      (s) => s['result']['net_pay'] = 81,
      (s) => s['detail']['bank_account'] = {'account_number': 'secret'},
    ]) {
      final raw = response(); mutate(raw['snapshot']);
      expect(() => PayrollFinalizationResult.parse(raw, statement(), 4), throwsFormatException);
    }
    expect(PayrollFinalizationResult.parse({'finalized': false, 'reason': 'recalculation_changed', 'revision': 5},
      statement(), 4).finalized, false);
  });
  test('missing capability alone is unsupported; permission failure propagates', () async {
    for (final code in ['PGRST202', '42883', '42501']) {
      final repository = PayrollFinalizationRepository(invoke: (_, __) async =>
        throw PostgrestException(message: 'function read_payroll_finalization_status does not exist', code: code));
      if (code == '42501') {
        await expectLater(repository.read(statement()), throwsA(isA<PostgrestException>()));
      } else {
        expect(await repository.read(statement()), isNull);
      }
    }
  });
  testWidgets('viewer and missing revision never expose save operation', (tester) async {
    for (final current in [statement(), statement(revision: null)]) {
      final repository = PayrollFinalizationRepository(invoke: (_, __) async =>
        status(ready: current.revision == null));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollFinalizationPanel(
        key: UniqueKey(), statement: current, repository: repository,
        onSaved: (_) => fail('unexpected save'), reloadStatement: () async {}))));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '給与を確定'), findsNothing);
    }
  });
  testWidgets('cancel sends nothing; duplicate tap sends once and unknown result requires read', (tester) async {
    var writes = 0; var reads = 0;
    final pending = Completer<dynamic>();
    final repository = PayrollFinalizationRepository(invoke: (name, params) async {
      if (name == 'read_payroll_finalization_status') { reads++; return status(); }
      writes++; expect(params['p_expected_revision'], 4);expect(params['p_confirmed'], true);
      return pending.future;
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollFinalizationPanel(
      statement: statement(), repository: repository, onSaved: (_) => fail('unexpected save'),
      reloadStatement: () async {}))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '給与を確定'));await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));await tester.pumpAndSettle();expect(writes, 0);
    await tester.tap(find.widgetWithText(FilledButton, '給与を確定'));await tester.pumpAndSettle();
    await tester.tap(find.text('確認して確定'));await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '給与を確定'), warnIfMissed: false);await tester.pump();
    expect(writes, 1);
    pending.completeError(StateError('lost reply'));await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '給与を確定'), findsNothing);
    expect(find.textContaining('再送せず'), findsOneWidget);
    await tester.tap(find.text('保存状態を再読み込み'));await tester.pumpAndSettle();
    expect(reads, 2);expect(writes, 1);
  });
}
