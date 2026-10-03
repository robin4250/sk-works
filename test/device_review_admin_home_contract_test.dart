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

    expect(home, contains("'本日の勤怠報告'"));
    expect(home, contains("SkoLanguageController.tr('未対応')"));
    expect(home, contains('Icons.notifications_active_outlined'));
    expect(home, contains('repeat(reverse: true)'));

    expect(app, contains("SkoLanguageController.tr('社員データ')"));
    expect(app, contains("SkoLanguageController.tr('管理現場')"));
    expect(home, contains('HomeShortcutAccess.subAdmin'));
    expect(home, contains('HomeShortcutAccess.viewer'));
    expect(home, contains('HomeShortcutAccess.admin'));
    expect(home, isNot(contains('_ProfessionalAccessMark')));
    expect(home, contains('final borderWidth = isAdmin ? 4.0'));
    expect(home, contains('if (isViewer)'));
    expect(home, contains('padding: const EdgeInsets.all(3)'));
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
    expect(homeDashboard, contains('extendBodyBehindAppBar: true'));
    expect(homeDashboard, contains('preferredSize: Size.fromHeight(_chromeVisible ? 64 : 0)'));
    expect(homeDashboard, contains('toolbarHeight: _chromeVisible ? 64 : 0'));
    expect(homeDashboard, contains('contentTopInset: _chromeVisible ? 72 : 8'));
    expect(homeDashboard, contains('forceMaterialTransparency: true'));
    expect(homeDashboard, contains('return Stack('));
    expect(homeDashboard, contains('Theme.of(context).scaffoldBackgroundColor'));
    expect(homeDashboard, isNot(contains('surfaceContainerHighest')));
    expect(homeDashboard, contains('bodyAppearance = _homeAppearance.copyWith(clearWallpaper: true)'));
    expect(homeDashboard, contains('flexibleSpace: ColoredBox('));
    expect(homeDashboard, contains('_homeAppearance.headerOpacity'));
    expect(homeDashboard, contains('Colors.white.withValues('));
    expect(homeDashboard, contains('alpha: _homeAppearance.headerOpacity'));
    expect(homeDashboard, contains('backgroundColor: Colors.transparent'));
    expect(homeDashboard, contains('_homeAppearance.wallpaperOpacity'));
    expect(homeDashboard, contains('_chromeVisible'));
    expect(homeDashboard, isNot(contains('AnimatedContainer(')));
  });
}
