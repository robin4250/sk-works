/// Approval, allocation and submission are distinct concepts. These objects do
/// not save, approve, reimburse or change any payroll/invoice amount.
enum ExpenseApproval { pending, approved, rejected }

enum ExpenseCategory { unallocated, ownCompany, subcontractor, customer }

enum ExpenseList { allocation, ownCompany, subcontractor, customer }

class ExpenseAllocation {
  ExpenseAllocation(
    this.category, {
    this.counterpartyId,
    this.counterpartyName,
  }) {
    final external =
        category == ExpenseCategory.subcontractor ||
        category == ExpenseCategory.customer;
    if (external &&
        (counterpartyId == null || counterpartyId!.trim().isEmpty)) {
      throw ArgumentError('An external allocation requires a counterparty ID.');
    }
    if (!external && (counterpartyId != null || counterpartyName != null)) {
      throw ArgumentError(
        'Own/unallocated expenses cannot have a counterparty.',
      );
    }
  }
  final ExpenseCategory category;
  final String? counterpartyId;
  final String? counterpartyName;
  bool sameAs(ExpenseAllocation other) =>
      category == other.category &&
      counterpartyId == other.counterpartyId &&
      counterpartyName == other.counterpartyName;
}

class ExpenseClaim {
  ExpenseClaim({
    required this.id,
    required this.companyId,
    required this.applicantId,
    required this.applicantName,
    required DateTime incurredOn,
    required this.submittedAt,
    required this.description,
    required this.amountYen,
    required this.approval,
    required this.allocation,
    this.revision = 1,
    this.withdrawn = false,
  }) : incurredOn = DateTime.utc(
         incurredOn.year,
         incurredOn.month,
         incurredOn.day,
       ) {
    for (final value in [
      id,
      companyId,
      applicantId,
      applicantName,
      description,
    ]) {
      if (value.trim().isEmpty) {
        throw ArgumentError('Claim fields cannot be empty.');
      }
    }
    if (amountYen < 0) {
      throw ArgumentError('An expense amount cannot be negative.');
    }
  }
  final String id;
  final String companyId;
  final String applicantId;
  final String applicantName;

  /// A civil date. No conversion from an instant into another timezone.
  final DateTime incurredOn;
  final DateTime submittedAt;
  final String description;
  final int amountYen;
  final ExpenseApproval approval;
  final int revision;
  final bool withdrawn;
  final ExpenseAllocation allocation;

  /// A candidate only. Period, payment and immutable snapshot rules belong to
  /// the future persistence contract, not to this display model.
  bool get isSettlementCandidate => !withdrawn && approval == ExpenseApproval.approved;

  ExpenseClaim _copy(ExpenseApproval status, ExpenseAllocation destination) =>
      ExpenseClaim(
        id: id,
        companyId: companyId,
        applicantId: applicantId,
        applicantName: applicantName,
        incurredOn: incurredOn,
        submittedAt: submittedAt,
        description: description,
        amountYen: amountYen,
        approval: status,
        allocation: destination,
        revision: revision,
        withdrawn: withdrawn,
      );

  /// An already approved claim is not silently reassigned by a duplicate event.
  ExpenseClaim approve() {
    if (withdrawn) throw StateError('Withdrawn expenses cannot be approved.');
    return approval == ExpenseApproval.approved
      ? this
      : _copy(
          ExpenseApproval.approved,
          ExpenseAllocation(ExpenseCategory.ownCompany),
        );
  }
  ExpenseClaim reject() {
    if (withdrawn) throw StateError('Withdrawn expenses cannot be reviewed.');
    return _copy(ExpenseApproval.rejected, allocation);
  }
  ExpenseClaim allocate(ExpenseAllocation destination) {
    if (withdrawn || approval != ExpenseApproval.approved ||
        destination.category == ExpenseCategory.unallocated) {
      throw StateError(
        'Only approved claims can be allocated to a destination.',
      );
    }
    return _copy(approval, destination);
  }

