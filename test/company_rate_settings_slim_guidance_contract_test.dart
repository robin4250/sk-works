import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Formatting may split translated widget arguments across lines.
Matcher containsUi(String expected) => predicate<String>(
  (source) => source.replaceAll(RegExp(r'\s+'), '').contains(
    expected.replaceAll(RegExp(r'\s+'), ''),
  ),
  'contains translated UI contract: $expected',
);

void main() {
  test('company rates explain source ownership and retain editable legacy rates', () {
    final source = File(
      'lib/features/settings/company_rate_settings_page.dart',
    ).readAsStringSync();
    expect(source, contains('会社共通の税率・福利厚生費率・手当をここで設定します。'));
    expect(source, contains('社員ごとの給与は「個別給与設定」'));
    expect(source, contains('現場ごとの請求単価は「管理者用現場データ」'));
    expect(source, contains('同じ内容の再入力は不要です。'));
    expect(source, contains('SkoLanguageController.watch(context)'));
    expect(source, contains('ExpansionTile('));
    expect(source, containsUi("SkoLanguageController.tr('旧単価（登録済み設定）')"));
    expect(source, contains('_moneyField(_overtime,'));
    expect(source, contains('_moneyField(_early,'));
    expect(source, contains('_moneyField(_night,'));
    expect(source, contains('_moneyField(_holiday,'));
  });
}
