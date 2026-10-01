import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attention card keeps the fixed blinking bell treatment', () {
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(home, contains('class _AttentionBlinkingBell'));
    expect(home, contains('AnimationController('));
    expect(home, contains('..repeat(reverse: true)'));
    expect(home, contains('FadeTransition('));
    expect(home, contains('Icons.notifications_active_outlined'));
    expect(home, contains('_AttentionBlinkingBell(color: scheme.onPrimary)'));
  });
}
