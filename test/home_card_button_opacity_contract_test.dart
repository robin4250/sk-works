import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home card buttons have an independent opacity setting defaulting to 100 percent', () {
    final appearance = File(
      'lib/features/home/home_appearance.dart',
    ).readAsStringSync();
    final home = File(
      'lib/features/home/friendly_home_content.dart',
    ).readAsStringSync();

    expect(appearance, contains('this.cardButtonOpacity = 1'));
    expect(appearance, contains('final double cardButtonOpacity'));
    expect(appearance, contains("'card_button_opacity'"));
    expect(appearance, contains("fallback: 1"));
    expect(appearance, contains("'カード上ボタンの透明度'"));
    expect(appearance, contains('cardButtonOpacity:'));

    expect(home, contains('appearance.cardButtonOpacity'));
    expect(home, contains('required this.buttonOpacity'));
    expect(home, contains('opacity: buttonOpacity'));
    expect(home, contains("'本日の勤怠報告'"));
    expect(home, contains("'本日の出勤'"));
  });
}
