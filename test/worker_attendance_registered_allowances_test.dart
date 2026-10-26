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
Map<String, Object?> row(Object? saved, {String id = report, String user = worker}) => {
  'report_id': id, 'worker_id': user, 'company_allowance_selections': saved,
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
}
