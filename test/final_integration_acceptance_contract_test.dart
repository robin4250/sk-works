import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iPhone acceptance test covers final integrated modules', () {
    final doc = File('docs/IPHONE_ACCEPTANCE_TEST.md').readAsStringSync();

    expect(doc, contains('## M. 現場チャット連動'));
    expect(doc, contains('## N. 車両・ルート'));
    expect(doc, contains('## O. Master管理'));
    expect(doc, contains('15分'));
    expect(doc, contains('個別情報が表示されない'));
    expect(doc, contains('車両・ルート'));
  });
}
