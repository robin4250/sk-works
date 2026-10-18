import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/expense_cost_direction_v2_candidate.dart';
import 'package:sk_works/domain/expense_payment_reader_candidate.dart';

const _company = '11111111-1111-1111-1111-111111111111';
const _document = '22222222-2222-2222-2222-222222222222';
const _subject = '33333333-3333-3333-3333-333333333333';
const _claim = '44444444-4444-4444-4444-444444444444';
const _context = ExpenseCostContext(
  kind: ExpenseCostDocumentKind.paymentCertificate,
  companyId: _company,
  documentId: _document,
  subjectId: _subject,
  month: '2026-10',
  documentRevision: 3,
);
List<Map<String, dynamic>> _claims() => [
  {'id': _claim, 'revision': 2, 'amount_yen': 1000},
];
Map<String, dynamic> _v2() => {
  'version': 2,
  'contract': 'expense_cost_direction',
  'document_kind': 'paymentCertificate',
  'direction': 'deduction',
  'company_id': _company,
  'document_id': _document,
  'subject_id': _subject,
  'month': '2026-10',
  'document_revision': 3,
  'amount_yen': 1000,
  'claims': _claims(),
};
Map<String, dynamic> _row({bool v2 = true}) => {
  'company_id': _company,
  'id': _document,
  'partner_company_id': _subject,
  'period_start': '2026-10-01',
  'period_end': '2026-10-31',
  'revision': 3,
  'gross_amount': v2 ? 0 : 1000,
  'deductions': v2 ? 1000 : 0,
  'net_amount': v2 ? -1000 : 1000,
  'status': 'finalized',
  'snapshot': v2
      ? {'expense_cost_direction_v2': _v2()}
      : {
          'expense_extra_source_version': 1,
          'expense_extra_amount_yen': 1000,
          'expense_extra_claims': _claims(),
        },
};
ExpensePaymentReadCandidate _read(
  Map<String, dynamic> row, {
  bool enabled = true,
  ExpensePaymentBasisCandidate? basis,
  Object? details,
  bool useDefaultBasis = true,
}) => ExpensePaymentReadCandidate.read(
  row: row,
  expected: _context,
  expectedPeriodStart: '2026-10-01',
  expectedPeriodEnd: '2026-10-31',
  legacyDetails: _claims(),
  v2ContractVerified: enabled,
  v2Basis:
      basis ??
      (useDefaultBasis
          ? const ExpensePaymentBasisCandidate(
              context: _context,
              grossBeforeExpenseYen: 0,
              otherDeductionsYen: 0,
            )
          : null),
  v2ScopedDetails: details ?? (useDefaultBasis ? _v2() : null),
);
Map<String, dynamic> _copy(Map<String, dynamic> row) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(row)) as Map);

