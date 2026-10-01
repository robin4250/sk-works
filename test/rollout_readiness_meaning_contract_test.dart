import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rollout readiness 3/3 means worker site and communication group', () {
    final page = File(
      'lib/features/settings/rollout_readiness_page.dart',
    ).readAsStringSync();

    expect(page, contains("title: '作業員マスター'"));
    expect(page, contains("title: '現場マスター'"));
    expect(page, contains("title: '通信グループ'"));

    expect(page, contains("title: '勤怠実績'"));
    expect(page, contains('informational: true'));

    expect(
      page,
      contains(
        "final required = checks.where((item) => !item.informational).toList();",
      ),
    );
    expect(page, contains("final groups = _count('communication_groups');"));
  });

  test('LINE linkage is separate from SKO communication group readiness', () {
    final page = File(
      'lib/features/settings/rollout_readiness_page.dart',
    ).readAsStringSync();

    expect(page, contains("title: '通信グループ'"));
    expect(page, contains("title: 'LINEグループ連携'"));
    expect(page, contains("_count('active_line_bindings')"));
  });
}
