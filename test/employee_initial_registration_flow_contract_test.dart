import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('top exposes separate employee registration and initial registration', () {
    final app = read('lib/app_v2.dart');

    expect(app, contains("key: 'employee_register'"));
    expect(app, contains("SkoLanguageController.tr('従業員登録')"));
    expect(app, contains('EmployeeRegistrationPage'));
    expect(app, contains("key: 'initial_registration'"));
    expect(app, contains("SkoLanguageController.tr('初回登録')"));
    expect(app, contains('EmployeeInitialRegistrationPage'));
    expect(app, contains("accessLabel: SkoLanguageController.tr('管理者')"));
  });

  test('employee preregistration stores only name and phone before invite', () {
    final page = read(
      'lib/features/people/employee_registration_page.dart',
    );
    final repository = read(
      'lib/features/people/employee_invite_repository.dart',
    );

    expect(page, contains('名前と携帯電話番号だけを先に登録'));
    expect(repository, contains('registerEmployee'));
    expect(repository, contains("'register_employee_preregistration'"));
    final foundation = read(
      'supabase/migrations/20261005062000_secure_employee_preregistration_rpcs.sql',
    );
    final latest = read(
      'supabase/migrations/20261006193110_activate_preregistered_employees.sql',
    );
    expect(foundation, contains("w.affiliation = 'employee'"));
    expect(latest, contains("'active'"));
    expect(latest, contains("status='inactive'"));
    expect(latest, contains('user_id is null'));
  });

  test('initial registration uses preregistered worker and delivery status', () {
    final page = read(
      'lib/features/people/employee_initial_registration_page.dart',
    );
    final repository = read(
      'lib/features/people/employee_invite_repository.dart',
    );
    final edge = read(
      'supabase/functions/create-employee-invite/index.ts',
    );

    expect(page, contains('TestFlight'));
    expect(page, contains('初回ログインQR'));
    expect(page, contains('未送信'));
    expect(repository, contains('createInviteForWorker'));
    expect(repository, contains("rpc('initial_registration_employee_rows')"));
    expect(repository, contains("'register_employee_preregistration'"));
    expect(repository, isNot(contains("from('workers').select")));
    expect(repository, contains("'workerId': workerId"));
    expect(repository, contains("'deliverSms': deliverSms"));
    expect(edge, contains('existingWorker'));
    expect(edge, contains('persistedWorkerId'));
    expect(edge, contains('status: "active"'));
    expect(edge, isNot(contains('status: "inactive"')));
    expect(edge, contains('SKO_TESTFLIGHT_URL'));
    expect(edge, contains('SKO_EMPLOYEE_INVITE_SMS_WEBHOOK'));
  });

  test('employee invite production deletion guards stay mirrored', () {
    final edge = read(
      'supabase/functions/create-employee-invite/index.ts',
    );

    expect(edge, contains('createDeletionInspection'));
    expect(edge, contains('serverAccountAccess'));
    expect(edge, contains('serverAccountActivity'));
    expect(edge, contains('inspectDeletion(req)'));
    expect(edge, contains('accountActivity.finish'));
    for (final path in [
      'supabase/functions/_shared/account_activity.mjs',
      'supabase/functions/_shared/account_access.mjs',
      'supabase/functions/_shared/account_deletion_inspection.mjs',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('fixed home header reserves status bar plus toolbar height', () {
    final app = read('lib/app_v2.dart');

    expect(app, contains('extendBodyBehindAppBar: true'));
    expect(app, contains('MediaQuery.paddingOf(context).top + 72'));
  });
}
