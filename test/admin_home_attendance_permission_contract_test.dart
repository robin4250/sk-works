import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all roles keep personal clock in/out while management stays permissioned', () {
    final source =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(
      source,
      contains('一般ユーザー・サブ管理者・管理者の全員が、自分自身の出勤・退勤を登録できます。'),
    );
    expect(source, contains("onOpen('clock_in')"));
    expect(source, contains("onOpen('clock_out')"));

    expect(
      source,
      contains(
        "moduleEnabled('attendance') &&\n"
        "            identity.can('can_manage_attendance')",
      ),
    );
    expect(source, contains('出勤状況を確認'));
  });
}
