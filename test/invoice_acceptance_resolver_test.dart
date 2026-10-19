import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_acceptance_resolver.dart';

void main() {
  Map<String, dynamic> workspace() => {
    'source_locked': false,
    'source_blocked': false,
    'source_changed': false,
    'attachment': null,
    'defaults': {
      'version': 1,
      'kind': 'acceptance',
      'month': '2026-01',
      'issuer': {'name': '受注会社'},
      'counterparty': {'name': '発注会社'},
      'company_seal_snapshot': {
        'version': 1,
        'style': 'legacy',
        'name': '受注会社',
      },
      'company_seal_enabled': false,
      'total_amount_yen': 110000,
    },
    'template': {
      'acceptance_text': '{order_date}の注文を承諾',
      'issuer': {'name': '別会社'},
      'total_amount_yen': 1,
    },
  };
  final date = DateTime(2026, 2, 5);

  test(
    'unsaved draft uses authorized source and prose without mutating input',
    () {
      final data = workspace();
      final result = InvoiceAcceptanceResolver.resolve(data, issueDate: date)!;
      expect(result.payload['order_date'], '2025-12-15');
      expect(result.payload['issue_date'], '2026-02-05');
      expect(result.payload['acceptance_text'], '2025-12-15の注文を承諾');
      expect(result.payload['issuer'], {'name': '受注会社'});
      expect(result.payload['total_amount_yen'], 110000);
      expect((data['defaults'] as Map).containsKey('issue_date'), false);
      expect(data['attachment'], isNull);
    },
  );
  test('saved appendix wins over current template and issue date', () {
    final data = workspace();
    final saved = InvoiceAcceptanceResolver.resolve(data, issueDate: date)!;
    data['attachment'] = {'version': 7, 'payload': saved.payload};
    data['source_locked'] = true;
    final result = InvoiceAcceptanceResolver.resolve(data, issueDate: null)!;
    expect(result.version, 7);
    expect(result.payload, saved.payload);
  });
  test('historical missing appendix remains absent', () {
    final data = workspace()..['source_locked'] = true;
    expect(InvoiceAcceptanceResolver.resolve(data, issueDate: null), isNull);
  });
  test('changed source and unknown readiness cannot silently generate', () {
    for (final key in ['source_changed', 'source_blocked']) {
      final data = workspace()..[key] = true;
      expect(
        () => InvoiceAcceptanceResolver.resolve(data, issueDate: date),
        throwsStateError,
      );
    }
    final data = workspace()..remove('source_locked');
    expect(
      () => InvoiceAcceptanceResolver.resolve(data, issueDate: date),
      throwsStateError,
    );
    expect(
      () => InvoiceAcceptanceResolver.resolve(workspace(), issueDate: null),
      throwsStateError,
    );
  });
}
