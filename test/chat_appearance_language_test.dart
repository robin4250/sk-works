import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/chat/chat_appearance_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final original = SkoLanguageController.pack.value;
    addTearDown(() => SkoLanguageController.pack.value = original);
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
  });

  Future<void> open(
    WidgetTester tester, {
    bool fullHeight = true,
    ChatAppearance initial = const ChatAppearance(),
    ValueChanged<ChatAppearance?>? onSaved,
  }) async {
    if (fullHeight) {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: SkoLanguageController.pack,
        builder: (_, language, _) => MaterialApp(
          locale: Locale(language.languageCode),
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<ChatAppearance>(
                        MaterialPageRoute(
                          builder: (_) => ChatAppearancePage(
                            groupId: 'group-1',
                            initial: initial,
                          ),
                        ),
                      );
                  onSaved?.call(result);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'live switch preserves edited opacity and saves the original group keys only',
    (tester) async {
      ChatAppearance? saved;
      await open(
        tester,
        initial: const ChatAppearance(
          backgroundOpacity: 43,
          headerOpacity: 67,
          footerOpacity: 81,
          bubbleOpacity: 92,
        ),
        onSaved: (value) => saved = value,
      );
      final state = tester.state(find.byType(ChatAppearancePage));
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(29);
      await tester.pumpAndSettle();
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ChatAppearancePage)), same(state));
      expect(find.text('Chat appearance'), findsOneWidget);
      expect(find.text('No wallpaper'), findsOneWidget);
      expect(
        find.text(
          'Personal settings for this chat only. Other users are not affected.',
        ),
        findsOneWidget,
      );
      expect(find.text('Choose wallpaper'), findsOneWidget);
      expect(find.text('Remove wallpaper'), findsOneWidget);
      expect(find.text('Wallpaper opacity  29％'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      await tester.scrollUntilVisible(find.text('Save for this chat'), 200);
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<Slider>(find.byType(Slider)).map((s) => s.value),
        [29, 67, 81, 92],
      );
      await tester.tap(find.text('Save for this chat'));
      await tester.pumpAndSettle();
      expect(saved!.backgroundOpacity, 29);
      expect(saved!.headerOpacity, 67);
      expect(saved!.footerOpacity, 81);
      expect(saved!.bubbleOpacity, 92);
      expect(prefs.getKeys(), {
        'sko_chat_appearance_group-1_background',
        'sko_chat_appearance_group-1_header',
        'sko_chat_appearance_group-1_footer',
        'sko_chat_appearance_group-1_bubble',
      });
      expect(prefs.getInt('sko_chat_appearance_group-1_background'), 29);
    },
  );

  testWidgets(
    'back after language changes does not save or alter existing settings',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'sko_chat_appearance_group-1_background': 47,
        'unrelated': 'keep',
      });
      await open(tester, initial: const ChatAppearance(backgroundOpacity: 47));
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(30);
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
      await tester.pumpAndSettle();
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
      await tester.pumpAndSettle();
      expect(find.text('チャット背景・透明度'), findsOneWidget);
      expect(find.text('壁紙の透明度  30％'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('sko_chat_appearance_group-1_background'), 47);
      expect(prefs.getString('unrelated'), 'keep');
      expect(prefs.getKeys().length, 2);
    },
  );

  testWidgets('English controls fit a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    await open(tester, fullHeight: false);
    await tester.scrollUntilVisible(find.text('Save for this chat'), 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Message background opacity  80％'), findsOneWidget);
  });
}
