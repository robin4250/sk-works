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
      contains('if (widget.allowEmployeeHomes)'),
    );
    expect(
      map,
      contains(
        'if (!value.canViewAll || !widget.allowEmployeeHomes)',
      ),
    );
  });
}
