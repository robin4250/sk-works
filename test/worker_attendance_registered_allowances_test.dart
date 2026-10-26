import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/worker_attendance_registered_allowances.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';

const report = '00000000-0000-0000-0000-000000000001';
const worker = '00000000-0000-0000-0000-000000000002';
Map<String, Object?> selection({String name = '保存済み共通手当', String unit = 'day'}) => {
  'origin': 'company_common',
  'id': '00000000-0000-0000-0000-000000000003',
  'generation': null, 'registration_version': 7,
  'name_snapshot': name, 'unit': unit,
};
Map<String, Object?> row(Object? saved, {String id = report, String user = worker, String status = 'signed'}) => {
  'report_id': id, 'worker_id': user, 'company_allowance_selections': saved, 'daily_reports': {'status': status},
};
Map<String, Object?> choices(List<Object?> items) => {'contract_version': 1, 'items': items};
void main() {
  test('saved identity, old name and version survive catalog-independent display', () {
    final result = workerAttendanceRegisteredAllowances([row(choices([selection()]))],
        reportIds: {report}, workerId: worker);
    final saved = result[report]!.single;
    expect(saved.id, '00000000-0000-0000-0000-000000000003');
    expect(saved.registrationVersion, 7);
    expect(saved.nameSnapshot, '保存済み共通手当');
    final day = WorkerAttendanceDay(date: DateTime(2026, 10, 26),
        allowanceNames: [saved.nameSnapshot, '自由記入'],
        allowanceUnits: const {'自由記入': '回'}, companyAllowanceSelections: [saved]);
    expect(day.allowanceDisplayText(saved.nameSnapshot), '保存済み共通手当');
    expect(day.allowanceDisplayText('自由記入'), '自由記入1回');
  });
  test('hour choice shows its name without inventing one paid hour', () {
    final saved = workerAttendanceRegisteredAllowances([row(choices([selection(unit: 'hour')]))],
        reportIds: {report}, workerId: worker)[report]!.single;
    final day = WorkerAttendanceDay(date: DateTime(2026, 10, 26),
        companyAllowanceSelections: [saved], allowanceUnits: {saved.nameSnapshot: '時間'});
    expect(day.allowanceDisplayText(saved.nameSnapshot), saved.nameSnapshot);
  });
  test('legacy null and explicit empty choices never invent registered names', () {
    expect(workerAttendanceRegisteredAllowances([row(null)], reportIds: {report}, workerId: worker)[report], isEmpty);
    expect(workerAttendanceRegisteredAllowances([row(choices([]))], reportIds: {report}, workerId: worker)[report], isEmpty);
  });
  test('unlinked report and another worker are rejected', () {
    for (final invalid in [row(null, id: 'unlinked'), row(null, user: 'someone-else')]) {
      expect(() => workerAttendanceRegisteredAllowances([invalid], reportIds: {report}, workerId: worker), throwsFormatException);
    }
  });
  test('duplicate roster and malformed or duplicate identity fail visibly', () {
    for (final invalid in [
      [row(null), row(null)],
      [row(choices([selection(), selection()]))],
      [row(choices([selection(name: '')]))],
      [row({'contract_version': 2, 'items': []})],
    ]) {
      expect(() => workerAttendanceRegisteredAllowances(invalid, reportIds: {report}, workerId: worker), throwsFormatException);
    }
  });
  test('actual Supabase read connects only linked worker snapshots to their work dates', () async {
    const draftReport = '00000000-0000-0000-0000-000000000005';
    const otherReport = '00000000-0000-0000-0000-000000000004';
    final seen = <Uri>[];
    final client = SupabaseClient('https://fixture.invalid', 'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      seen.add(request.url);
      final path = request.url.path;
      Object result;
      if (path.endsWith('/attendance_entries')) {
        expect(request.url.queryParameters['worker_id'], 'eq.$worker');
        expect(request.url.queryParametersAll['work_date'],
            containsAll(['gte.2026-10-01', 'lt.2026-11-01']));
        expect(request.url.queryParameters['select'], contains('source_report_id'));
        result = [
          {'id': 'entry-one', 'source_report_id': report, 'work_date': '2026-10-26',
            'site_id': 'site', 'base_man_days': 1, 'allowance_amount': 0,
            'allowance_names': ['自由記入'], 'sites': {'name': '合成現場'}},
          {'id': 'entry-draft', 'source_report_id': draftReport, 'work_date': '2026-10-28',
            'site_id': 'site', 'base_man_days': 1, 'allowance_amount': 0,
            'allowance_names': ['既存確定出勤の手当'], 'sites': {'name': '合成現場'}},
          {'id': 'entry-two', 'source_report_id': otherReport, 'work_date': '2026-10-27',
            'site_id': 'site', 'base_man_days': 1, 'allowance_amount': 0,
            'allowance_names': [], 'sites': {'name': '合成現場'}},
        ];
      } else if (path.endsWith('/daily_report_workers')) {
        expect(request.url.queryParameters['worker_id'], 'eq.$worker');
        expect(request.url.queryParameters['report_id'], contains(report));
        expect(request.url.queryParameters['report_id'], contains(otherReport));
        expect(request.url.queryParameters['select'], 'report_id,worker_id,company_allowance_selections,daily_reports!inner(status)');
        expect(request.url.queryParameters['daily_reports.status'], 'eq.signed');
        result = [row(choices([selection(name: '登録当時の名前')])),
          row(choices([selection(name: '翌日の手当')]), id: otherReport),
          row(choices([selection(name: '手直し中の未確定手当')]), id: draftReport, status: 'draft')];
      } else if (path.endsWith('/attendance_verifications') || path.endsWith('/paid_leave_requests')) {
        result = [];
      } else if (path.endsWith('/paid_leave_worker_summary')) {
        result = {'granted_days': 0};
      } else if (path.endsWith('/my_attendance_allowance_units')) {
        result = {'現在の改名後': '時間', '自由記入': '回'};
      } else {
        throw StateError('Unexpected read: $path');
      }
      return http.Response(jsonEncode(result), 200, headers: {'content-type': 'application/json'});
    }));
    try {
      final month = await WorkerAttendanceSheetRepository.forClient(client)
          .loadMonth(DateTime(2026, 10), workerId: worker);
      final first = month.days[DateTime(2026, 10, 26)]!;
      final second = month.days[DateTime(2026, 10, 27)]!;
      expect(first.allowanceNames, ['登録当時の名前', '自由記入']);
      expect(first.companyAllowanceSelections.single.registrationVersion, 7);
      expect(first.allowanceNames, isNot(contains('現在の改名後')));
      expect(first.allowanceNames, isNot(contains('翌日の手当')));
      expect(second.allowanceNames, ['翌日の手当']);
      final draftDay = month.days[DateTime(2026, 10, 28)]!;
      expect(draftDay.allowanceNames, ['既存確定出勤の手当']);
      expect(draftDay.companyAllowanceSelections, isEmpty);
      expect(month.days.length, 3);
      expect(seen.where((uri) => uri.path.endsWith('/daily_report_workers')).length, 1);
    } finally {
      await client.dispose();
    }
  });

}
