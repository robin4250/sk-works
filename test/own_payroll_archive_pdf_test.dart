import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/personal_vault/own_payroll_archive_pdf.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PayrollStatementRecord record({int gross = 100000}) => PayrollStatementRecord(
    id: 'synthetic-statement', companyName: 'Fixture company', workerName: 'Only owner',
    periodStart: DateTime(2026, 9, 1), periodEnd: DateTime(2026, 9, 30),
    grossPay: gross, deductions: 10000, netPay: gross - 10000,
    workflowState: 'finalized', revision: 1,
    detail: {'基本給': 100000, '所得税': 10000, '出勤日数': 5,
      'remarks': 'FOREIGN_INTERNAL_SECRET',
      'company_seal_snapshot': {'url': 'https://invalid.invalid/SECRET'}});
  test('allowlist never copies nested or free text company data', () {
    final projected = OwnPayrollArchivePdf.projectNumericDetail(record().detail);
    expect(jsonEncode(projected), isNot(contains('SECRET')));
    expect(projected['company_seal_enabled'], false);
    expect(projected['基本給'], 100000);
  });
  test('actual existing renderer succeeds without Supabase or network fonts', () async {
    final source = record(); final before = jsonEncode(source.detail);
    final font = pw.Font.ttf(ByteData.sublistView(await File(
      'assets/fonts/company-seal/NotoSansJP-Bold.ttf').readAsBytes()));
    final bytes = await OwnPayrollArchivePdf.build(source: source,
      verifiedPersonId: 'fixture-person', snapshotPersonId: 'fixture-person',
      sourceCompanyId: 'fixture-company', regularFont: font, boldFont: font);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(jsonEncode(source.detail), before);
  });
  test('unknown monetary breakdown and foreign owner fail before rendering', () {
    expect(() => OwnPayrollArchivePdf.build(source: record(gross: 100001),
      verifiedPersonId: 'fixture-person', snapshotPersonId: 'fixture-person',
      sourceCompanyId: 'fixture-company', regularFont: pw.Font.helvetica(),
      boldFont: pw.Font.helveticaBold()), throwsStateError);
    expect(() => OwnPayrollArchivePdf.build(source: record(),
      verifiedPersonId: 'fixture-person', snapshotPersonId: 'other-person',
      sourceCompanyId: 'fixture-company', regularFont: pw.Font.helvetica(),
      boldFont: pw.Font.helveticaBold()), throwsStateError);
  });
}
