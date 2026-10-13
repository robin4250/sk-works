import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/group_checkout_repository.dart';

Map<String, Object?> row(String source, String worker, {String date = '2026-10-31', String? out}) => {
  'source_clock_in_id': source, 'worker_id': worker, 'worker_name': worker,
  'work_date': date, 'clock_out_at': out,
};

void main() {
  test('capability requires explicit enabled, version and current company', () {
    expect(groupCheckoutEnabled({'version': 1, 'company_id': 'own', 'group_checkout_enabled': true}, 'own'), isTrue);
    expect(groupCheckoutEnabled({'version': 1, 'company_id': 'other', 'group_checkout_enabled': true}, 'own'), isFalse);
    expect(groupCheckoutEnabled({'company_id': 'own', 'group_checkout_enabled': true}, 'own'), isFalse);
    expect(groupCheckoutEnabled({'version': 1, 'company_id': 'own', 'group_checkout_enabled': 'true'}, 'own'), isFalse);
    expect(groupCheckoutEnabled(null, 'own'), isFalse);
  });
  test('overnight roster preserves owning month and early leave', () {
    final rows = parseGroupCheckoutCandidates([
      row('a', 'one'), row('b', 'two', out: '2026-11-01T01:00:00+09:00'),
    ], DateTime(2026, 10, 31));
    expect(rows.first.isOpen, isTrue);
    expect(rows.last.isOpen, isFalse);
    expect(rows.last.workDate, DateTime(2026, 10, 31));
    expect(() => rows.clear(), throwsUnsupportedError);
  });
  test('wrong month, ambiguous shift and malformed checkout never become candidates', () {
    final day = DateTime(2026, 10, 31);
    expect(() => parseGroupCheckoutCandidates([row('a', 'one', date: '2026-11-01')], day), throwsStateError);
    expect(() => parseGroupCheckoutCandidates([row('a', 'one'), row('b', 'one')], day), throwsStateError);
    expect(() => parseGroupCheckoutCandidates([row('a', 'one', out: 'bad')], day), throwsStateError);
    expect(() => parseGroupCheckoutCandidates([row('a', 'one', date: '2026-02-31')], DateTime(2026, 3, 3)), throwsStateError);
  });
  test('request snapshot remains stable for unordered retries and later selection mutation', () {
    final selection = <String>{'b', 'a'};
    final request = GroupCheckoutRequest(anchorId: 'anchor', sourceIds: selection);
    final token = request.token;
    selection.remove('b');
    expect(request.sourceIds, ['a', 'b']);
    expect(request.matches(['b', 'a']), isTrue);
    expect(request.matches(selection), isFalse);
    expect(request.token, token);
    expect(token, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(() => request.sourceIds.clear(), throwsUnsupportedError);
  });
}
