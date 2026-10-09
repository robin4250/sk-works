import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_confirmation_repository.dart';
import 'package:sk_works/features/payroll/payroll_statement_source_repository.dart';
import 'package:sk_works/features/payroll/payroll_statements_page.dart';

PayrollStatementRecord record({String id = 'saved', String state = 'finalized', String name = '保存会社', int net = 123}) =>
    PayrollStatementRecord(id: id, companyName: name, workerName: '保存社員',
      periodStart: DateTime(2026, 9), periodEnd: DateTime(2026, 9, 30),
      grossPay: net, deductions: 0, netPay: net, detail: const {'bank_account': {}},
      workflowState: state, revision: 4, reviewConfirmed: state == 'finalized');

void main() {
  test('frozen management history bypasses current confirmation and keeps saved display values', () async {
    final saved = record();
    var confirmationReads = 0;
    final repository = PayrollStatementSourceRepository(
      readManagement: (_) async => [saved],
      readSelf: () async => throw StateError('self source must not be consulted'),
      readConfirmation: (_) async { confirmationReads++; throw StateError('current month has changed'); });
    final source = await repository.load(record(state: 'draft', name: '現会社', net: 999));
    expect(identical(source.statement, saved), isTrue);
    expect(source.statement.companyName, '保存会社');
    expect(source.statement.netPay, 123);
    expect(source.confirmation, isNull);
    expect(confirmationReads, 0);
  });
  test('denied manager read uses only fresh own rows; missing target never uses original', () async {
    var selfReads = 0;
    final repository = PayrollStatementSourceRepository(
      readManagement: (_) async => throw const PostgrestException(message: 'denied', code: '42501'),
      readSelf: () async { selfReads++; return [record(id: 'other')]; },
      readConfirmation: (_) async => throw StateError('not expected'));
    await expectLater(repository.load(record()), throwsStateError);
    expect(selfReads, 1);
  });
  test('generic read failure propagates without self fallback or stale draft output', () async {
    var selfReads = 0;
    final repository = PayrollStatementSourceRepository(
      readManagement: (_) async => throw StateError('network'),
      readSelf: () async { selfReads++; return [record()]; },
      readConfirmation: (_) async => throw StateError('not expected'));
    await expectLater(repository.load(record(state: 'draft')), throwsStateError);
    expect(selfReads, 0);
  });
  test('fresh draft keeps current confirmation without altering source amounts', () async {
    final fresh = record(state: 'draft', net: 456);
    final confirmation = PayrollConfirmationStatus.fromJson({'confirmed': true});
    final repository = PayrollStatementSourceRepository(
      readManagement: (_) async => [fresh],
      readSelf: () async => throw StateError('not expected'),
      readConfirmation: (_) async => confirmation);
    final source = await repository.load(record(net: 123));
    expect(identical(source.statement, fresh), isTrue);
    expect(identical(source.confirmation, confirmation), isTrue);
    expect(source.statement.netPay, 456);
  });
  test('named missing workspace rereads only own saved source', () async {
    final saved = record();
    final repository = PayrollStatementSourceRepository(
      readManagement: (_) async => throw const PostgrestException(message: 'payroll_review_workspace not found', code: 'PGRST202'),
      readSelf: () async => [saved],
      readConfirmation: (_) async => throw StateError('not expected'));
    final source = await repository.load(record(state: 'draft'));
    expect(identical(source.statement, saved), isTrue);
    expect(source.confirmation, isNull);
  });
  test('named missing confirmation keeps fresh draft; unrelated missing RPC fails', () async {
    final fresh = record(state: 'draft', net: 456);
    PayrollStatementSourceRepository repository(String message) => PayrollStatementSourceRepository(
      readManagement: (_) async => [fresh],
      readSelf: () async => throw StateError('not expected'),
      readConfirmation: (_) async => throw PostgrestException(message: message, code: '42883'));
    final source = await repository('payroll_confirmation_status not found').load(record());
    expect(identical(source.statement, fresh), isTrue);
    expect(source.confirmation, isNull);
    await expectLater(repository('unrelated_function not found').load(record()), throwsA(isA<PostgrestException>()));
  });
  testWidgets('pending read and failed retry never create sharing or printing preview from old draft', (tester) async {
    final pending = Completer<List<PayrollStatementRecord>>();
    var reads = 0;
    final repository = PayrollStatementSourceRepository(
      readManagement: (_) { reads++; return reads == 1 ? pending.future : Future.error(StateError('retry failed')); },
      readSelf: () async => [record()],
      readConfirmation: (_) async => throw StateError('not expected'));
    await tester.pumpWidget(MaterialApp(home: PayrollStatementPreviewPage(
      statement: record(state: 'draft'), sourceRepository: repository)));
    await tester.pump();
    expect(find.byType(PdfPreview), findsNothing);
    pending.completeError(StateError('source unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfPreview), findsNothing);
    expect(find.textContaining('source unavailable'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.byType(PdfPreview), findsNothing);
    expect(find.textContaining('retry failed'), findsOneWidget);
  });
}