void main() {
  test(
    'expense-only saved payment reads -1000 with exact scoped details and independent basis',
    () {
      final row = _row();
      final before = jsonEncode(row);
      final result = _read(row);
      expect(result.usesV2, isTrue);
      expect(result.expenseLineDeltaYen, -1000);
      expect(result.grossYen, 0);
      expect(result.deductionsYen, 1000);
      expect(result.netYen, -1000);
      expect(jsonEncode(row), before);
      expect(
        () => result.directionalCost!.claims.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'default gate is OFF and a capability boolean cannot replace basis and detail evidence',
    () {
      expect(
        () => ExpensePaymentReadCandidate.read(
          row: _row(),
          expected: _context,
          expectedPeriodStart: '2026-10-01',
          expectedPeriodEnd: '2026-10-31',
          legacyDetails: _claims(),
        ),
        throwsStateError,
      );
      expect(() => _read(_row(), enabled: false), throwsStateError);
      expect(() => _read(_row(), useDefaultBasis: false), throwsStateError);
      expect(() => _read(_row(), details: {}), throwsStateError);
    },
  );
  test(
    'legacy finalized +1000 is preserved and cannot acquire a deduction from v2 evidence',
    () {
      final row = _row(v2: false);
      final before = jsonEncode(row);
      final result = _read(row, useDefaultBasis: false);
      expect(result.usesV2, isFalse);
      expect(result.expenseLineDeltaYen, 1000);
      expect(result.grossYen, 1000);
      expect(result.deductionsYen, 0);
      expect(result.netYen, 1000);
      expect(result.legacyCost!.fields, row['snapshot']);
      expect(jsonEncode(row), before);
      expect(() => _read(row), throwsStateError);
    },
  );
  test('mixed v1/v2 or malformed v2 never falls back to additive legacy', () {
    for (final value in [null, {}, 1]) {
      final row = _row()..['snapshot'] = {'expense_cost_direction_v2': value};
      expect(() => _read(row), throwsStateError);
    }
    final mixed = _copy(_row());
    mixed['snapshot']['expense_extra_source_version'] = 1;
    expect(() => _read(mixed), throwsStateError);
  });
  test(
    'company document partner period and revision are exact, with no date or number fallback',
    () {
      for (final entry in <String, Object?>{
        'company_id': _subject,
        'id': _subject,
        'partner_company_id': _company,
        'period_start': '2026-09-01',
        'period_end': '2026-11-01',
        'revision': 4,
        'gross_amount': 0.0,
        'deductions': -1000,
        'net_amount': '-1000',
        'snapshot': null,
      }.entries) {
        expect(
          () => _read(_row()..[entry.key] = entry.value),
          throwsStateError,
          reason: entry.key,
        );
      }
      for (final date in ['2026-10-32', '2026-10-31T00:00:00Z', '2026-10-00']) {
        final row = _row()..['period_end'] = date;
        expect(
          () => ExpensePaymentReadCandidate.read(
            row: row,
            expected: _context,
            expectedPeriodStart: '2026-10-01',
            expectedPeriodEnd: date,
            legacyDetails: _claims(),
          ),
          throwsStateError,
        );
      }
    },
  );
  test(
    'snapshot and detail scope or claim revision mismatch reject the entire projection',
    () {
      for (final entry in <String, Object>{
        'company_id': _subject,
        'document_id': _subject,
        'subject_id': _company,
        'month': '2026-11',
        'document_revision': 4,
        'direction': 'addition',
        'document_kind': 'invoice',
      }.entries) {
        final bad = _v2()..[entry.key] = entry.value;
        expect(
          () => _read(_row(), details: bad),
          throwsStateError,
          reason: entry.key,
        );
        final row = _row();
        row['snapshot']['expense_cost_direction_v2'] = bad;
        expect(() => _read(row), throwsStateError);
      }
      final changed = _v2();
      changed['claims'].first['revision'] = 3;
      expect(() => _read(_row(), details: changed), throwsStateError);
    },
  );
  test(
    'positive, double deduction and changed gross cannot masquerade as signed saved totals',
    () {
      for (final values in [
        [0, 1000, 1000],
        [0, 1000, 0],
        [0, 2000, -2000],
        [1000, 1000, 0],
      ]) {
        final row = _row()
          ..['gross_amount'] = values[0]
          ..['deductions'] = values[1]
          ..['net_amount'] = values[2];
        expect(() => _read(row), throwsStateError);
      }
      const otherContext = ExpenseCostContext(
        kind: ExpenseCostDocumentKind.paymentCertificate,
        companyId: _company,
        documentId: _document,
        subjectId: _subject,
        month: '2026-10',
        documentRevision: 2,
      );
      expect(
        () => _read(
          _row(),
          basis: const ExpensePaymentBasisCandidate(
            context: otherContext,
            grossBeforeExpenseYen: 0,
            otherDeductionsYen: 0,
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'other nonexpense deductions and base gross are retained without deriving from a legacy gross',
    () {
      final row = _row()
        ..['gross_amount'] = 20000
        ..['deductions'] = 1500
        ..['net_amount'] = 18500;
      final result = _read(
        row,
        basis: const ExpensePaymentBasisCandidate(
          context: _context,
          grossBeforeExpenseYen: 20000,
          otherDeductionsYen: 500,
        ),
      );
      expect(result.grossYen, 20000);
      expect(result.deductionsYen, 1500);
      expect(result.netYen, 18500);
    },
  );
}
