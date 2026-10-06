import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('site map prefers unified trade company master for customer and partner layers', () {
    final repository =
        File('lib/features/sites/site_map_repository.dart').readAsStringSync();

    expect(repository, contains("rpc('site_map_workspace')"));
    expect(repository, contains("rpc('trade_company_workspace')"));
    expect(repository, contains("_hasRole(row, 'customer')"));
    expect(repository, contains("_hasRole(row, 'subcontractor')"));
    expect(repository, contains("'customer_name': row['name']"));
    expect(repository, contains("'partner_name': row['name']"));
    expect(repository, contains("'address': row['address']"));
    expect(repository, contains('_mergeCompanyPlaces('));
  });

  test('map company layers ignore records without a usable address', () {
    final repository =
        File('lib/features/sites/site_map_repository.dart').readAsStringSync();

    expect(repository, contains("if (address.isEmpty || name.isEmpty) return;"));
    expect(repository, contains('for (final row in master)'));
    expect(repository, contains('for (final row in legacy)'));
  });

  test('site map keeps subcontractor selector on admin map', () {
    final page = File('lib/features/sites/site_map_page.dart').readAsStringSync();

    expect(page, contains('_MapLayer.partners'));
    expect(page, contains("SkoLanguageController.tr('下請け会社')"));
    expect(page, contains('enabled: data.partners.isNotEmpty'));
    expect(page, contains('if (widget.mode == SiteMapMode.admin)'));
  });
}
