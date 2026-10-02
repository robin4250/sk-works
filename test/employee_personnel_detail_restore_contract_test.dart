import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/phone_display.dart';

void main() {
  test('employee detail page exposes required personnel fields', () {
    final page = File(
      'lib/features/people/employee_personnel_detail_page.dart',
    ).readAsStringSync();

    for (final label in [
      '名前',
      '区分',
      '血液型',
      '職種',
      '電話番号',
      '住所',
      '緊急連絡先氏名',
      '続柄',
      '緊急連絡先電話番号',
      '緊急連絡先住所',
    ]) {
      expect(page, contains(label));
    }

    expect(page, contains("'送信'"));
    expect(page, contains("'印刷'"));
    expect(page, contains("'社員一覧'"));
    expect(page, contains("'個別'"));
  });

  test('personnel list print is A4 landscape with company and date', () {
    final page = File(
      'lib/features/people/employee_personnel_print_page.dart',
    ).readAsStringSync();

    expect(page, contains('PdfPageFormat.a4.landscape'));
    expect(page, contains('companyName'));
    expect(page, contains('Alignment.centerRight'));
    expect(page, contains("pdfFileName: '社員一覧.pdf'"));
    expect(page, contains('allowPrinting: true'));
    expect(page, contains('allowSharing: true'));
  });

  test('phone display converts +81 to domestic leading zero', () {
    expect(domesticPhoneDisplay('+819012345678'), '09012345678');
    expect(domesticPhoneDisplay('+81-90-1234-5678'), '090-1234-5678');
    expect(domesticPhoneDisplay('090-1234-5678'), '090-1234-5678');
  });

  test('employee details reuse approved onboarding data', () {
    final repository = File(
      'lib/features/people/people_cloud_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261002011817_add_employee_personnel_rows.sql',
    ).readAsStringSync();

    expect(repository, contains("rpc('employee_personnel_rows')"));
    expect(migration, contains('employee_registration_invites'));
    expect(migration, contains("eri.status='approved'"));
    expect(migration, contains("'blood_type'"));
    expect(migration, contains("'emergency_relation'"));
  });
}
