import 'package:flutter_test/flutter_test.dart';

import '../lib/features/invoices/invoice_approval_repository.dart';

InvoiceApprovalRecord record({
  String status = 'approved',
  DateTime? approvedAt,
  DateTime? displayDate,
  DateTime? override,
  String mode = 'actual',
}) => InvoiceApprovalRecord(
  userId: 'user',
  name: '確認者',
  position: 1,
  status: status,
  canCurrentUserApprove: false,
  approvedAt: approvedAt,
  displayDate: displayDate,
  displayDateOverride: override,
  displayDateMode: mode,
);

void main() {
  test(
    'actual date uses Japan calendar day without inventing missing timestamps',
    () {
      expect(
        record(approvedAt: DateTime.utc(2026, 10, 7, 23)).stampDisplayDate,
        DateTime(2026, 10, 8),
      );
      expect(record().stampDisplayDate, isNull);
    },
  );
  test(
    'closing and no-date policies do not substitute current or actual date',
    () {
      final actual = DateTime.utc(2026, 10, 8);
      expect(
        record(mode: 'closing', approvedAt: actual).stampDisplayDate,
        isNull,
      );
      expect(record(mode: 'none', approvedAt: actual).stampDisplayDate, isNull);
      expect(
        record(
          mode: 'closing',
          approvedAt: actual,
          displayDate: DateTime(2026, 9, 30),
        ).stampDisplayDate,
        DateTime(2026, 9, 30),
      );
    },
  );
  test('override changes display only and pending records never stamp', () {
    final actual = DateTime.utc(2026, 10, 8);
    final item = record(approvedAt: actual, override: DateTime(2026, 9, 30));
    expect(item.stampDisplayDate, DateTime(2026, 9, 30));
    expect(item.approvedAt, actual);
    expect(
      record(
        status: 'pending',
        approvedAt: actual,
        override: DateTime(2026, 9, 30),
      ).stampDisplayDate,
      isNull,
    );
  });
}
