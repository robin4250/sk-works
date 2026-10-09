import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

Map<String, dynamic> row({String? state}) => {
  'id': 'statement', 'company_name': '保存会社', 'worker_name': '保存社員',
  'period_start': '2026-09-01', 'period_end': '2026-09-30',
  'gross_pay': 300000, 'deductions': 20000, 'net_pay': 280000,
  if (state != null) 'workflow_state': state,
  'review_confirmed': true,
  'detail': {'基本給': 300000, '使用料率': '保存値', 'payment_date': '2026-10-25'},
};

void main() {
  test('manager draft keeps row confirmation and separate status takes priority', () {
    final managerRow = row(state: 'draft');
    expect(payrollStatementFromRow(managerRow, null).reviewConfirmed, isTrue);
    expect(
      payrollStatementFromRow(managerRow, {'review_confirmed': false})
          .reviewConfirmed,
      isFalse,
    );
  });
  test('self and manager parser prefer saved row name then saved detail name', () {
    for (final name in [null, '', '   ']) {
      final saved = row(state: 'finalized')..['company_name'] = name;
      (saved['detail'] as Map)['company_name'] = '確定時会社';
      expect(payrollStatementFromRow(saved, null).companyName, '確定時会社');
    }
    final saved = row(state: 'finalized');
    (saved['detail'] as Map)['company_name'] = '明細内会社';
    expect(payrollStatementFromRow(saved, null).companyName, '保存会社');
  });
  test('finalized and unknown legacy rows keep saved results and confirmation', () {
    for (final state in ['finalized', 'issued', null]) {
      final saved = payrollStatementFromRow(row(state: state), {'review_confirmed': false});
      final shown = payrollStatementWithDraftReview(saved, confirmed: false, draftCompanyName: '現在会社');
      expect(identical(saved, shown), isTrue);
      expect(shown.companyName, '保存会社');
      expect(shown.reviewConfirmed, isTrue);
      expect(shown.netPay, 280000);
      expect(shown.detail['使用料率'], '保存値');
      expect(shown.detail['payment_date'], '2026-10-25');
    }
  });
  test('only explicitly draft row uses current review while preserving calculations', () {
    final saved = payrollStatementFromRow(row(state: 'draft'), {'review_confirmed': false});
    expect(saved.reviewConfirmed, isFalse);
    final shown = payrollStatementWithDraftReview(saved, confirmed: true);
    expect(shown.reviewConfirmed, isTrue);
    expect(shown.workflowState, 'draft');
    expect(identical(shown.detail, saved.detail), isTrue);
    expect(shown.grossPay, saved.grossPay);
  });
  test('explicit detail workflow state works; revision and amounts do not infer draft', () {
    final explicit = row();
    (explicit['detail'] as Map)['workflow_state'] = 'draft';
    expect(payrollStatementFromRow(explicit, null).isDraft, isTrue);
    final unknown = row()..['revision'] = 1;
    expect(payrollStatementFromRow(unknown, null).isDraft, isFalse);
  });
}
