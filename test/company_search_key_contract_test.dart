import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company discovery supports the agreed search keys', () {
    final source =
        File('lib/domain/company_search_key.dart').readAsStringSync();

    for (final key in <String>[
      'companyName',
      'address',
      'corporateNumber',
      'skoCompanyId',
    ]) {
      expect(source, contains(key));
    }
  });
}
