import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/help/manual_content.dart';
import 'package:sk_works/features/help/manual_library_page.dart';
import 'package:sk_works/features/help/manual_version.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  testWidgets('English manual library shows beta date and Japanese PDF language', (tester) async {
    final original = SkoLanguageController.pack.value;
    addTearDown(() => SkoLanguageController.pack.value = original);
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const ManualLibraryPage(role: ManualRole.general),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Help / Manual'), findsOneWidget);
    expect(find.text('Manual for Employee'), findsOneWidget);
    expect(find.text('SKO v${ManualVersion.appVersion} / Beta / ${ManualVersion.revisionDate}'), findsOneWidget);
    expect(find.text('The PDF is in Japanese.'), findsOneWidget);
    expect(find.textContaining('10 pages.'), findsOneWidget);
    expect(find.text('Open Employee Manual PDF'), findsOneWidget);
    expect(ManualContent.forRole(ManualRole.general).length, 10);
    expect(ManualContent.forRole(ManualRole.subAdmin).length, 15);
    expect(ManualContent.forRole(ManualRole.admin).length, 20);
  });
}
