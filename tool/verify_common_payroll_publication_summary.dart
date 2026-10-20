import 'dart:io';
import 'package:sk_works/features/payroll/company_common_payroll_publication_summary.dart';

// Pure Dart only: no Flutter startup, SDK client or network.
void main() {
  void check(bool value, String label) {
    if (!value) throw StateError(label);
  }

  for (final count in [0, 1, 12, 2147483647]) {
    final result = CommonPayrollPublicationSummary.fromReceipt({
      'recalculated_scopes': count,
    });
    check(result.recalculatedScopes == count, 'exact server integer $count');
    check(
      result.message.contains('再計算：$count件'),
      'visible exact server count $count',
    );
    check(!result.message.contains('すべて'), 'no all-payroll success claim');
  }
  for (final invalid in [
    null,
    -1,
    '12',
    12.0,
    true,
    <String, dynamic>{},
    [12],
  ]) {
    final result = CommonPayrollPublicationSummary.fromReceipt({
      'recalculated_scopes': invalid,
    });
    check(result.recalculatedScopes == null, 'unknown invalid count $invalid');
    check(
      result.message.contains('再計算件数を確認できません'),
      'unknown count remains explicit',
    );
    check(!result.message.contains('0件'), 'unknown is not zero');
  }
  for (final missing in [
    null,
    [],
    {
      'timeline': {
        'entries': [1, 2, 3],
      },
    },
  ]) {
    check(
      CommonPayrollPublicationSummary.fromReceipt(missing).recalculatedScopes ==
          null,
      'timeline or missing payload must not supply a count',
    );
  }
  stdout.writeln(
    'PASS publication summary: exact nonnegative integers, explicit zero, invalid/missing counts, no inferred totals',
  );
}
