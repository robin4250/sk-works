import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/site_payment_certificates_repository.dart';

void main() {
  Map<String, dynamic> proposal(int revision, List<String> companies) => {
    'id': 'proposal-$revision', 'revision': revision,
    'confirmations': [for (final company in companies) {'company_id': company}],
  };
  Map<String, dynamic> workspace(List<Map<String, dynamic>> proposals) => {
    'parent_company_id': 'parent', 'child_company_id': 'child', 'proposals': proposals,
  };
  test('old confirmed revision cannot replace unconfirmed latest revision', () {
    expect(ConfirmedSitePayment.latestConfirmed(workspace([
      proposal(1, ['parent', 'child']), proposal(2, ['parent']),
    ])), isNull);
  });
  test('both exact companies must confirm the same latest revision', () {
    expect(ConfirmedSitePayment.latestConfirmed(workspace([
      proposal(3, ['parent', 'unrelated']),
    ])), isNull);
    expect(ConfirmedSitePayment.latestConfirmed(workspace([
      proposal(2, ['parent']), proposal(3, ['parent', 'child']),
    ]))?['id'], 'proposal-3');
  });
  test('duplicate confirmation by one company is not mutual agreement', () {
    expect(ConfirmedSitePayment.latestConfirmed(workspace([
      proposal(1, ['parent', 'parent']),
    ])), isNull);
  });
}
