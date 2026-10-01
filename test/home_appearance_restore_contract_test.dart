import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home appearance is personal and never allows zero opacity', () {
    final appearance =
        File('lib/features/home/home_appearance.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

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
    expect(home, contains('appearance.headerOpacity'));
    expect(app, contains('_homeAppearance.footerOpacity'));
    expect(app, contains("'壁紙・透明度を設定'"));
  });
}
