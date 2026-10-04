import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('admin setup keeps employee onboarding states intact', () {
    final gate = read('lib/features/auth/auth_gate.dart');
    final pages = read('lib/features/auth/secure_onboarding_pages.dart');

    expect(gate, contains('_GateStatus.employeePassword'));
    expect(gate, contains('_GateStatus.employeeProfile'));
    expect(gate, contains('_GateStatus.employeeApprovalPending'));
    expect(gate, contains('_GateStatus.needsAdminInitialSetup'));
    expect(pages, contains('従業員登録QRでログイン'));
  });

  test('admin initial setup follows rollout sequence instead of site and rates', () {
    final page = read('lib/features/auth/admin_initial_setup_page.dart');
    final migration = read(
      'supabase/migrations/20261005045500_align_admin_initial_setup_with_employee_rollout.sql',
    );

    for (final label in [
      '個人情報登録',
      '会社情報登録',
      '提出書類登録',
      '資格設定',
      '従業員登録',
      '初回登録',
    ]) {
      expect(page, contains(label));
    }

    expect(page, contains('CompanySubmittedDocumentsPage'));
    expect(page, contains('QualificationCloudPage'));
    expect(page, contains('EmployeeRegistrationPage'));
    expect(page, contains('EmployeeInitialRegistrationPage'));
    expect(page, contains('現場登録や単価設定は初回必須ではなく'));

    expect(migration, contains('personal_profile_completed'));
    expect(migration, contains('company_documents_reviewed'));
    expect(migration, contains('qualification_settings_reviewed'));
    expect(migration, contains('employee_registration_reviewed'));
    expect(migration, contains('initial_registration_reviewed'));
    expect(migration, contains('mark_admin_initial_setup_step'));
  });

  test('existing completed companies stay completed after rollout migration', () {
    final migration = read(
      'supabase/migrations/20261005045500_align_admin_initial_setup_with_employee_rollout.sql',
    );

    expect(migration, contains('where completed_at is not null'));
    expect(migration, contains('company_documents_reviewed = true'));
    expect(migration, contains('initial_registration_reviewed = true'));
  });

  test('company profile completion also completes personal step', () {
    final migration = read(
      'supabase/migrations/20261005050000_sync_admin_personal_profile_initial_step.sql',
    );

    expect(migration, contains('sync_initial_personal_profile_progress'));
    expect(migration, contains('new.company_profile_completed'));
    expect(migration, contains('new.personal_profile_completed := true'));
  });
}
