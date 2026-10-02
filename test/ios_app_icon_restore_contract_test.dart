import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS preparation restores AppIcon sizes from the formal SKO icon', () {
    final prepare = File('tool/prepare_ios.sh').readAsStringSync();

    expect(prepare, contains('SKO正式アイコン.png'));
    expect(prepare, contains('SKO-AppIcon-1024.png'));
    expect(prepare, contains('Contents.json'));
    expect(prepare, contains('sips'));
    expect(prepare, isNot(contains('generate_ios_app_icon.swift')));
    expect(
      prepare,
      contains('正式AppIcon元画像が見つかりません。仮アイコンは生成しません。'),
    );
  });
}
