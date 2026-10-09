import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance list opens worker selector and supports batch printing', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final list = File(
      'lib/features/attendance/attendance_worker_list_page.dart',
    ).readAsStringSync();
    final sheet = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();
    final pdf =
        File('lib/features/attendance/attendance_pdf_service.dart')
            .readAsStringSync();

    expect(app, contains("key: 'attendance_list'"));
    expect(app, contains('const AttendanceWorkerListPage()'));
    expect(list, contains("'出勤表一覧'"));
    expect(list, contains("'全社員の出勤表をまとめて印刷'"));
    expect(list, contains('WorkerAttendanceSheetPage('));
    expect(list, contains('workerId: worker.id'));
    expect(list, contains('AttendancePdfService.printWorkers'));
    expect(sheet, contains('this.workerId'));
    expect(sheet, contains('this.initialMonth'));
    expect(pdf, contains('printWorkers('));
    expect(pdf, contains('出勤表一覧.pdf'));
  });

  test('qualification registration is split into own and employee flows', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final own = File(
      'lib/features/qualifications/own_qualification_registration_page.dart',
    ).readAsStringSync();
    final employee = File(
      'lib/features/qualifications/qualification_cloud_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/qualifications/qualification_cloud_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261003120833_allow_self_qualification_registration.sql',
    ).readAsStringSync();

    expect(app, contains("key: 'qualification_register'"));
    expect(app, contains("SkoLanguageController.tr('資格登録')"));
    expect(app, contains("key: 'employee_qualifications'"));
    expect(app, contains("SkoLanguageController.tr('従業員資格')"));
    expect(own, contains("'ログイン中の本人の資格だけを表示します'"));
    expect(own, contains('loadOwnQualificationWorkspace'));
    expect(own, contains('insertOwnQualification'));
    expect(employee, contains("'従業員資格'"));
    expect(employee, contains("'従業員名で検索'"));
    expect(employee, contains("'資格種類・証明書番号で検索'"));
    expect(repository, contains("value.role == 'manager'"));
    expect(migration, contains('worker can register own qualification'));
    expect(migration, contains('w.user_id = (select auth.uid())'));
  });

  test('signature feature data remains while its home shortcut is retired', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final repository = File(
      'lib/features/settings/company_module_settings_repository.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/settings/company_module_settings_page.dart',
    ).readAsStringSync();

    expect(repository, contains("'signatures'"));
    expect(
      settings.replaceAll(RegExp(r'\s+'), ' '),
      contains("'signatures' => SkoLanguageController.tr('サイン一覧')"),
    );
    expect(app, isNot(contains("key: 'signatures'")));
    expect(app, contains("if (key == 'signatures') return;"));
    expect(app, contains("SkoLanguageController.tr('管理者・サブ管理者')"));
  });
}
