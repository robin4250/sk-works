import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/expense_cost_direction_v2_candidate.dart';
import 'package:sk_works/domain/expense_cost_snapshot.dart';

const _company = '11111111-1111-1111-1111-111111111111';
const _document = '22222222-2222-2222-2222-222222222222';
const _subject = '33333333-3333-3333-3333-333333333333';
const _claim = 'abcdefab-4444-4444-4444-444444444444';
ExpenseCostContext _context(ExpenseCostDocumentKind kind) => ExpenseCostContext(
  kind: kind,
  companyId: _company,
  documentId: _document,
  subjectId: _subject,
  month: '2026-10',
  documentRevision: 3,
);
Map<String, dynamic> _snapshot(ExpenseCostDocumentKind kind) => {
  'version': 2,
  'contract': 'expense_cost_direction',
  'document_kind': kind.name,
  'direction': kind == ExpenseCostDocumentKind.invoice
      ? 'addition'
      : 'deduction',
  'company_id': _company,
  'document_id': _document,
  'subject_id': _subject,
  'month': '2026-10',
  'document_revision': 3,
  'amount_yen': 1000,
  'claims': [
    {'id': _claim, 'revision': 2, 'amount_yen': 1000},
  ],
};
ExpenseCostDirectionV2Candidate _parse(
  Map<String, dynamic> raw,
  ExpenseCostDocumentKind kind,
) => ExpenseCostDirectionV2Candidate.parse(raw, expected: _context(kind));
Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

