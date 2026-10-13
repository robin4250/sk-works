import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat appearance defaults match product specification', () {
    final page =
        File('lib/features/chat/chat_appearance_page.dart').readAsStringSync();

    expect(page, contains('this.backgroundOpacity = 100'));
    expect(page, contains("defaults_20261003"));
    expect(page, contains("setInt(_key(groupId, 'background'), 100)"));
    expect(page, contains("setInt(_key(groupId, 'header'), 80)"));
    expect(page, contains("setInt(_key(groupId, 'footer'), 80)"));
    expect(page, contains("setInt(_key(groupId, 'bubble'), 80)"));
    expect(page, contains('this.headerOpacity = 80'));
    expect(page, contains('this.footerOpacity = 80'));
    expect(page, contains('this.bubbleOpacity = 80'));
    expect(page, contains("?? 100).clamp(1, 100)"));
    expect(page, contains("?? 80).clamp(1, 100)"));
  });
}
