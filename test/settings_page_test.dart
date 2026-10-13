// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:sk_works/features/settings/settings_page.dart';

void main() {
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  });
  testWidgets(
    'settings removes duplicate company editing while personal settings still save',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_company_name': '旧端末だけの会社名',
        'settings_tax_rate': 8.0,
        'settings_default_unit_price': 12345,
        'settings_invoice_detail_mode': 'consolidatedOnly',
      });
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.pumpAndSettle();
      for (final label in [
        '会社情報',
        '会社名',
        '請求設定',
        '標準人工単価（円）',
        '標準の請求明細方式',
        '設定を保存',
        '旧端末だけの会社名',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.text('日本語'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('フローティングヘルプ'), findsOneWidget);
      await tester.tap(find.widgetWithText(SwitchListTile, 'アプリの通知音設定'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sko_app_notification_sound_enabled'), isFalse);
      // Removing the editor must not delete or silently migrate saved defaults.
      expect(prefs.getString('settings_company_name'), '旧端末だけの会社名');
      expect(prefs.getDouble('settings_tax_rate'), 8.0);
      expect(prefs.getInt('settings_default_unit_price'), 12345);
      expect(
        prefs.getString('settings_invoice_detail_mode'),
        'consolidatedOnly',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
