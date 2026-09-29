import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/company_document_exchange_repository.dart';

void main() {
  test('document exchange item keeps send kind and id only', () {
    const item = CompanyDocumentExchangeItem(
      id: 'item-1',
      kind: 'received',
      name: '資格証',
      group: '協力会社C',
    );

    expect(item.toSendJson(), {
      'id': 'item-1',
      'kind': 'received',
    });
  });

  test('request id is RFC4122-shaped version 4 UUID', () {
    final value = CompanyDocumentExchangeRepository.createRequestId(Random(7));

    expect(
      value,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
