import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/active_country_pack.dart';
import 'package:sk_works/international/core/language_pack.dart';
import 'package:sk_works/international/language_pack_registry.dart';
import 'package:sk_works/international/market_selection.dart';

void main() {
  test('English display retains Japanese country rules', () {
    final selection = MarketSelection.fromDeviceLocale(
      languageCode: 'en-US', countryCode: 'US',
    );
    expect(selection.language.languageCode, 'en');
    expect(selection.country.countryCode, 'JP');
    expect(selection.country.currencyCode, 'JPY');
    expect(activeCountryPack.countryCode, 'JP');
  });

  test('templates translate only fixed wording and preserve inserted data', () {
    final pack = LanguagePackRegistry.resolve('en');
    expect(pack.format('単価の参照元：{source}', {'source': '株式会社テスト'}),
        'Rate source: 株式会社テスト');
    expect(pack.format('保存できませんでした: {error}', {'error': '{source} 日本語エラー'}),
        'Could not save: {source} 日本語エラー');
    expect(pack.format('未知の文言：{value}', {'value': '123円'}), '未知の文言：123円');
  });

  test('missing parameters remain visible and null becomes empty', () {
    const pack = LanguagePack(languageCode: 'en', fallbackLanguageCode: 'ja');
    expect(pack.format('{missing}/{empty}', {'empty': null}), '{missing}/');
  });

  test('new fixed feature and money warnings have English resources', () {
    final pack = LanguagePackRegistry.resolve('en');
    for (final source in ['利用機能のON／OFF', '旧単価（登録済み設定）',
      '打刻済み・日報未確定', '単価の参照元', '再試行', '設定を確認']) {
      expect(pack.strings.containsKey(source), isTrue, reason: source);
      expect(pack.translate(source), isNot(source));
    }
    expect(pack.translate('未翻訳の項目'), '未翻訳の項目');
  });
}
