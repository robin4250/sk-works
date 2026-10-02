import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS release scripts require the production SKO bundle identifier', () {
    final preflight = File('tool/testflight_preflight.sh').readAsStringSync();
    final prepare = File('tool/prepare_ios.sh').readAsStringSync();

    expect(preflight, contains('com.skworks.skWorks'));
    expect(prepare, contains('BUNDLE_ID="com.skworks.skWorks"'));
    expect(
      preflight,
      isNot(contains(
        r'[[ "$bundle" == "com.robin4250.sko" ]] && ok "Bundle Identifier',
      )),
    );
  });

  test('prepare_ios uses the formal icon and never regenerates the placeholder', () {
    final script = File('tool/prepare_ios.sh').readAsStringSync();

    expect(script, contains('SKO正式アイコン.png'));
    expect(script, contains('正式AppIcon元画像が見つかりません。仮アイコンは生成しません。'));
    expect(script, isNot(contains('xcrun swift tool/generate_ios_app_icon.swift')));
  });
}
