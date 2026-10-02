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
    expect(attention, greaterThanOrEqualTo(0));
    expect(RegExp(r"'要対応'").allMatches(home).length, equals(1));
    expect(home, contains('_OrderedHomeContent'));
    expect(home, contains('actionOrder'));
    expect(home, contains('visibleHomeKeys'));

    expect(home, contains("'本日の勤務報告'"));
    expect(home, contains("SkoLanguageController.tr('未対応')"));
    expect(home, contains('Icons.notifications_active_outlined'));
    expect(home, contains('repeat(reverse: true)'));

    expect(app, contains("SkoLanguageController.tr('社員')"));
    expect(app, contains("SkoLanguageController.tr('管理現場')"));
    expect(home, contains('_HomeActionAccess.subAdmin'));
    expect(home, contains('_HomeActionAccess.admin'));
    expect(home, contains('_HomeActionAccess.professional'));
    expect(home, contains('class _ProfessionalAccessMark'));
    expect(home, contains('final background = scheme.surfaceContainerLowest;'));
    expect(home, isNot(contains('isSubAdmin ? scheme.primaryContainer')));

    expect(app, isNot(contains("label: '運用準備チェック'")));
    expect(app, contains('_identity.companyName'));
    expect(app, contains('_identity.displayName'));
    expect(app, contains('now.year'));
    final homeStart = app.indexOf('Widget _homeDashboard()');
    final homeEnd = app.indexOf('List<_HomeLayoutItem> get _homeLayoutItems');
    expect(homeStart, greaterThanOrEqualTo(0));
    expect(homeEnd, greaterThan(homeStart));
    final homeDashboard = app.substring(homeStart, homeEnd);
    expect(homeDashboard, contains('extendBodyBehindAppBar: false'));
    expect(homeDashboard, contains('preferredSize: Size.fromHeight(_chromeVisible ? 64 : 0)'));
    expect(homeDashboard, contains('toolbarHeight: _chromeVisible ? 64 : 0'));
    expect(homeDashboard, contains('contentTopInset: 8'));
    expect(homeDashboard, contains('forceMaterialTransparency: true'));
    expect(homeDashboard, contains('return Stack('));
    expect(homeDashboard, contains('surfaceContainerHighest'));
    expect(homeDashboard, contains('bodyAppearance = _homeAppearance.copyWith(clearWallpaper: true)'));
    expect(homeDashboard, contains('flexibleSpace: ColoredBox('));
    expect(homeDashboard, contains('_homeAppearance.headerOpacity'));
    expect(homeDashboard, contains('Colors.white.withValues('));
    expect(homeDashboard, contains('_homeAppearance.wallpaperOpacity'));
    expect(homeDashboard, contains('_chromeVisible'));
    expect(homeDashboard, isNot(contains('AnimatedContainer(')));
  });
}
