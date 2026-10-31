import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_display_status.dart';

void main() {
  final required = <String, dynamic>{'name': '雇用保険被保険者証', 'is_required': true};
  test('submission metadata cannot replace required attachment evidence', () {
    final row = <String, dynamic>{'status': 'submitted'};
    expect(workerDocumentDisplayStatus(required, row).label, '添付待ち');
    expect(workerDocumentDisplayStatus(required, row).complete, false);
    expect(row, {'status': 'submitted'});
    expect(
      workerDocumentDisplayStatus(required, {
        ...row,
        'attachment_path': 'retained/original',
      }).complete,
      true,
    );
    expect(
      workerDocumentDisplayStatus(required, {
        ...row,
        'attachment_path': '  ',
      }).complete,
      false,
    );
  });
  test('expiry and unresolved status remain incomplete while bank is a separate record', () {
    final row = {'status': 'verified', 'attachment_path': 'retained/original'};
    expect(
      workerDocumentDisplayStatus({
        ...required,
        'expiry_required': true,
      }, row).label,
      '提出済み・期限未入力',
    );
    expect(
      workerDocumentDisplayStatus(
        required,
        row,
        effectiveStatus: 'expired',
      ).complete,
      false,
    );
    expect(
      workerDocumentDisplayStatus(required, {
        'status': 'unknown',
        'attachment_path': 'retained/original',
      }).complete,
      false,
    );
    expect(
      workerDocumentDisplayStatus(
        {'name': '銀行口座情報', 'is_required': true},
        {'status': 'submitted'},
      ).label,
      '登録済み',
    );
    expect(
      workerDocumentDisplayStatus(
        {...required, 'is_required': false},
        {'status': 'submitted'},
      ).complete,
      true,
    );
  });
}
