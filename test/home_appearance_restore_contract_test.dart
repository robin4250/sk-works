import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home appearance is personal and never allows zero opacity', () {
    final appearance =
        File('lib/features/home/home_appearance.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();
    final theme = File('lib/branding/sko_theme.dart').readAsStringSync();

    expect(appearance, contains("sko_home_appearance_"));
    expect(appearance, contains("defaults_20261003"));
    expect(appearance, contains("setDouble(_key('wallpaper_opacity'), 1.0)"));
    expect(appearance, contains("setDouble(_key('button_opacity'), 0.8)"));
    expect(appearance, contains("setDouble(_key('card_button_opacity'), 1.0)"));
    expect(appearance, contains("setDouble(_key('card_opacity'), 0.8)"));
    expect(appearance, contains("setDouble(_key('header_opacity'), 0.8)"));
    expect(appearance, contains("setDouble(_key('footer_opacity'), 0.8)"));
    expect(appearance, contains('getApplicationSupportDirectory'));
    expect(appearance, contains('min: 0.01'));
    expect(appearance, contains('divisions: 99'));
    expect(appearance, contains("'壁紙の透明度'"));
    expect(appearance, contains("'機能ボタンの透明度'"));
    expect(appearance, contains("'カードの透明度'"));
    expect(appearance, contains("'ヘッダーの透明度'"));
    expect(appearance, contains("'フッターの透明度'"));
    expect(appearance, contains('他ユーザーへ影響しません'));

    expect(home, contains('appearance.wallpaperOpacity'));
    expect(home, contains('appearance.buttonOpacity'));
    expect(home, contains('appearance.cardOpacity'));
    expect(app, contains('_homeAppearance.headerOpacity'));
    expect(app, contains('_homeAppearance.footerOpacity'));
    expect(appearance, contains('this.buttonOpacity = 0.8'));
    expect(appearance, contains('this.cardOpacity = 0.8'));
    expect(appearance, contains('this.headerOpacity = 0.8'));
    expect(appearance, contains('this.footerOpacity = 0.8'));
    expect(appearance, contains("buttonOpacity: _read(prefs, 'button_opacity', fallback: 0.8)"));
    expect(appearance, contains("cardOpacity: _read(prefs, 'card_opacity', fallback: 0.8)"));
    expect(appearance, contains("headerOpacity: _read(prefs, 'header_opacity', fallback: 0.8)"));
    expect(appearance, contains("footerOpacity: _read(prefs, 'footer_opacity', fallback: 0.8)"));
    expect(app, contains('opacity: _homeAppearance.headerOpacity'));
    expect(app, contains('backgroundColor: Colors.white'));
    expect(app, isNot(contains('flexibleSpace: ColoredBox(')));
    expect(theme, contains('backgroundColor: Colors.white'));
    expect(app, contains('Theme.of(context).scaffoldBackgroundColor'));
    expect(app, contains('extendBodyBehindAppBar: true'));
    expect(app, contains('contentTopInset: _chromeVisible ? 72 : 8'));
    expect(app, isNot(contains('colorScheme.surfaceContainerHighest')));
    expect(app, contains('withValues(alpha: _homeAppearance.footerOpacity)'));
    expect(app, contains("'背景・ヘッダー・フッター設定'"));
  });
}
