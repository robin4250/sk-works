import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice uses final generated company and dated approval seals', () {
    final s = File('lib/features/invoices/invoice_pdf_service.dart')
        .readAsStringSync();
    expect(s, contains('CompanySealPdf.build('));
    expect(
      File('lib/features/shared/company_seal_pdf.dart').readAsStringSync(),
      contains("name.endsWith('株式会社')"),
    );
    expect(
      File('lib/features/shared/company_seal_pdf.dart').readAsStringSync(),
      contains("'株式会社'"),
    );
    expect(s, contains('_datedApprovalStamp'));
    expect(s, contains("record.stampRole == 'approval' ? '承認' : '確認'"));
    expect(s, contains('_surname(record.name)'));
    expect(s, contains("date.month.toString().padLeft(2, '0')"));
    expect(s, contains('approvals.take(3)'));
  });
}
