import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice uses generated company and surname-only approval seals', () {
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
    expect(s, isNot(contains("record.stampRole == 'approval' ? '承認' : '確認'")));
    expect(s, contains('_surname(record.name)'));
    expect(s, isNot(contains('final date = record.stampDisplayDate;')));
    expect(s, contains('for (var i = 0; i < 3; i++)'));
    expect(s, contains('approvals[i].approved'));
    expect(s, isNot(contains('static pw.Widget _approvalBoxes(')));
  });
}
