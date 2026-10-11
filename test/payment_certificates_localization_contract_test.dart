import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment certificate pages support English display', () {
    final source = File(
      'lib/features/payroll/payment_certificates_page.dart',
    ).readAsStringSync();

    expect(source, contains("SkoLanguageController.isEnglish ? 'Payment Certificates'"));
    expect(source, contains("label: '支払証明書設定'"));
    final footer = File('lib/features/shared/related_action_footer.dart').readAsStringSync();
    final english = File('lib/features/languages/en/english_language_pack.dart').readAsStringSync();
    expect(footer, contains('SkoLanguageController.tr(label)'));
    expect(english, contains('Payment Certificate Settings'));
    expect(source, contains("'Subcontractor Company'"));
    expect(source, contains("'日給'"));
    expect(source, contains("'時給'"));
    expect(source, contains("'残業 1時間単価'"));
    expect(source, contains("'早出 1時間単価'"));
    expect(source, contains("'夜勤 1日単価'"));
    expect(source, contains("'Draft'"));
    expect(source, contains("'Finalized'"));
    expect(source, contains("'Print'"));
  });
}
