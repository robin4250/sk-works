import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final fixturePath = Platform.environment['SKO_PAYROLL_FINALIZATION_FIXTURE_PATH'];
  test('actual source SQL response is accepted by the strict Dart snapshot consumer', () {
    final raw = jsonDecode(File(fixturePath!).readAsStringSync()) as Map<String, dynamic>;
    final snapshot = raw['snapshot'] as Map<String, dynamic>;
    final expected = PayrollStatementRecord(id: snapshot['statement_id'] as String,
      companyName: 'Changed current company', workerName: 'Changed current worker',
      periodStart: DateTime.parse(snapshot['period_start'] as String), periodEnd: DateTime.parse(snapshot['period_end'] as String),
      grossPay: 0, deductions: 0, netPay: 0, detail: const {}, workflowState: 'draft', revision: raw['revision'] as int);
    final saved = PayrollFinalizationResult.parse(raw, expected, raw['revision'] as int).statement!;
    expect(saved.companyName, snapshot['company_name']);expect(saved.netPay, 293000);
    expect(saved.workflowState, 'finalized');expect(saved.reviewConfirmed, true);expect(saved.detail['bank_account'], isEmpty);
  }, skip: fixturePath == null ? 'Generated exact SQL response is provided by Flutter CI' : false);
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
        onSaved: (_) => fail('unexpected save'), reloadStatement: () async => statement()))));
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
      reloadStatement: () async => statement()))));
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

  testWidgets('recalculation change never reports success and requires fresh confirmation', (tester) async {
    var writes = 0;
    final repository = PayrollFinalizationRepository(invoke: (name, params) async {
      if (name == 'read_payroll_finalization_status') return status();
      writes++;return {'finalized': false, 'reason': 'recalculation_changed', 'revision': 5};
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollFinalizationPanel(
      statement: statement(), repository: repository, onSaved: (_) => fail('unexpected save'),
      reloadStatement: () async => statement()))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '給与を確定'));await tester.pumpAndSettle();
    await tester.tap(find.text('確認して確定'));await tester.pumpAndSettle();
    expect(writes, 1);expect(find.textContaining('確認をやり直し'), findsOneWidget);
    expect(find.text('給与明細を確定して保存しました'), findsNothing);
    expect(find.widgetWithText(FilledButton, '給与を確定'), findsNothing);
  });
  testWidgets('successful confirmation uses saved snapshot instead of current metadata', (tester) async {
    PayrollStatementRecord? saved;
    final repository = PayrollFinalizationRepository(invoke: (name, params) async =>
      name == 'read_payroll_finalization_status' ? status() : response());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollFinalizationPanel(
      statement: statement(), repository: repository, onSaved: (value) => saved = value,
      reloadStatement: () async => statement()))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '給与を確定'));await tester.pumpAndSettle();
    await tester.tap(find.text('確認して確定'));await tester.pumpAndSettle();
    expect(saved!.companyName, 'Saved company');expect(saved!.isDraft, false);
    expect(saved!.detail['bank_account'], isEmpty);
    expect(find.text('給与明細を確定して保存しました'), findsOneWidget);
  });

  testWidgets('unknown result retains warning when capability says saved but saved source reload fails', (tester) async {
    var saved = false; var reads = 0; var writes = 0;
    final repository = PayrollFinalizationRepository(invoke: (name, params) async {
      if (name == 'read_payroll_finalization_status') {
        reads++;
        return saved ? {...status(ready: false), 'workflow_state': 'finalized', 'snapshot_saved': true} : status();
      }
      writes++;saved = true;throw StateError('lost reply after commit');
    });
    var unavailable = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollFinalizationPanel(
      statement: statement(), repository: repository, onSaved: (_) => fail('unexpected direct save'),
      onVerificationRequired: (value) => unavailable = value,
      reloadStatement: () async => statement()))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '給与を確定'));await tester.pumpAndSettle();
    await tester.tap(find.text('確認して確定'));await tester.pumpAndSettle();
    expect(unavailable, true);
    await tester.tap(find.text('保存状態を再読み込み'));await tester.pumpAndSettle();
    expect(find.text('保存結果を確認できません。再読み込みしてください。'), findsOneWidget);
    expect(find.text('保存状態を再読み込み'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '給与を確定'), findsNothing);
    expect(unavailable, true);expect(reads, 2);expect(writes, 1);
  });

  testWidgets('lost statement access disables cached ready capability while preserving reread', (tester) async {
    final repository = PayrollFinalizationRepository(invoke: (_, __) async => status());
    Future<void> show(bool available) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollFinalizationPanel(
        key: const ValueKey('same-panel'), statement: statement(), statementAvailable: available,
        repository: repository, onSaved: (_) => fail('unexpected save'), reloadStatement: () async => null))));
      await tester.pumpAndSettle();
    }
    await show(true);expect(find.widgetWithText(FilledButton, '給与を確定'), findsOneWidget);
    await show(false);expect(find.widgetWithText(FilledButton, '給与を確定'), findsNothing);
    expect(find.text('保存状態を再読み込み'), findsOneWidget);
  });
}
