import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('received subcontractor data is grouped into the agreed hierarchy', () {
    final page = File(
      'lib/features/people/company_delivery_inbox_page.dart',
    ).readAsStringSync();

    expect(page, contains("personnel('社員')"));
    expect(page, contains("qualifications('資格')"));
    expect(page, contains("workerDocuments('必要書類')"));
    expect(page, contains("companyDocuments('会社提出書類一覧')"));

    expect(page, contains("'qualification-certificates'"));
    expect(page, contains("'worker-documents'"));
    expect(page, contains("'company-required-documents'"));
    expect(page, contains('item.originCompany'));
    expect(page, contains("'kind': item.isStructured ? 'received_data' : 'received'"));
  });
}
