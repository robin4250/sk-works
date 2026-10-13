import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

PayrollStatementRecord statement(Map<String, dynamic> detail) =>
    PayrollStatementRecord(
      id: 'pay-type-test',
      companyName: '登録会社',
      workerName: '登録社員',
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 31),
      grossPay: 0,
      deductions: 0,
      netPay: 0,
      detail: detail,
    );

void main() {
  test(
    'payroll output preserves monthly hourly daily and missing metadata',
    () {
      for (final entry in <String, String>{
        'monthly': '月給',
        'hourly': '時給',
        'daily': '日給',
      }.entries) {
        expect(
          PayrollPdfService.buildTextSnapshot(
            statement({'pay_type': entry.key}),
          ),
          contains('給与形態 ${entry.value}'),
        );
        expect(
          PayrollPdfService.buildTextSnapshot(
            statement({'pay_type': '', '給与形態': entry.value}),
          ),
          contains('給与形態 ${entry.value}'),
        );
        expect(
          PayrollPdfService.buildTextSnapshot(statement({'給与方式': entry.value})),
          contains('給与形態 ${entry.value}'),
        );
        expect(
          PayrollPdfService.buildTextSnapshot(
            statement({
              'payroll_settings': {'pay_type': entry.key},
            }),
          ),
          contains('給与形態 ${entry.value}'),
        );
      }
      expect(
        PayrollPdfService.buildTextSnapshot(statement({})),
        contains('給与形態 未登録'),
      );
      expect(
        PayrollPdfService.buildTextSnapshot(statement({})),
        isNot(contains('¥0')),
      );
    },
  );
}