void main() {
  test(
    'user example: expense-only statement preserves a signed net of minus 1000',
    () {
      final cost = _parse(
        _snapshot(ExpenseCostDocumentKind.paymentCertificate),
        ExpenseCostDocumentKind.paymentCertificate,
      );
      expect(cost.signedDeltaYen, -1000);
      cost.verifyPaymentTotals(
        baseGrossYen: 0,
        otherDeductionsYen: 0,
        savedGrossYen: 0,
        savedDeductionsYen: 1000,
        savedNetYen: -1000,
      );
      for (final wrongNet in [0, 1000]) {
        expect(
          () => cost.verifyPaymentTotals(
            baseGrossYen: 0,
            otherDeductionsYen: 0,
            savedGrossYen: 0,
            savedDeductionsYen: 1000,
            savedNetYen: wrongNet,
          ),
          throwsStateError,
        );
      }
    },
  );

  test(
    '1000-yen payment expense deducts once, preserves gross and other deductions',
    () {
      final cost = _parse(
        _snapshot(ExpenseCostDocumentKind.paymentCertificate),
        ExpenseCostDocumentKind.paymentCertificate,
      );
      expect(cost.amountYen, 1000);
      expect(cost.signedDeltaYen, -1000);
      cost.verifyPaymentTotals(
        baseGrossYen: 20000,
        otherDeductionsYen: 500,
        savedGrossYen: 20000,
        savedDeductionsYen: 1500,
        savedNetYen: 18500,
      );
      for (final wrong in [
        [21000, 500, 20500], // former addition result
        [19000, 1500, 17500], // also deducted from gross
        [20000, 2500, 17500], // expense deducted twice
        [20000, 1500, 19500], // net fails to include deduction
      ]) {
        expect(
          () => cost.verifyPaymentTotals(
            baseGrossYen: 20000,
            otherDeductionsYen: 500,
            savedGrossYen: wrong[0],
            savedDeductionsYen: wrong[1],
            savedNetYen: wrong[2],
          ),
          throwsStateError,
        );
      }
    },
  );

  test('1000-yen invoice expense adds once after existing welfare and tax', () {
    final cost = _parse(
      _snapshot(ExpenseCostDocumentKind.invoice),
      ExpenseCostDocumentKind.invoice,
    );
    expect(cost.signedDeltaYen, 1000);
    // Existing work/welfare/tax aggregate is 23760 and stays untouched.
    cost.verifyInvoiceTotal(baseTotalYen: 23760, savedTotalYen: 24760);
    for (final wrong in [22760, 23760, 24860, 25760]) {
      expect(
        () =>
            cost.verifyInvoiceTotal(baseTotalYen: 23760, savedTotalYen: wrong),
        throwsStateError,
      );
    }
    expect(
      () => cost.verifyPaymentTotals(
        baseGrossYen: 20000,
        otherDeductionsYen: 0,
        savedGrossYen: 20000,
        savedDeductionsYen: 1000,
        savedNetYen: 19000,
      ),
      throwsStateError,
    );
  });

  test(
    'strict envelope rejects every absent or additional field, including supplied delta and settlement',
    () {
      final good = _snapshot(ExpenseCostDocumentKind.paymentCertificate);
      for (final key in good.keys) {
        final bad = _copy(good)..remove(key);
        expect(
          () => _parse(bad, ExpenseCostDocumentKind.paymentCertificate),
          throwsStateError,
          reason: key,
        );
      }
      for (final extra in [
        'signed_delta_yen',
        'settlement_method',
        'payroll',
        'unexpected',
      ]) {
        expect(
          () => _parse(
            _copy(good)..[extra] = -1000,
            ExpenseCostDocumentKind.paymentCertificate,
          ),
          throwsStateError,
        );
      }
    },
  );

  test(
    'unknown version, type, kind, reverse direction and exact context mismatch fail closed',
    () {
      final good = _snapshot(ExpenseCostDocumentKind.paymentCertificate);
      final changes = <String, List<Object?>>{
        'version': [1, 3, 2.0, '2', null],
        'contract': ['other', null],
        'document_kind': ['payroll', 'invoice', 'unknown'],
        'direction': ['addition', -1, null],
        'company_id': [_subject, null],
        'document_id': [_subject, null],
        'subject_id': [_document, null],
        'month': ['2026-11', '2026-10-01', null],
        'document_revision': [2, 4, 3.0, '3'],
        'amount_yen': [-1000, 1000.0, '1000', null],
        'claims': [{}, null],
      };
      for (final entry in changes.entries) {
        for (final value in entry.value) {
          expect(
            () => _parse(
              _copy(good)..[entry.key] = value,
              ExpenseCostDocumentKind.paymentCertificate,
            ),
            throwsStateError,
            reason: '${entry.key}=$value',
          );
        }
      }
    },
  );

  test(
    'positive claim amounts, integral revisions, UUID IDs and exact keys are required',
    () {
      final good = _snapshot(ExpenseCostDocumentKind.invoice);
      for (final row in <Map<String, Object?>>[
        {'id': _claim, 'revision': 0, 'amount_yen': 1000},
        {'id': _claim, 'revision': 2.0, 'amount_yen': 1000},
        {'id': '', 'revision': 2, 'amount_yen': 1000},
        {'id': 'unknown', 'revision': 2, 'amount_yen': 1000},
        {'id': _claim, 'revision': 2, 'amount_yen': 0},
        {'id': _claim, 'revision': 2, 'amount_yen': -1000},
        {'id': _claim, 'revision': 2, 'amount_yen': 1000.0},
        {'id': _claim, 'revision': 2},
        {
          'id': _claim,
          'revision': 2,
          'amount_yen': 1000,
          'direction': 'addition',
        },
      ]) {
        expect(
          () => _parse(
            _copy(good)..['claims'] = [row],
            ExpenseCostDocumentKind.invoice,
          ),
          throwsStateError,
        );
      }
      final duplicate = _copy(good)..['amount_yen'] = 2000;
      duplicate['claims'].add({
        'id': _claim.toUpperCase(),
        'revision': 2,
        'amount_yen': 1000,
      });
      expect(
        () => _parse(duplicate, ExpenseCostDocumentKind.invoice),
        throwsStateError,
      );
      expect(
        () => _parse(
          _copy(good)..['amount_yen'] = 999,
          ExpenseCostDocumentKind.invoice,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'immutable snapshot and scoped detail verification retain IDs, revisions and original amounts',
    () {
      final original = _snapshot(ExpenseCostDocumentKind.invoice);
      final before = jsonEncode(original);
      final cost = _parse(original, ExpenseCostDocumentKind.invoice);
      cost.verifyDetails(_copy(original));
      expect(jsonEncode(original), before);
      expect(
        () => cost.fields['direction'] = 'deduction',
        throwsUnsupportedError,
      );
      expect(() => cost.claims.clear(), throwsUnsupportedError);
      expect(() => cost.claims.first['revision'] = 3, throwsUnsupportedError);
      for (final change in [
        {'id': _subject, 'revision': 2, 'amount_yen': 1000},
        {'id': _claim, 'revision': 3, 'amount_yen': 1000},
      ]) {
        expect(
          () => cost.verifyDetails(_copy(original)..['claims'] = [change]),
          throwsStateError,
        );
      }
      expect(
        () => cost.verifyDetails(_copy(original)..['subject_id'] = _company),
        throwsStateError,
      );
      original['claims'].first['amount_yen'] = 999;
      expect(cost.amountYen, 1000);
      expect(cost.claims.first['amount_yen'], 1000);
    },
  );

  test(
    'zero expense and deductions exceeding gross retain exact signed net without clamping',
    () {
      final raw = _snapshot(ExpenseCostDocumentKind.paymentCertificate)
        ..['amount_yen'] = 0
        ..['claims'] = [];
      final zero = _parse(raw, ExpenseCostDocumentKind.paymentCertificate);
      zero.verifyPaymentTotals(
        baseGrossYen: 0,
        otherDeductionsYen: 0,
        savedGrossYen: 0,
        savedDeductionsYen: 0,
        savedNetYen: 0,
      );
      final cost = _parse(
        _snapshot(ExpenseCostDocumentKind.paymentCertificate),
        ExpenseCostDocumentKind.paymentCertificate,
      );
      cost.verifyPaymentTotals(
        baseGrossYen: 500,
        otherDeductionsYen: 0,
        savedGrossYen: 500,
        savedDeductionsYen: 1000,
        savedNetYen: -500,
      );
      cost.verifyPaymentTotals(
        baseGrossYen: 500,
        otherDeductionsYen: 700,
        savedGrossYen: 500,
        savedDeductionsYen: 1700,
        savedNetYen: -1200,
      );
      for (final wrongNet in [0, 500]) {
        expect(
          () => cost.verifyPaymentTotals(
            baseGrossYen: 500,
            otherDeductionsYen: 0,
            savedGrossYen: 500,
            savedDeductionsYen: 1000,
            savedNetYen: wrongNet,
          ),
          throwsStateError,
        );
      }
    },
  );

  test('signed net and deduction sum retain exact integer limits', () {
    const max = 9007199254740991;
    final raw = _snapshot(ExpenseCostDocumentKind.paymentCertificate)
      ..['amount_yen'] = max;
    raw['claims'].first['amount_yen'] = max;
    final cost = _parse(raw, ExpenseCostDocumentKind.paymentCertificate);
    cost.verifyPaymentTotals(
      baseGrossYen: 0,
      otherDeductionsYen: 0,
      savedGrossYen: 0,
      savedDeductionsYen: max,
      savedNetYen: -max,
    );
    expect(
      () => cost.verifyPaymentTotals(
        baseGrossYen: 0,
        otherDeductionsYen: 1,
        savedGrossYen: 0,
        savedDeductionsYen: max,
        savedNetYen: -max,
      ),
      throwsStateError,
    );
    for (final wrongNet in [-max - 1, max + 1]) {
      expect(
        () => cost.verifyPaymentTotals(
          baseGrossYen: 0,
          otherDeductionsYen: 0,
          savedGrossYen: 0,
          savedDeductionsYen: max,
          savedNetYen: wrongNet,
        ),
        throwsStateError,
      );
    }
    for (final negativeAmounts in [
      [-1, 0, 0, max],
      [0, -1, 0, max],
      [0, 0, -1, max],
      [0, 0, 0, -1],
    ]) {
      expect(
        () => cost.verifyPaymentTotals(
          baseGrossYen: negativeAmounts[0],
          otherDeductionsYen: negativeAmounts[1],
          savedGrossYen: negativeAmounts[2],
          savedDeductionsYen: negativeAmounts[3],
          savedNetYen: -max,
        ),
        throwsStateError,
      );
    }
  });

  test(
    'legacy v1 is unchanged, round trips verbatim and cannot be silently upgraded',
    () {
      final legacy = {
        'expense_extra_source_version': 1,
        'expense_extra_amount_yen': 1000,
        'expense_extra_claims': [
          {'id': _claim, 'revision': 2, 'amount_yen': 1000},
        ],
      };
      final before = jsonEncode(legacy);
      final v1 = ExpenseCostSnapshot.parse(legacy);
      expect(v1.fields, legacy);
      expect(v1.amountYen, 1000);
      expect(
        () => ExpenseCostDirectionV2Candidate.parse(
          legacy,
          expected: _context(ExpenseCostDocumentKind.paymentCertificate),
        ),
        throwsStateError,
      );
      expect(jsonEncode(legacy), before);
      expect(ExpenseCostSnapshot.parse({}).isCurrent, isFalse);
    },
  );

  test(
    'invalid expected scope and nonexact integer bounds cannot authorize a snapshot',
    () {
      final good = _snapshot(ExpenseCostDocumentKind.invoice);
      for (final context in [
        const ExpenseCostContext(
          kind: ExpenseCostDocumentKind.invoice,
          companyId: 'bad',
          documentId: _document,
          subjectId: _subject,
          month: '2026-10',
          documentRevision: 3,
        ),
        const ExpenseCostContext(
          kind: ExpenseCostDocumentKind.invoice,
          companyId: _company,
          documentId: _document,
          subjectId: _subject,
          month: '2026-13',
          documentRevision: 3,
        ),
        const ExpenseCostContext(
          kind: ExpenseCostDocumentKind.invoice,
          companyId: _company,
          documentId: _document,
          subjectId: _subject,
          month: '0000-01',
          documentRevision: 0,
        ),
      ]) {
        expect(
          () => ExpenseCostDirectionV2Candidate.parse(good, expected: context),
          throwsStateError,
        );
      }
      expect(
        () => _parse(
          _copy(good)..['amount_yen'] = 9007199254740992,
          ExpenseCostDocumentKind.invoice,
        ),
        throwsStateError,
      );
    },
  );
}
