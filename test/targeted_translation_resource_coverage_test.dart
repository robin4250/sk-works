import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/languages/en/english_language_pack.dart';

void main() {
  test('targeted screens fixed translation calls have English resources', () {
    final calls = RegExp(
      r"SkoLanguageController\.tr(?:Params)?\(\s*'([^'\n]+)'",
    );
    for (final file in [
      'lib/features/settings/company_module_settings_page.dart',
      'lib/features/settings/company_rate_settings_page.dart',
      'lib/features/payroll/individual_payroll_settings_page.dart',
      'lib/features/payroll/payment_certificates_page.dart',
      'lib/features/daily_reports/daily_report_page.dart',
      'lib/features/daily_reports/daily_report_pending_notice.dart',
    ]) {
      for (final match in calls.allMatches(File(file).readAsStringSync())) {
        final source = match.group(1)!;
        expect(englishLanguagePack.strings.containsKey(source), isTrue,
            reason: '$file: $source');
      }
    }
  });
}
