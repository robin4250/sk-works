import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment certificate pages support English display', () {
    final source = File(
      'lib/features/payroll/payment_certificates_page.dart',
    ).readAsStringSync();

    expect(source, contains("SkoLanguageController.isEnglish ? 'Payment Certificates'"));
    expect(source, contains("'Payment Certificate Settings'"));
    expect(source, contains("'Subcontractor Company'"));
    expect(source, contains("'Daily Rate'"));
    expect(source, contains('Overtime Hourly Rate'));
    expect(source, contains('Early-start Hourly Rate'));
    expect(source, contains('Night Hourly Rate'));
    expect(source, contains("'Draft'"));
    expect(source, contains("'Finalized'"));
    expect(source, contains("'Print'"));
  });
}
