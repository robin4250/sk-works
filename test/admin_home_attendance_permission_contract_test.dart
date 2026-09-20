import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin attendance card requires explicit attendance permission', () {
    final source =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(
      source,
      contains(
        "moduleEnabled('attendance') &&\n            identity.can('can_manage_attendance')",
      ),
    );
  });
}
