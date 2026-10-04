import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll review list is connected to management and viewer menu', () {
    final app = read('lib/app_v2.dart');

    expect(app, contains("import 'features/payroll/payroll_review_page.dart';"));
    expect(app, contains("case 'payroll_review':"));
    expect(app, contains("title: '給料一覧'"));
    expect(app, contains('child: PayrollReviewPage()'));
    expect(app, contains("key: 'payroll_review'"));
    expect(app, contains("label: SkoLanguageController.tr('給料一覧')"));
    expect(app, contains('_identity.isManagement || _isViewer'));
  });
}
