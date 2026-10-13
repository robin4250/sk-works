import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('generation attention opens notification center', () {
    final home = read('lib/features/home/friendly_home_content.dart');
    final app = read('lib/app_v2.dart');

    expect(home, contains("widget.onOpen('notifications')"));
    expect(home, isNot(contains('generationIssueCount > 0')));
    expect(home, isNot(contains("? 'approvals'")));
    expect(app, contains("case 'notifications':"));
    expect(app, contains('NotificationsPage'));
  });
}
