import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled company modules are blocked across all primary routes', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("'clock_in' || 'clock_out'"));
    expect(app, contains("const _ModuleDisabledPage(label: '出勤表')"));
    expect(app, contains("const _ModuleDisabledPage(label: '現場')"));
    expect(app, contains("const _ModuleDisabledPage(label: 'チャット')"));
    expect(app, contains('この機能は会社設定でOFFになっています'));
    expect(home, contains("moduleEnabled('attendance')"));
    expect(home, contains("moduleEnabled('invoices')"));
  });
}
