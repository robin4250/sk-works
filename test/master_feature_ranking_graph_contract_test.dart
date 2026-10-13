import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master dashboard shows popular and low-usage feature graph', () {
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    expect(page, contains("'機能利用グラフ'"));
    expect(page, contains("'人気機能'"));
    expect(page, contains("'低利用機能（使用あり）'"));
    expect(page, contains('LinearProgressIndicator'));
    expect(page, contains('_lowUsageRows'));
    expect(page, contains('left.count.compareTo(right.count)'));
    expect(page, contains("'有効・未使用'"));
  });
}
