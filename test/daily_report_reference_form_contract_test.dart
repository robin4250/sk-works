import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily report PDF follows supplied handwritten work-report structure', () {
    final source = File(
      'lib/features/daily_reports/daily_report_pdf_service.dart',
    ).readAsStringSync();

    expect(source, contains("'作業日報'"));
    expect(source, contains("SkoLanguageController.tr('現場名')"));
    expect(source, contains("SkoLanguageController.tr('作業内容')"));
    expect(source, contains("SkoLanguageController.tr('報告者サイン')"));
    expect(source, contains("SkoLanguageController.tr('責任者サイン')"));
    expect(source, contains("SkoLanguageController.tr('日付')"));
    expect(source, contains("SkoLanguageController.tr('現場')"));
    expect(source, contains('PdfColors.blueGrey100'));
  });
}
