import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('top attendance selection saves and returns to home', () {
    final page = File(
      'lib/features/attendance/attendance_selection_page.dart',
    ).readAsStringSync();
    final workplace = File(
      'lib/features/attendance/work_destination_selection_page.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(page, contains("'出勤方法と車両を選択'"));
    expect(page, contains("labelText: '出勤方法'"));
    expect(page, contains("labelText: '車両（任意）'"));
    expect(page, contains("'確定して保存'"));
    expect(page, contains("mode: _mode"));
    expect(workplace, contains("'現場の選択'"));
    expect(workplace, contains("labelText: '固定の1現場'"));
    expect(workplace, contains("labelText: '複数現場のルート'"));
    expect(app, contains("case 'attendance_method_vehicle':"));
    expect(app, contains("case 'workplace_select':"));
    expect(app, contains('AttendanceSelectionPage()'));
    expect(app, contains('WorkDestinationSelectionPage()'));
  });

  test('clock-in page follows requested field order and keeps recent confirmations', () {
    final page = File(
      'lib/features/attendance/attendance_verification_page.dart',
    ).readAsStringSync();

    expect(page.indexOf("labelText: '出勤方法'"), lessThan(page.indexOf("labelText: '現場'")));
    expect(page.indexOf("labelText: '現場'"), lessThan(page.indexOf("label: '車両'")));
    expect(page.indexOf("label: '車両'"), lessThan(page.indexOf("label: 'ルート'")));
    expect(page.indexOf("label: 'ルート'"), lessThan(page.indexOf("labelText: 'メモ'")));
    expect(page, contains("'出勤を確定'"));
    expect(page, contains("'最近の確認'"));
  });

  test('GPS auto attendance stores weekdays time and background location contract', () {
    final dialog = File(
      'lib/features/attendance/gps_auto_schedule_dialog.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/attendance/gps_auto_attendance_service.dart',
    ).readAsStringSync();
    final repo = File(
      'lib/features/attendance/attendance_verification_repository.dart',
    ).readAsStringSync();
    final ios = File('tool/prepare_ios.sh').readAsStringSync();

    expect(dialog, contains("'GPS自動出勤の曜日と取得時間'"));
    expect(dialog, contains("'GPS取得時間'"));
    expect(dialog, contains('LocationPermission.always'));
    expect(service, contains('AppleSettings('));
    expect(service, contains('allowBackgroundLocationUpdates: true'));
    expect(service, contains('Geolocator.getPositionStream'));
    expect(repo, contains("'attempt_gps_auto_attendance'"));
    expect(repo, contains("'save_my_attendance_selection'"));
    expect(ios, contains('NSLocationAlwaysAndWhenInUseUsageDescription'));
    expect(ios, contains('background_modes.append("location")'));
  });

  test('location photo never keeps GPS auto background schedule enabled', () {
    final confirmPage = File(
      'lib/features/attendance/attendance_verification_page.dart',
    ).readAsStringSync();
    final selectionPage = File(
      'lib/features/attendance/attendance_selection_page.dart',
    ).readAsStringSync();
    final sql = File(
      'supabase/migrations/'
      '20261002004813_separate_gps_auto_from_location_photo.sql',
    ).readAsStringSync();

    expect(confirmPage, contains('位置情報＋写真（確定時のみ）'));
    expect(selectionPage, contains('位置情報＋写真（確定時のみ）'));
    expect(confirmPage, contains('GpsAutoAttendanceService.instance.refresh()'));
    expect(sql, contains("if v_mode='gps_auto' then"));
    expect(sql, contains('set enabled=false'));
  });

  test('location photo evidence links to and displays beside daily report', () {
    final repo = File(
      'lib/features/daily_reports/daily_report_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/daily_reports/daily_report_page.dart',
    ).readAsStringSync();

    expect(repo, contains("'link_daily_report_attendance_evidence'"));
    expect(repo, contains('loadAttendanceEvidence'));
    expect(page, contains("'出勤確認写真'"));
    expect(page, contains("'出勤確認写真一覧'"));
    expect(page, contains('InteractiveViewer'));
  });

  test('Japan timezone is explicit for daily selection and evidence linking', () {
    final sql = File(
      'supabase/migrations/'
      '20261002004444_fix_attendance_selection_japan_timezone.sql',
    ).readAsStringSync();
    expect(sql, contains("at time zone 'Asia/Tokyo'"));
    expect(sql, contains("v_today:=(now() at time zone v_timezone)::date"));
  });
}
