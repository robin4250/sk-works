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
      '登録済み・期限未入力',
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
      '口座情報を確認',
    );
    expect(
      workerDocumentDisplayStatus(
        {...required, 'is_required': false},
        {'status': 'submitted'},
      ).complete,
      true,
    );
  });
  test('multi-photo evidence uses the canonical parser and rejects malformed lists', () {
    for (final row in [
      {
        'status': 'submitted',
        'attachment_paths': ['retained/a', 'retained/b'],
      },
      {'status': 'submitted', 'attachment_path': 'retained/a'},
    ]) {
      expect(workerDocumentDisplayStatus(required, row).complete, true);
    }
    for (final paths in [
      42,
      ['a', 'a'],
      [' '],
      [null],
    ]) {
      expect(
        workerDocumentDisplayStatus(required, {
          'status': 'submitted',
          'attachment_path': 'retained/legacy',
          'attachment_paths': paths,
        }).complete,
        false,
      );
    }
    expect(
      workerDocumentDisplayStatus(
        {...required, 'expiry_required': true},
        {
          'status': 'submitted',
          'attachment_paths': ['a'],
          'expires_at': '2026-02-30',
        },
      ).complete,
      false,
    );
    expect(
      workerDocumentDisplayStatus(
        {...required, 'expiry_required': true},
        {
          'status': 'submitted',
          'attachment_paths': ['a'],
          'expires_at': '2026-10-30',
        },
        today: DateTime(2026, 10, 31),
      ).label,
      '期限切れ',
    );
    expect(
      workerDocumentDisplayStatus(
        {'name': '銀行口座情報'},
        {'status': 'submitted'},
        bankRegistered: true,
      ).complete,
      true,
    );
  });
  test(
    'bank evidence is independent of an absent or stale document status row',
    () {
      for (final row in [
        null,
        {'status': 'missing'},
        {'status': 'expired'},
      ]) {
        expect(
          workerDocumentDisplayStatus(
            {'name': '銀行口座情報'},
            row,
            bankRegistered: true,
          ).complete,
          true,
        );
        expect(
          workerDocumentDisplayStatus({'name': '銀行口座情報'}, row).label,
          '口座情報を確認',
        );
      }
    },
  );
}
