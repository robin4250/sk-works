import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sk_works/features/daily_reports/daily_report_pending_notice.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  setUp(() {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
  });
  tearDown(() {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
  });
  testWidgets('clocked-in draft shows report completion status without salary claim', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: DailyReportPendingNotice(hasClockedInWorkers: true, isSigned: false),
    )));
    expect(find.text('打刻済み・日報未確定'), findsOneWidget);
    expect(find.textContaining('給与'), findsNothing);
  });

  testWidgets('signed report and no clock evidence do not show pending notice', (tester) async {
    for (final state in [(true, true), (false, false)]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: DailyReportPendingNotice(
          hasClockedInWorkers: state.$1, isSigned: state.$2,
        ),
      )));
      expect(find.text('打刻済み・日報未確定'), findsNothing);
    }
  });
  testWidgets('open notice switches English and Japanese without losing entered data', (tester) async {
    final controller = TextEditingController(text: '現場Aの登録内容');
    await tester.pumpWidget(ValueListenableBuilder(
      valueListenable: SkoLanguageController.pack,
      builder: (context, language, child) => MaterialApp(
        locale: Locale(language.languageCode),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: Column(children: [
          const DailyReportPendingNotice(hasClockedInWorkers: true, isSigned: false),
          TextField(controller: controller),
        ])),
      ),
    ));
    expect(find.text('打刻済み・日報未確定'), findsOneWidget);
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    await tester.pumpAndSettle();
    expect(find.text('Clocked In / Daily Report Pending'), findsOneWidget);
    expect(find.text('打刻済み・日報未確定'), findsNothing);
    expect(controller.text, '現場Aの登録内容');
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
    await tester.pumpAndSettle();
    expect(find.text('打刻済み・日報未確定'), findsOneWidget);
    expect(controller.text, '現場Aの登録内容');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

}
