import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  testWidgets('locale changes update an open editor without losing its text', (tester) async {
    final original = SkoLanguageController.pack.value;
    addTearDown(() => SkoLanguageController.pack.value = original);
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
    await tester.pumpWidget(ValueListenableBuilder(
      valueListenable: SkoLanguageController.pack,
      builder: (_, language, _) => MaterialApp(
        locale: Locale(language.languageCode),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _Editor()),
            ),
            child: const Text('Open editor'),
          ),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '株式会社テスト 1500');
    expect(find.text('再試行'), findsOneWidget);
    final state = tester.state<_EditorState>(find.byType(_Editor));
    final controller = state.controller;
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(state.controller, same(controller));
    expect(controller.text, '株式会社テスト 1500');
    final context = tester.element(find.byType(TextField));
    expect(Localizations.localeOf(context).languageCode, 'en');
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Cancel');
    expect(find.text('株式会社テスト 1500'), findsOneWidget);
  });
}

class _Editor extends StatefulWidget {
  const _Editor();
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(body: Column(children: [
      Text(SkoLanguageController.tr('再試行')),
      TextField(controller: controller),
    ]));
  }
}
