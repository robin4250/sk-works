import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/shift_draft_gateway.dart';
import 'package:sk_works/features/shifts/shift_draft_request.dart';

void main() {
  final draft = ShiftDraftRequest(companyId: 'c', workerId: 'w', siteId: 's',
    workDate: DateTime(2026, 10, 26), holiday: false, night: false,
    startMinute: 480, endMinute: 1020, checkLate: true, checkEarly: true, revision: 2);
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
}
