import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin and general site maps use separate modes and entries', () {
    final map = File('lib/features/sites/site_map_page.dart').readAsStringSync();
    final sites =
        File('lib/features/sites/site_cloud_page.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(map, contains('enum SiteMapMode { general, admin }'));
    expect(map, contains('class GeneralSiteMapPage'));
    expect(map, contains('mode: SiteMapMode.general'));
    expect(map, contains('class AdminSiteMapPage'));
    expect(map, contains('mode: SiteMapMode.admin'));
    expect(
      map,
      contains('bool get allowEmployeeHomes => mode == SiteMapMode.admin'),
    );
    expect(sites, contains('const GeneralSiteMapPage()'));
    expect(app, contains('const AdminSiteMapPage()'));
    expect(
      app,
      isNot(
        contains(
          "SiteMapPage(\n          allowEmployeeHomes: true",
        ),
      ),
    );
  });

  test('general map never exposes all employee homes', () {
    final map = File('lib/features/sites/site_map_page.dart').readAsStringSync();

    expect(
      map,
      contains('if (data.canViewAll && widget.allowEmployeeHomes)'),
    );
    expect(
      map,
      contains(
        'if (!scoped.canViewAll || !widget.allowEmployeeHomes)',
      ),
    );
  });

  test('map layer checks are one-shot and clear after opening map', () {
    final map = File('lib/features/sites/site_map_page.dart').readAsStringSync();

    expect(map, contains('_layers = <_MapLayer>{};'));
    expect(map, contains('void _clearMapSelection()'));
    expect(map, contains('setState(_layers.clear);'));
    expect(map, contains('_clearMapSelection();'));
    expect(map, isNot(contains('_saveLayerPreferences')));
  });

  test('notification map entry opens the general map', () {
    final notifications = File(
      'lib/features/notifications/notifications_page.dart',
    ).readAsStringSync();

    expect(notifications, contains('const GeneralSiteMapPage()'));
    expect(notifications, isNot(contains('const SiteMapPage()')));
  });
}
