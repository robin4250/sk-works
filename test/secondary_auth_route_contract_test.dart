import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sensitive routes stay behind secondary authentication', () {
    final source = File('lib/app_v2.dart').readAsStringSync();

    expect(
      source,
      contains(
        "const SecondaryProtectedPage(\n              title: '請求書',\n              child: InvoiceCloudPage(),",
      ),
    );
    expect(
      source,
      contains(
        "const SecondaryProtectedPage(\n          title: '管理者用現場データ',\n          child: AdminSiteFinancialPage(),",
      ),
    );

    final secondary =
        File('lib/features/auth/secondary_protected_page.dart').readAsStringSync();
    expect(secondary, contains('verifySecondaryPassword'));
    expect(secondary, contains('biometricOnly: true'));
  });
}
