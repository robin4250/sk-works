import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company submitted documents are admin-only navigation', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("case 'company_documents':"));
    expect(app, contains('page = const CompanySubmittedDocumentsPage();'));
    expect(app, contains("key: 'company_documents'"));
    expect(app, contains("label: '会社提出書類'"));
    expect(
      app,
      contains(
        "(key == 'company_deliveries' || key == 'company_documents')",
      ),
    );
    expect(home, contains("'company_documents'"));
    expect(home, contains("'会社提出書類'"));
    expect(home, contains('access: _HomeActionAccess.admin'));
  });
}
