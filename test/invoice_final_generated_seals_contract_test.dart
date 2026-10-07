import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('invoice uses final generated company and dated approval seals', () {
    final s=File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
    expect(s, contains('_companySealGroups'));
    expect(s, contains("name.endsWith('株式会社')"));
    expect(s, contains("'株式会社'"));
    expect(s, contains('_datedApprovalStamp'));
    expect(s, contains("approval ? '承認' : '確認'"));
    expect(s, contains('_surname(record.name)'));
    expect(s, contains("date.month.toString().padLeft(2, '0')"));
    expect(s, contains('approvals.take(3)'));
  });
}
