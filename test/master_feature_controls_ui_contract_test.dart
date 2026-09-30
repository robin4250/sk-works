import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('master feature controls UI is reversible and confirmation based', () {
    final page = File(
      'lib/features/settings/master_feature_controls_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/settings/master_feature_controls_repository.dart',
    ).readAsStringSync();

    expect(page, contains('Master 機能設定'));
    expect(page, contains('既存データや履歴は削除しません'));
    expect(page, contains('再びONにすると'));
    expect(page, contains('車両管理'));
    expect(page, contains('ルート・配車'));
    expect(page, contains('一時停止する'));
    expect(repository, contains("'current_master_feature_flags'"));
    expect(repository, contains("'set_master_feature_enabled'"));
  });

  test('master feature controls are not exposed before dedicated master gate', () {
    final settings =
        File('lib/features/settings/settings_page.dart').readAsStringSync();

    expect(settings, isNot(contains('MasterFeatureControlsPage')));
  });
}
