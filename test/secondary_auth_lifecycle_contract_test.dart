import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secondary auth relocks when app leaves foreground', () {
    final source =
        File('lib/features/auth/secondary_protected_page.dart')
            .readAsStringSync();

    expect(source, contains('with WidgetsBindingObserver'));
    expect(source, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(source, contains('didChangeAppLifecycleState'));
    expect(source, contains('AppLifecycleState.paused'));
    expect(source, contains('AppLifecycleState.inactive'));
    expect(source, contains('_unlocked = false'));
    expect(source, contains('WidgetsBinding.instance.removeObserver(this)'));
  });
}
