import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_approval_repository.dart';

void main() {
  final approval = <String, dynamic>{
    'approver_user_id': 'person', 'status': 'approved',
    'approved_at': '2026-10-09T01:00:00Z',
  };
  final name = <String, dynamic>{
    'invoice_id': 'invoice', 'user_id': 'person', 'status': 'approved',
    'approved_at': '2026-10-09T10:00:00+09:00', 'snapshot_surname': '斉藤',
    'draft_surname': '斎藤', 'can_set_surname': true,
  };
  test('snapshot binds exact invoice, approver and actual instant', () {
    final result = InvoiceStampSurnameMetadata.match('invoice', approval, name);
    expect(result.snapshotSurname, '斉藤');
    expect(result.draftSurname, isNull);
    expect(result.canSet, isFalse);
    for (final changed in [
      {...name, 'invoice_id': 'another'},
      {...name, 'user_id': 'another'},
      {...name, 'status': 'pending'},
      {...name, 'approved_at': '2026-10-09T01:01:00Z'},
      {...name, 'approved_at': null},
    ]) {
      expect(() => InvoiceStampSurnameMetadata.match('invoice', approval, changed), throwsA(isA<InvoiceStampSurnameReadException>()));
    }
  });
  test('cancel/reapprove between RPCs never attaches a new surname to an old time', () {
    final newer = {...name, 'approved_at': '2026-10-09T01:02:00Z', 'snapshot_surname': '斎藤'};
    expect(() => InvoiceStampSurnameMetadata.match('invoice', approval, newer), throwsA(isA<InvoiceStampSurnameReadException>()));
  });
  test('genuinely unconfigured snapshots retain legacy display without inventing a surname', () {
    final result = InvoiceStampSurnameMetadata.match('invoice', approval, {...name, 'snapshot_surname': null});
    expect(result.snapshotSurname, isNull);
    expect(result.canSet, isFalse);
    expect(InvoiceStampSurnameMetadata.match('invoice', approval, null).snapshotSurname, isNull);
    expect(InvoiceStampSurnameMetadata.match('invoice', {...approval, 'approved_at': null}, {...name, 'approved_at': null, 'snapshot_surname': null}).snapshotSurname, isNull);
  });
  test('draft editing requires pending rows on both RPCs with no approval time', () {
    final pending = {...approval, 'status': 'pending', 'approved_at': null};
    final draft = {...name, 'status': 'pending', 'approved_at': null, 'snapshot_surname': null};
    final result = InvoiceStampSurnameMetadata.match('invoice', pending, draft);
    expect(result.draftSurname, '斎藤');
    expect(result.canSet, isTrue);
    expect(result.snapshotSurname, isNull);
    expect(() => InvoiceStampSurnameMetadata.match('invoice', pending, name), throwsA(isA<InvoiceStampSurnameReadException>()));
    expect(() => InvoiceStampSurnameMetadata.match('invoice', approval, draft), throwsA(isA<InvoiceStampSurnameReadException>()));
    expect(InvoiceStampSurnameMetadata.match('invoice', pending, {...draft, 'can_set_surname': false}).canSet, isFalse);
    expect(InvoiceStampSurnameMetadata.match('invoice', pending, null).canSet, isFalse);
  });
}
