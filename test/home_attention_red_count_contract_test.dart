import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home attention unresolved label and count are red', () {
    final source = File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    expect(source, contains("SkoLanguageController.tr('未対応')"));
    expect(source, contains('widget.attention.unresolvedCount'));
    expect(source, contains('color: scheme.error'));
  });
}
