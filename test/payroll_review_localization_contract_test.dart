import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll review supports English display without changing review logic', () {
    final source =
        File('lib/features/payroll/payroll_review_page.dart').readAsStringSync();

    expect(source, contains("import '../../international/language_controller.dart';"));
    expect(source, contains("'Payroll Review'"));
    expect(source, contains("'Hide from sub-admins'"));
    expect(source, contains("'Confirmed'"));
    expect(source, contains("'Unconfirmed'"));
    expect(source, contains("'Confirm after reviewing all'"));

    // Keep the existing hide-from-sub-admin semantics.
    expect(source, contains('value: !worker.visibleToManager'));
    expect(source, contains('visible: !hidden'));
  });
}