  bool sameAs(ExpenseClaim other) =>
      id == other.id &&
      companyId == other.companyId &&
      applicantId == other.applicantId &&
      applicantName == other.applicantName &&
      incurredOn == other.incurredOn &&
      submittedAt == other.submittedAt &&
      description == other.description &&
      amountYen == other.amountYen &&
      approval == other.approval &&
      revision == other.revision &&
      withdrawn == other.withdrawn &&
      allocation.sameAs(other.allocation);
}

/// Drafts cannot be supplied to submitted-claim lists or PDF details.
/// No conversion to a submitted claim is provided without a persistence contract.
class ExpenseDraft {
  const ExpenseDraft({
    required this.companyId,
    required this.applicantId,
    required this.incurredOn,
    required this.description,
    required this.amountText,
  });
  final String companyId;
  final String applicantId;
  final DateTime incurredOn;
  final String description;
  final String amountText;
}

class ExpenseClaims {
  ExpenseClaims({
    required this.companyId,
    required Iterable<ExpenseClaim> claims,
  }) {
    if (companyId.trim().isEmpty) throw ArgumentError('Company ID required.');
    final unique = <String, ExpenseClaim>{};
    for (final claim in claims) {
      if (claim.companyId != companyId) {
        throw ArgumentError('Company scope mismatch.');
      }
      final previous = unique[claim.id];
      if (previous != null && !previous.sameAs(claim)) {
        throw StateError('Conflicting versions for one expense ID.');
      }
      unique[claim.id] = claim;
    }
    entries = List.unmodifiable(unique.values);
  }
  final String companyId;
  late final List<ExpenseClaim> entries;
  List<ExpenseClaim> forList(ExpenseList list) => List.unmodifiable(
    entries.where(
      (claim) => switch (list) {
        ExpenseList.allocation => true,
        ExpenseList.ownCompany =>
          claim.allocation.category == ExpenseCategory.ownCompany,
        ExpenseList.subcontractor =>
          claim.allocation.category == ExpenseCategory.subcontractor,
        ExpenseList.customer =>
          claim.allocation.category == ExpenseCategory.customer,
      },
    ),
  );
  ExpenseClaims forMonth(DateTime month) => ExpenseClaims(
    companyId: companyId,
    claims: entries.where(
      (c) =>
          c.incurredOn.year == month.year && c.incurredOn.month == month.month,
    ),
  );

  ExpenseClaims forApplicant(String applicantId) {
    if (applicantId.trim().isEmpty) {
      throw ArgumentError('Applicant ID required.');
    }
    return ExpenseClaims(
      companyId: companyId,
      claims: entries.where((claim) => claim.applicantId == applicantId),
    );
  }

  ExpenseClaims forCounterparty(
    ExpenseCategory category,
    String counterpartyId,
  ) {
    if (!const [
          ExpenseCategory.customer,
          ExpenseCategory.subcontractor,
        ].contains(category) ||
        counterpartyId.trim().isEmpty) {
      throw ArgumentError('External destination required.');
    }
    return ExpenseClaims(
      companyId: companyId,
      claims: entries.where(
        (claim) =>
            claim.allocation.category == category &&
            claim.allocation.counterpartyId == counterpartyId,
      ),
    );
  }
}

String expenseApprovalLabel(ExpenseApproval status) => switch (status) {
  ExpenseApproval.pending => '未承認',
  ExpenseApproval.approved => '承認済み',
  ExpenseApproval.rejected => '却下',
};
String expenseCategoryLabel(ExpenseCategory category) => switch (category) {
  ExpenseCategory.unallocated => '未振り分け',
  ExpenseCategory.ownCompany => '自社',
  ExpenseCategory.subcontractor => '下請け・協力会社',
  ExpenseCategory.customer => '取引先',
};

String expenseClaimStatusLabel(ExpenseClaim claim) => claim.withdrawn ? '取り下げ（削除済み）' : expenseApprovalLabel(claim.approval);
