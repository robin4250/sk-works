enum PayrollAdjustmentDirection {
  addition,
  deduction,
}

class PayrollAdjustmentType {
  const PayrollAdjustmentType({
    required this.id,
    required this.companyId,
    required this.label,
    required this.direction,
    this.isActive = true,
  });

  final String id;
  final String companyId;
  final String label;
  final PayrollAdjustmentDirection direction;
  final bool isActive;

  PayrollAdjustmentType copyWith({
    String? label,
    PayrollAdjustmentDirection? direction,
    bool? isActive,
  }) {
    return PayrollAdjustmentType(
      id: id,
      companyId: companyId,
      label: label ?? this.label,
      direction: direction ?? this.direction,
      isActive: isActive ?? this.isActive,
    );
  }
}

class PayrollAdjustmentRecord {
  const PayrollAdjustmentRecord({
    required this.id,
    required this.companyId,
    required this.workerId,
    required this.typeId,
    required this.labelSnapshot,
    required this.direction,
    required this.amountYen,
    required this.effectiveDate,
    required this.createdByUserId,
    required this.createdAt,
    this.note,
    this.cancelledAt,
    this.cancelledByUserId,
  }) : assert(amountYen >= 0);

  final String id;
  final String companyId;
  final String workerId;
  final String typeId;

  // Keep the label used at the time of entry even if an admin renames
  // the reusable company-level adjustment type later.
  final String labelSnapshot;
  final PayrollAdjustmentDirection direction;
  final int amountYen;
  final DateTime effectiveDate;
  final String createdByUserId;
  final DateTime createdAt;
  final String? note;
  final DateTime? cancelledAt;
  final String? cancelledByUserId;

  bool get isCancelled => cancelledAt != null;

  int get signedAmountYen {
    if (isCancelled) return 0;
    return direction == PayrollAdjustmentDirection.addition
        ? amountYen
        : -amountYen;
  }
}
