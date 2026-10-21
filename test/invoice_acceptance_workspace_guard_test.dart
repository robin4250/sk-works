import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_acceptance_workspace_guard.dart';

void main() {
  bool load({String id = 'saved-invoice', String? revision = '2026-10-21T00:00:00Z',
      bool explicit = false, bool repository = true}) =>
    InvoiceAcceptanceWorkspaceGuard.shouldLoad(invoiceId: id,
      sourceRevision: revision, hasExplicitSelection: explicit,
      repositoryAvailable: repository);

  test('saved invoice requires authorized workspace before PDF generation', () {
    expect(load(), isTrue);
    expect(() => load(repository: false), throwsStateError);
  });
  test('explicit saved or missing historical appendix remains caller-owned', () {
    expect(load(explicit: true, repository: false), isFalse);
    expect(load(explicit: true), isFalse);
  });
  test('local and synthetic calculations keep their existing output', () {
    for (final repository in [true, false]) {
      expect(load(id: '', repository: repository), isFalse);
      expect(load(revision: null, repository: repository), isFalse);
      expect(load(id: '', revision: null, repository: repository), isFalse);
    }
  });
}
