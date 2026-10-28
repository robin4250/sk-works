import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/shift_draft_request.dart';

void main() {
  ShiftDraftRequest draft({String company = 'c', String worker = 'w',
      String? site = 's', bool holiday = false, int start = 480, int end = 1020,
      int revision = 0, DateTime? date}) => ShiftDraftRequest(companyId: company,
    workerId: worker, siteId: site, workDate: date ?? DateTime(2026, 10, 26),
    holiday: holiday, night: false, startMinute: start, endMinute: end,
    checkLate: true, checkEarly: true, revision: revision);

  test('normal and overnight plans keep the correct calendar relationship', () {
    expect(draft().validate(), isNull);
    final overnight = draft(start: 1320, end: 360);
    expect(overnight.validate(), isNull);
    expect(overnight.endsNextDay, isTrue);
    expect(draft().endsNextDay, isFalse);
  });
  test('rejects invalid identity, times, site and revision', () {
    expect(draft(company: '').validate(), isNotNull);
    expect(draft(worker: '').validate(), isNotNull);
    expect(draft(site: null).validate(), isNotNull);
    expect(draft(start: 500, end: 500).validate(), isNotNull);
    expect(draft(start: -1).validate(), isNotNull);
    expect(draft(end: 1440).validate(), isNotNull);
    expect(draft(revision: -1).validate(), isNotNull);
    expect(draft(date: DateTime(2026, 10, 26, 1)).validate(), isNotNull);
  });
  test('holiday does not require a workplace or time', () {
    expect(draft(site: null, holiday: true).validate(), isNull);
    expect(draft(company: '', holiday: true).validate(), isNotNull);
  });
}
