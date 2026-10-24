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
    expect(source, contains('共通手当は給料一覧の「社内共通手当」から設定します。'));
    expect(source, contains('この保存では手当の名称・金額・単位を変更しません。'));
    expect(source, contains('SkoLanguageController.watch(context)'));
    expect(source, contains('ExpansionTile('));
    expect(source, containsUi("SkoLanguageController.tr('旧単価（登録済み設定）')"));
    expect(source, contains('_moneyField(_overtime,'));
    expect(source, contains('_moneyField(_early,'));
    expect(source, contains('_moneyField(_night,'));
    expect(source, contains('_moneyField(_holiday,'));
  });
}
