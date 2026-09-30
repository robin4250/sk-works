import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master dashboard exposes aggregate future plan analysis indicators', () {
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    expect(page, contains("'将来プラン分析指標'"));
    expect(page, contains("'30日利用率 %'"));
    expect(page, contains("'30日 1社あたり利用回数'"));
    expect(page, contains("'1社あたり利用者 平均'"));
    expect(page, contains("'1社あたりストレージ 平均MB'"));
    expect(page, contains("'会社間連携率 %'"));
    expect(page, contains("'30日継続率 %'"));
    expect(page, contains('個別会社のプラン判定や会社名・ID表示は行いません'));
  });
}
