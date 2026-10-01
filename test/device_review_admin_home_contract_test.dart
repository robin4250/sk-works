import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device review admin home decisions stay fixed', () {
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(home, contains("'本日の出勤'"));
    expect(home, isNot(contains("'管理出勤'")));

    final attention = home.indexOf("'要対応'");
    final management = home.indexOf("const _SectionTitle('管理')");
    expect(attention, greaterThanOrEqualTo(0));
    expect(management, greaterThan(attention));

    expect(home, contains("'本日の勤務報告'"));
    expect(home, isNot(contains("'おはようございます、")));
    expect(home, contains("'未対応 ${attention.missingCount}件'"));
    expect(home, contains('Icons.notifications_active_outlined'));

    expect(home, contains("'人員'"));
    expect(home, contains("'管理現場'"));

    expect(home, contains('_HomeActionAccess.subAdmin'));
    expect(home, contains('_HomeActionAccess.admin'));
    expect(home, contains('_HomeActionAccess.professional'));
    expect(home, contains('class _ProfessionalAccessMark'));
    expect(home, contains('final background = scheme.surfaceContainerLowest;'));
    expect(home, isNot(contains('isSubAdmin ? scheme.primaryContainer')));

    expect(app, isNot(contains("label: '運用準備チェック'")));
  });
}
