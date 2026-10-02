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
    expect(appearance, contains('this.buttonOpacity = 0.6'));
    expect(appearance, contains('this.cardOpacity = 0.6'));
    expect(appearance, contains('this.headerOpacity = 0.6'));
    expect(appearance, contains('this.footerOpacity = 0.6'));
    expect(appearance, contains('fallback = 0.6'));
    expect(app, contains('Colors.white.withValues('));
    expect(app, contains('alpha: _homeAppearance.headerOpacity'));
    expect(theme, contains('backgroundColor: Colors.white'));
    expect(app, contains('withValues(alpha: _homeAppearance.footerOpacity)'));
    expect(app, contains("'背景・ヘッダー・フッター設定'"));
  });
}
