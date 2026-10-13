import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registered partners use the existing company registration list and details', () {
    final page = File('lib/features/companies/trade_company_page.dart').readAsStringSync();
    final inbox = File('lib/features/people/company_delivery_inbox_page.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();
    expect(page, contains('TradeCompanyRepository.maybeCreate()'));
    expect(page, contains('item.isSubcontractor'));
    expect(page, contains('_openCompany(item)'));
    expect(page, contains('item.name'));
    expect(page, contains('item.address'));
    expect(page, contains('item.phone'));
    expect(page, contains('onOpenDeliveries'));
    expect(app, contains("case 'company_deliveries':"));
    expect(inbox, isNot(contains('_registeredPartners')));
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
