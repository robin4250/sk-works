import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/site_contract_status.dart';

Map<String, dynamic> proposal(int revision, List<String> companies,
    {String start = '2026-10-01'}) => {
  'revision': revision,
  'terms': {'effective_from': start},
  'confirmations': [for (final company in companies) {'company_id': company}],
};
SiteContractStatus status(List<Map<String, dynamic>> proposals) =>
    SiteContractStatus.fromProposals(proposals, parentCompanyId: 'a',
      childCompanyId: 'b', today: DateTime(2026, 10, 15));
void main() {
  test('pending revision preserves current agreement', () {
    final value = status([proposal(2, ['a']), proposal(1, ['a', 'b'])]);
    expect(value.active!['revision'], 1);
    expect(value.label, '契約中・変更承認待ち');
  });
  test('duplicate confirmations cannot impersonate both parties', () {
    expect(status([proposal(1, ['a', 'a'])]).isContracted, false);
  });
  test('future approved revision does not replace effective agreement', () {
    final value = status([proposal(2, ['a', 'b'], start: '2026-11-01'),
      proposal(1, ['a', 'b'])]);
    expect(value.active!['revision'], 1);
    expect(value.scheduled!['revision'], 2);
    expect(value.label, '契約中・変更適用待ち');
  });
  test('old unconfirmed revisions are only history', () {
    expect(status([proposal(1, ['a']), proposal(2, ['a', 'b'])]).pending, isNull);
  });
}
