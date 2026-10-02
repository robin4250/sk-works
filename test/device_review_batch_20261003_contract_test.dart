import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee and daily report previews support real pinch zoom', () {
    final employee = File(
      'lib/features/people/employee_personnel_print_page.dart',
    ).readAsStringSync();
    final daily = File(
      'lib/features/daily_reports/daily_report_page.dart',
    ).readAsStringSync();

    expect(employee, contains('InteractiveViewer('));
    expect(employee, contains('maxScale: 5'));
    expect(employee, contains('constrained: false'));
    expect(daily, contains('日報 A4プレビュー'));
    expect(daily, contains('InteractiveViewer('));
    expect(daily, contains('maxScale: 5'));
    expect(daily, contains('constrained: false'));
  });

  test('attendance home cards follow menu visibility and order', () {
    final home = File(
      'lib/features/home/friendly_home_content.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(home, contains('_OrderedHomeContent'));
    expect(home, contains("visibleHomeKeys.contains('attendance_verify')"));
    expect(home, contains("visibleHomeKeys.contains('attendance_today')"));
    expect(home, contains("key == 'attendance_verify'"));
    expect(home, contains("key == 'attendance_today'"));
    expect(app, contains("showAttendanceReport:"));
    expect(app, contains("showTodayAttendance:"));
  });

  test('attendance sheet hides zero totals and uses configurable units', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/attendance/worker_attendance_sheet_repository.dart',
    ).readAsStringSync();
    final pdf = File(
      'lib/features/attendance/attendance_pdf_service.dart',
    ).readAsStringSync();

    expect(page, contains("day.allowanceUnits[name] ?? '回'"));
    expect(page, contains("data.allowanceUnits[entry.key] ?? '回'"));
    expect(repository, contains("rpc('my_attendance_allowance_units')"));
    expect(pdf, contains('_hoursCell'));
    expect(pdf, contains('if (data.overtimeHours > 0)'));
    expect(pdf, contains("data.allowanceUnits[entry.key] ?? '回'"));
  });

  test('site map is native multi-pin and employee homes are admin-menu only', () {
    final map = File('lib/features/sites/site_map_page.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();
    final sites = File(
      'lib/features/sites/site_cloud_page.dart',
    ).readAsStringSync();
    final prepare = File('tool/prepare_ios.sh').readAsStringSync();

    expect(map, contains("MethodChannel('sko.multi_pin_map')"));
    expect(map, contains('選択地点を複数ピンで地図表示'));
    expect(map, contains('this.allowEmployeeHomes = false'));
    expect(app, contains('SiteMapPage(allowEmployeeHomes: true)'));
    expect(sites, contains('const SiteMapPage()'));
    expect(prepare, contains('import MapKit'));
    expect(prepare, contains('showAnnotations'));
  });

  test('chat fits tabs and anchors newest bubble above composer', () {
    final chat = File(
      'lib/features/chat/chat_cloud_page.dart',
    ).readAsStringSync();

    expect(chat, contains('reverse: true'));
    expect(chat, contains('_messages.length - 1 - index'));
    expect(chat, contains('Expanded('));
    expect(chat, contains('_chatTabButton'));
    expect(chat, contains("label: '協力会社'"));
  });

  test('daily report restores reporter sign and photo location review', () {
    final page = File(
      'lib/features/daily_reports/daily_report_page.dart',
    ).readAsStringSync();
    final repo = File(
      'lib/features/daily_reports/daily_report_repository.dart',
    ).readAsStringSync();
    final pdf = File(
      'lib/features/daily_reports/daily_report_pdf_service.dart',
    ).readAsStringSync();

    expect(page, contains('報告者サイン'));
    expect(page, contains('責任者サイン'));
    expect(page, contains('位置を地図で確認'));
    expect(repo, contains('representative_signature_json'));
    expect(repo, contains('latitude,longitude,accuracy_m'));
    expect(pdf, contains('報告者サイン'));
    expect(pdf, contains('責任者サイン'));
  });

  test('admin company documents entry is now company data', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final page = File(
      'lib/features/people/company_submitted_documents_page.dart',
    ).readAsStringSync();

    expect(app, contains("label: '会社データ'"));
    for (final label in const [
      '会社名',
      '会社住所',
      '法人番号（13桁）',
      '会社電話番号',
      '会社FAX番号',
      'メールアドレス',
      '銀行名',
      '支店名',
      '口座番号',
      '口座名義',
      'カメラで撮影',
      '写真ライブラリから選択',
    ]) {
      expect(page, contains(label));
    }
  });
}
