import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS preparation always restores the branded SKO app icon', () {
    final prepare = File('tool/prepare_ios.sh').readAsStringSync();
    final generator =
        File('tool/generate_ios_app_icon.swift').readAsStringSync();

    expect(prepare, contains('SKO-AppIcon-1024.png'));
    expect(prepare, contains('generate_ios_app_icon.swift'));
    expect(prepare, contains('Contents.json'));
    expect(prepare, contains('sips'));
    expect(generator, contains('HelveticaNeue-BoldItalic'));
    expect(generator, contains('let logo = "SKO"'));
    expect(generator, contains('NSColor.white'));
  });
}
