import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/site_payment_terms_comparison.dart';

Map<String, dynamic> proposal(String company, int revision, Map<String, dynamic> terms) =>
    {'proposed_company_id': company, 'revision': revision, 'terms': terms,
      'confirmations': [{'company_id': 'parent'}, {'company_id': 'child'}]};
SitePaymentTermsComparison compare(List<Map<String, dynamic>> proposals) =>
    SitePaymentTermsComparison.fromWorkspace({'parent_company_id': 'parent',
      'child_company_id': 'child', 'proposals': proposals});

void main() {
  test('confirmation by both companies never fabricates a child proposal', () {
    final result = compare([proposal('parent', 1, {'final_amount_yen': 100})]);
    expect(result.bothShared, false);
    expect(result.child, isNull);
    expect(result.display(result.child, 'final_amount_yen'), '未共有');
    expect(result.differs('final_amount_yen'), false);
  });
  test('uses highest revision from each company even if input is unordered', () {
    final result = compare([proposal('parent', 1, {'final_amount_yen': 50}),
      proposal('child', 2, {'final_amount_yen': 100}),
      proposal('unrelated', 9, {'final_amount_yen': 900}),
      proposal('parent', 3, {'final_amount_yen': 100})]);
    expect(result.parent!['revision'], 3);
    expect(result.child!['revision'], 2);
    expect(result.differs('final_amount_yen'), false);
  });
  test('equal totals do not mask basis, tax or welfare differences', () {
    final result = compare([proposal('parent', 1, {
      'base_amount_yen': 100, 'tax_included': true, 'tax_rate': 10,
      'adjustments': [{'name': '福利厚生費', 'amount_yen': 10, 'direction': 'deduction'}],
      'final_amount_yen': 90}), proposal('child', 2, {
      'base_amount_yen': 80, 'tax_included': false, 'tax_rate': 0,
      'adjustments': [{'name': '福利厚生費', 'amount_yen': 10, 'direction': 'addition'}],
      'final_amount_yen': 90})]);
    for (final key in ['base_amount_yen', 'tax_included', 'tax_rate', 'adjustments']) {
      expect(result.differs(key), true);
    }
    expect(result.differs('final_amount_yen'), false);
    expect(result.display(result.parent, 'adjustments'), contains('控除 10円'));
  });
  test('addition order and numeric representation do not create false mismatches', () {
    final first = {'name': '工事', 'direction': 'addition', 'amount_yen': 100};
    final second = {'name': '福利厚生費', 'direction': 'deduction', 'amount_yen': 20};
    final result = compare([proposal('parent', 1, {'base_amount_yen': 100,
      'adjustments': [first, second]}), proposal('child', 2,
      {'base_amount_yen': 100.0, 'adjustments': [second, first]})]);
    expect(result.differs('base_amount_yen'), false);
    expect(result.differs('adjustments'), false);
  });
  test('extra names, amounts and duplicate rows remain significant', () {
    final item = {'name': '01', 'direction': 'addition', 'amount_yen': 10};
    final result = compare([proposal('parent', 1, {'adjustments': [item]}),
      proposal('child', 2, {'adjustments': [item, item]})]);
    expect(result.differs('adjustments'), true);
    final renamed = compare([proposal('parent', 1, {'adjustments': [item]}),
      proposal('child', 2, {'adjustments': [{...item, 'name': '1'}]})]);
    expect(renamed.differs('adjustments'), true);
  });
}
