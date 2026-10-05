import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice PDF mirrors supplied reference form', () {
    final source = read('lib/features/invoices/invoice_pdf_service.dart');
    expect(source, contains('御　請　求　書'));
    expect(source, contains('御請求金額'));
    expect(source, contains('件名 ／ 工期'));
    expect(source, contains('作業所名'));
    expect(source, contains('工事内容'));
    expect(source, contains('請求金額'));
    expect(source, contains('お支払約定日'));
    expect(source, contains('備考：'));
    expect(source, contains('InvoiceSettingsRepository.maybeCreate()'));
  });

  test('payroll PDF mirrors supplied landscape grid form', () {
    final source = read('lib/features/payroll/payroll_pdf_service.dart');
    expect(source, contains('PdfPageFormat.a4.landscape'));
    expect(source, contains('給与明細書'));
    expect(source, contains('出勤日数'));
    expect(source, contains('基本給'));
    expect(source, contains('健康保険料'));
    expect(source, contains('総支給額'));
    expect(source, contains('差引支給額'));
    expect(source, contains('月次減税額'));
    expect(source, contains('お疲れさまです。'));
  });

  test('payment certificate uses calculated SKO detail rows', () {
    final repo = read(
      'lib/features/payroll/payment_certificate_repository.dart',
    );
    final pdf = read(
      'lib/features/payroll/payment_certificate_pdf_service.dart',
    );
    final migration = read(
      'supabase/migrations/20261005065000_payment_certificate_reference_detail_rows.sql',
    );

    expect(repo, contains('payment_certificate_detail_rows'));
    expect(pdf, contains('工事代金支払明細書'));
    expect(pdf, contains('作　業　所　名'));
    expect(pdf, contains('工　事　内　容'));
    expect(pdf, contains('差　引　残　高'));
    expect(migration, contains('security definer'));
    expect(migration, contains('revoke all on function'));
    expect(migration, contains('to authenticated'));
  });
}
