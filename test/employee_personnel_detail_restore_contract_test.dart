import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/phone_display.dart';

void main() {
  test('employee detail access is restricted to management roles', () {
    final repository = File(
      'lib/features/people/people_cloud_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/people/people_cloud_page.dart',
    ).readAsStringSync();

    expect(repository, contains("member.role == 'owner'"));
    expect(repository, contains("member.role == 'admin'"));
    expect(repository, contains("member.role == 'manager'"));
    expect(page, contains("onTap: !_canManagePeople"));
  });

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
    expect(page, contains("'電話番号'"));
    expect(page, contains("'緊急連絡先電話番号'"));
    expect(page, contains("'Googleマップを開けませんでした'"));
    expect(page, contains("scheme: 'tel'"));
    expect(page, contains("'www.google.com'"));
    expect(page, contains("'/maps/search/'"));
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

  test('employee list renders domestic phone and exposes call action', () {
    final list = File(
      'lib/features/people/people_cloud_page.dart',
    ).readAsStringSync();
    expect(list, contains('domesticPhoneDisplay(record.phone)'));
    expect(list, contains("tooltip: '電話をかける'"));
    expect(list, contains("scheme: 'tel'"));
  });

  test('phone display converts +81 to domestic leading zero', () {
    expect(domesticPhoneDisplay('+819012345678'), '09012345678');
    expect(domesticPhoneDisplay('+81-90-1234-5678'), '090-1234-5678');
    expect(domesticPhoneDisplay('090-1234-5678'), '090-1234-5678');
  });

  test('profile and employee registration share two-approver personnel workflow', () {
    final profile = File(
      'lib/features/profile/profile_page.dart',
    ).readAsStringSync();
    final peopleForm = File(
      'lib/features/people/people_page.dart',
    ).readAsStringSync();
    final edit = File(
      'lib/features/people/employee_personnel_edit_page.dart',
    ).readAsStringSync();
    final approvals = File(
      'lib/features/people/worker_personnel_change_approvals_page.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/'
      '20261002012754_add_worker_personnel_two_approver_edits.sql',
    ).readAsStringSync();
    final firstFill = File(
      'supabase/migrations/'
      '20261002013353_allow_unregistered_personnel_fields_without_approval.sql',
    ).readAsStringSync();

    expect(profile, contains("'社員個人情報'"));
    expect(profile, contains('savePersonnelProfile'));
    expect(peopleForm, contains("'血液型'"));
    expect(peopleForm, contains("'緊急連絡先'"));
    expect(edit, contains("'変更申請を送る'"));
    expect(approvals, contains("'承認 \$approvalCount/2 名'"));
    expect(approvals, contains('approvalCount/2 名'));
    expect(migration, contains('worker_personnel_change_requests'));
    expect(migration, contains('worker_personnel_change_approvals'));
    expect(migration, contains('v_count>=2'));
    expect(migration, contains('自分の申請は承認できません'));
    expect(firstFill, contains('if not v_requires_approval then'));
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
