import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('role-specific sensitive routes stay behind secondary authentication', () {
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
    expect(
      source,
      contains(
        "const SecondaryProtectedPage(\n          title: '給与明細',\n          child: PayrollStatementsPage(),",
      ),
    );

    expect(
      source,
      isNot(
        contains(
          "title: '必要書類',\n          child: WorkerDocumentPage(),",
        ),
      ),
    );
    expect(
      source,
      isNot(
        contains(
          "title: '資格証',\n          child: QualificationCertificatePage(),",
        ),
      ),
    );

    final secondary =
        File('lib/features/auth/secondary_protected_page.dart').readAsStringSync();
    expect(secondary, contains('secondaryPasswordConfigured'));
    expect(secondary, contains('setSecondaryPassword'));
    expect(secondary, contains('verifySecondaryPassword'));
    expect(secondary, contains('Face ID / Touch IDも使う'));
    expect(secondary, contains('AppLifecycleState.paused'));
  });

  test('secondary password is not required by the global auth gate', () {
    final gate = File('lib/features/auth/auth_gate.dart').readAsStringSync();

    expect(gate, isNot(contains('needsSecondaryPassword')));
    expect(gate, isNot(contains('SecondaryPasswordSetupPage(')));
  });
}
