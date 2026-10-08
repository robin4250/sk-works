import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:sk_works/features/payroll/individual_payroll_settings_page.dart';
import 'package:sk_works/features/settings/company_module_settings_page.dart';
import 'package:sk_works/features/settings/company_rate_settings_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  tearDown(() {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
  });

  for (final entry in <(Widget, String)>[
    (const IndividualPayrollSettingsPage(), '個別給与設定'),
    (const CompanyRateSettingsPage(), '会社単価・手当設定'),
    (const CompanyModuleSettingsPage(), '利用機能のON／OFF'),
  ]) {
    testWidgets('${entry.$2} reacts to language changes while open', (tester) async {
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
      await tester.pumpWidget(ValueListenableBuilder(
        valueListenable: SkoLanguageController.pack,
        builder: (context, pack, child) => MaterialApp(
          locale: Locale(pack.languageCode),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('ja'), Locale('en')],
          home: entry.$1,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);

      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
      await tester.pumpAndSettle();
      final translated = SkoLanguageController.tr(entry.$2);
      expect(translated, isNot(entry.$2));
      expect(find.text(translated), findsOneWidget);
      expect(find.text(entry.$2), findsNothing);

      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
    });
  }
}
