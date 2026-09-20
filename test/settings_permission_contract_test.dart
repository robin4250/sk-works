import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud company settings are gated by owner/admin role', () {
    final source = File('lib/features/settings/settings_page.dart').readAsStringSync();

    expect(source, contains("_canManageCompany = role == 'owner' || role == 'admin';"));
    expect(source, contains('enabled: !_usesCloud || _canManageCompany'));
    expect(source, contains('会社設定は管理者のみ変更できます'));
    expect(
      source,
      contains('_saving || (_usesCloud && !_canManageCompany)'),
    );
  });
}
