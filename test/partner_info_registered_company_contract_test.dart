import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('partner info also shows registered subcontractor master rows', () {
    final page = File(
      'lib/features/people/company_delivery_inbox_page.dart',
    ).readAsStringSync();

    expect(page, contains('TradeCompanyRepository.maybeCreate()'));
    expect(page, contains('_loadRegisteredPartners()'));
    expect(page, contains('row.isSubcontractor'));
    expect(page, contains("'登録済み協力会社'"));
    expect(page, contains('partner.name'));
    expect(page, contains('partner.address'));
    expect(page, contains('partner.phone'));
  });

  test('received company data flow remains available beside registered companies', () {
    final page = File(
      'lib/features/people/company_delivery_inbox_page.dart',
    ).readAsStringSync();

    expect(page, contains('repository.listDeliveries()'));
    expect(page, contains('repository.loadConnectionInbox()'));
    expect(page, contains("'受信データはまだありません'"));
    expect(page, contains('item.originCompany'));
  });
}
