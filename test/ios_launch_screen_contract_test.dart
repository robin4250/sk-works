import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS launch screen never renders the app icon as a fullscreen image', () {
    final prepare = File('tool/prepare_ios.sh').readAsStringSync();

    expect(prepare, contains('LaunchScreen.storyboard'));
    expect(prepare, contains('text="SKO"'));
    expect(prepare, contains('pointSize="30"'));
    expect(prepare, contains('sko-launch-title'));
    expect(
      prepare,
      isNot(contains('<imageView')),
    );
  });
}
