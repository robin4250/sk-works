import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/sites/site_map_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('map reconciles each role by ID and keeps distinct same-name companies', () async {
    final client = SupabaseClient(
      'https://map-fixture.invalid',
      'fixture-key',
      httpClient: MockClient((request) async {
        final data = switch (request.url.pathSegments.last) {
          'site_map_workspace' => {
            'customers': [
              {'customer_id': 'billing', 'customer_name': '旧名称', 'address': '旧住所'},
              {'customer_id': 'separate', 'customer_name': '同名会社', 'address': '新住所'},
              {'customer_id': 'legacy-only', 'customer_name': '旧登録のみ', 'address': '保管住所'},
            ],
            'partners': [
              {'partner_id': 'payment', 'partner_name': '旧名称', 'address': '旧住所'},
            ],
          },
          'trade_company_workspace' => [
            {'id': 'company', 'trade_role': 'both', 'customer_id': 'billing',
              'partner_company_id': 'payment', 'name': '同名会社', 'address': '新住所'},
            {'id': 'no-address', 'trade_role': 'customer', 'customer_id': 'legacy-only',
              'name': '旧登録のみ', 'address': ''},
          ],
          _ => throw StateError('Unexpected map request'),
        };
        return http.Response(
          jsonEncode(data), 200, request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.dispose);

    final map = await SiteMapRepository(client).load();
    expect(map.customers.map((row) => row['customer_id']),
      ['billing', 'separate', 'legacy-only']);
    expect(map.customers.first['address'], '新住所');
    expect(map.customers.last['address'], '保管住所');
    expect(map.partners.single['partner_id'], 'payment');
    expect(map.partners.single['address'], '新住所');
    expect(map.partners.single['trade_company_id'], map.customers.first['trade_company_id']);
  });

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
    expect(page, contains("SkoLanguageController.tr('協力会社')"));
    expect(page, contains('enabled: data.partners.isNotEmpty'));
    expect(page, contains('if (widget.mode == SiteMapMode.admin)'));
  });
}
