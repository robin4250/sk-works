import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/shift_draft_gateway.dart';
import 'package:sk_works/features/shifts/shift_draft_request.dart';

void main() {
  final draft = ShiftDraftRequest(companyId: 'c', workerId: 'w', siteId: 's',
    workDate: DateTime(2026, 10, 26), holiday: false, night: false,
    startMinute: 480, endMinute: 1020, checkLate: true, checkEarly: true, revision: 2);
  test('publication requires an exact server receipt for the saved revision', () async {
    final gateway = ShiftDraftGateway((name, params) async {
      expect(name, 'publish_shift_drafts');
      expect(params['p_company'], 'c');
      return [{'worker_id': 'w', 'work_date': '2026-10-26', 'revision': 2}];
    });
    await gateway.publish([draft]);
    final bad = ShiftDraftGateway((_, _) async => [
      {'worker_id': 'w', 'work_date': '2026-10-26', 'revision': 3}]);
    await expectLater(bad.publish([draft]), throwsFormatException);
    await expectLater(gateway.publish([draft, draft]), throwsFormatException);
  });
  test('validates the server receipt against saved worker, date and revision', () async {
    final gateway = ShiftDraftGateway((name, params) async {
      expect(name, 'save_shift_drafts');
      expect(params['p_company'], 'c');
      return [{'worker_id': 'w', 'work_date': '2026-10-26', 'revision': 3}];
    });
    await gateway.save([draft]);
    final wrong = ShiftDraftGateway((_, _) async => [
      {'worker_id': 'w', 'work_date': '2026-10-26', 'revision': 2}]);
    await expectLater(wrong.save([draft]), throwsFormatException);
  });
  test('rejects duplicates before contacting the server', () async {
    var calls = 0;
    final gateway = ShiftDraftGateway((_, _) async { calls++; return []; });
    await expectLater(gateway.save([draft, draft]), throwsFormatException);
    expect(calls, 0);
  });
  test('loads a bounded month and rejects incomplete or duplicate data', () async {
    final row = {'worker_id': 'w', 'work_date': '2026-10-26', 'site_id': 's',
      'holiday': false, 'night': false, 'start_minute': 480, 'end_minute': 1020,
      'check_late': true, 'check_early': true, 'revision': 3};
    final gateway = ShiftDraftGateway((name, params) async {
      expect(name, 'list_shift_drafts');
      expect(params['p_from'], '2026-10-01');
      expect(params['p_to'], '2026-10-31');
      return [row];
    });
    final drafts = await gateway.listMonth('c', DateTime(2026, 10, 20));
    expect(drafts.single.workerId, 'w');
    expect(drafts.single.revision, 3);
    final invalid = ShiftDraftGateway((_, _) async => [row, row]);
    await expectLater(invalid.listMonth('c', DateTime(2026, 10)), throwsFormatException);
    final incomplete = ShiftDraftGateway((_, _) async => null);
    await expectLater(incomplete.listMonth('c', DateTime(2026, 10)), throwsFormatException);
  });
}
