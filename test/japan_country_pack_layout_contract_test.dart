import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Japan is an explicit country pack behind a neutral contract', () {
    expect(File('lib/international/core/country_pack.dart').existsSync(), isTrue);
    expect(
      File('lib/international/countries/jp/japan_country_pack.dart').existsSync(),
      isTrue,
    );
    final active =
        File('lib/international/active_country_pack.dart').readAsStringSync();
    expect(active, contains('japanCountryPack'));
  });
}
