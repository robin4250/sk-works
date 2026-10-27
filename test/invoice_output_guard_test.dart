import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_output_guard.dart';

void main() {
  const one = InvoiceOutputIdentity(invoiceId: 'one', revision: 'r1');
  const two = InvoiceOutputIdentity(invoiceId: 'two', revision: 'r2');
  test('checks server twice for every invoice before handoff', () async {
    var checks = 0;
    var handed = false;
    final guard = InvoiceOutputGuard((ids) async {
      checks++;
      return ids.map((i) => InvoiceOutputPermit(invoiceId: i.invoiceId, revision: i.revision, allowed: true)).toList();
    });
    await guard.run([one, two], () async => 'bytes', (bytes) async { handed = bytes == 'bytes'; });
    expect(checks, 2);
    expect(handed, isTrue);
  });
  test('denies if revision becomes stale while bytes are built', () async {
    var checks = 0;
    var handed = false;
    final guard = InvoiceOutputGuard((ids) async {
      checks++;
      return [InvoiceOutputPermit(invoiceId: 'one', revision: checks == 1 ? 'r1' : 'r2', allowed: true)];
    });
    await expectLater(guard.run([one], () async => 'bytes', (_) async { handed = true; }), throwsA(isA<InvoiceOutputDenied>()));
    expect(handed, isFalse);
  });
  test('fails closed on denial, missing or duplicate responses and network failure', () async {
    for (final check in <InvoicePermitCheck>[
      (_) async => [const InvoiceOutputPermit(invoiceId: 'one', revision: 'r1', allowed: false)],
      (_) async => [],
      (_) async => [const InvoiceOutputPermit(invoiceId: 'one', revision: 'r1', allowed: true), const InvoiceOutputPermit(invoiceId: 'one', revision: 'r1', allowed: true)],
      (_) async => throw StateError('offline'),
    ]) {
      var built = false;
      var handed = false;
      await expectLater(InvoiceOutputGuard(check).run([one], () async { built = true; return 'bytes'; }, (_) async { handed = true; }), throwsA(anything));
      expect(built, isFalse);
      expect(handed, isFalse);
    }
  });
  test('rejects missing revisions and repeated invoices before contacting server', () async {
    var checks = 0;
    final guard = InvoiceOutputGuard((_) async { checks++; return []; });
    for (final ids in <List<InvoiceOutputIdentity>>[[], [one, one], [const InvoiceOutputIdentity(invoiceId: 'one', revision: '')]]) {
      await expectLater(guard.run(ids, () async => 'bytes', (_) async {}), throwsA(isA<InvoiceOutputDenied>()));
    }
    expect(checks, 0);
  });
}
