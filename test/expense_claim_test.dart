import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'expense_fixture.dart';

void main() {
  test(
    'approval starts at own company and repeat approval preserves later assignment',
    () {
      final original = expenseFixture('one');
      final approved = original.approve();
      expect(approved.allocation.category, ExpenseCategory.ownCompany);
      expect(original.approval, ExpenseApproval.pending);
      final assigned = approved.allocate(
        ExpenseAllocation(
          ExpenseCategory.customer,
          counterpartyId: 'customer-a',
        ),
      );
      expect(identical(assigned.approve(), assigned), isTrue);
      expect(assigned.id, original.id);
      expect(assigned.reject().allocation.counterpartyId, 'customer-a');
      expect(assigned.reject().isSettlementCandidate, isFalse);
      expect(
        assigned.reject().approve().allocation.category,
        ExpenseCategory.ownCompany,
      );
      expect(
        () => original.allocate(ExpenseAllocation(ExpenseCategory.ownCompany)),
        throwsStateError,
      );
    },
  );
  test(
    'all employees and statuses appear in allocation while applicant is exact',
    () {
      final entries = [
        expenseFixture('pending'),
        expenseFixture('approved').approve(),
        expenseFixture('rejected').reject(),
        expenseFixture('other', applicant: 'worker-ab'),
      ];
      final claims = ExpenseClaims(companyId: 'company', claims: entries);
      expect(claims.forList(ExpenseList.allocation), hasLength(4));
      expect(claims.forApplicant('worker-a').entries, hasLength(3));
      expect(claims.forList(ExpenseList.ownCompany).single.id, 'approved');
      expect(
        claims.entries.where((e) => e.isSettlementCandidate),
        hasLength(1),
      );
    },
  );
  test('duplicate IDs collapse only when all saved values agree', () {
    final claim = expenseFixture('same');
    expect(
      ExpenseClaims(
        companyId: 'company',
        claims: [claim, expenseFixture('same')],
      ).entries,
      hasLength(1),
    );
    expect(
      () =>
          ExpenseClaims(companyId: 'company', claims: [claim, claim.approve()]),
      throwsStateError,
    );
    expect(
      () => ExpenseClaims(
        companyId: 'company',
        claims: [expenseFixture('x', company: 'other')],
      ),
      throwsArgumentError,
    );
  });
  test(
    'counterparty details retain rejected history and reassignment removes old destination',
    () {
      final old = expenseFixture('one').approve().allocate(
        ExpenseAllocation(ExpenseCategory.subcontractor, counterpartyId: 'old'),
      );
      final newClaim = old.allocate(
        ExpenseAllocation(ExpenseCategory.customer, counterpartyId: 'new'),
      );
      final claims = ExpenseClaims(
        companyId: 'company',
        claims: [newClaim, newClaim],
      );
      expect(
        claims.forCounterparty(ExpenseCategory.subcontractor, 'old').entries,
        isEmpty,
      );
      expect(
        claims.forCounterparty(ExpenseCategory.customer, 'new').entries,
        hasLength(1),
      );
      final rejected = ExpenseClaims(
        companyId: 'company',
        claims: [old.reject()],
      );
      expect(
        rejected.forCounterparty(ExpenseCategory.subcontractor, 'old').entries,
        hasLength(1),
      );
      expect(rejected.entries.single.isSettlementCandidate, isFalse);
    },
  );
  test(
    'invalid identifiers, external allocations and negative values are rejected',
    () {
      expect(() => expenseFixture(''), throwsArgumentError);
      expect(() => expenseFixture('x', amount: -1), throwsArgumentError);
      expect(
        () => ExpenseAllocation(ExpenseCategory.customer),
        throwsArgumentError,
      );
      expect(
        () =>
            ExpenseAllocation(ExpenseCategory.ownCompany, counterpartyId: 'x'),
        throwsArgumentError,
      );
      final claims = ExpenseClaims(companyId: 'company', claims: []);
      expect(() => claims.forApplicant(''), throwsArgumentError);
      expect(
        () => claims.forCounterparty(ExpenseCategory.ownCompany, 'x'),
        throwsArgumentError,
      );
    },
  );
}
