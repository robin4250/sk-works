import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  test('Japanese and English language packs are both available', () {
    expect(LanguagePackRegistry.resolve('ja').languageCode, 'ja');
    expect(LanguagePackRegistry.resolve('en').languageCode, 'en');
    expect(LanguagePackRegistry.resolve('en-US').languageCode, 'en');
    expect(
      LanguagePackRegistry.resolve('en').translate('現場マップ'),
      'Site Map',
    );
  });

  test('language switch is wired through app, print, reports, and chat', () {
    final main = File('lib/main.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();
    final settings =
        File('lib/features/settings/settings_page.dart').readAsStringSync();
    final attendancePdf = File(
      'lib/features/attendance/attendance_pdf_service.dart',
    ).readAsStringSync();
    final reportPdf = File(
      'lib/features/daily_reports/daily_report_pdf_service.dart',
    ).readAsStringSync();
    final report = File(
      'lib/features/daily_reports/daily_report_page.dart',
    ).readAsStringSync();
    final chat =
        File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();
    final profile =
        File('lib/features/profile/profile_page.dart').readAsStringSync();
    final peoplePrint = File(
      'lib/features/people/employee_personnel_print_page.dart',
    ).readAsStringSync();

    expect(main, contains('SkoLanguageController.loadLocal()'));
    expect(app, contains('SkoLanguageController.pack'));
    expect(settings, contains("value: 'ja'"));
    expect(settings, contains("value: 'en'"));
    expect(settings, contains('SkoLanguageController.setLanguage'));
    expect(attendancePdf, contains('SkoLanguageController'));
    expect(reportPdf, contains('SkoLanguageController'));
    expect(report, contains('SkoLanguageController'));
    expect(chat, contains('SkoLanguageController'));
    expect(profile, contains('SkoLanguageController'));
    expect(peoplePrint, contains('SkoLanguageController'));
  });
}
