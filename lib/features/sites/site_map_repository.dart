import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class SiteMapWorkspace {
  const SiteMapWorkspace({
    required this.canViewAll,
    required this.sites,
    required this.customers,
    required this.partners,
    required this.workers,
    required this.company,
    required this.home,
    required this.employeeHomes,
  });

  final bool canViewAll;
  final List<Map<String, dynamic>> sites;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> partners;
  final List<Map<String, dynamic>> workers;
  final Map<String, dynamic>? company;
  final Map<String, dynamic>? home;
  final List<Map<String, dynamic>> employeeHomes;
}

class SiteMapRepository {
  SiteMapRepository._(this._client);

  final SupabaseClient _client;

  static SiteMapRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return SiteMapRepository._(client);
  }

  Future<SiteMapWorkspace> load() async {
    final raw = await _client.rpc('site_map_workspace');
    final value = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};

    List<Map<String, dynamic>> rows(String key) {
      final rawRows = value[key];
      if (rawRows is! List) return const [];
      return rawRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }

    Map<String, dynamic>? object(String key) {
      final rawObject = value[key];
      if (rawObject is! Map) return null;
      final map = Map<String, dynamic>.from(rawObject);
      return map.isEmpty ? null : map;
    }

    final legacyCustomers = rows('customers');
    final legacyPartners = rows('partners');
    var customers = legacyCustomers;
    var partners = legacyPartners;

    // The site-map RPC predates the unified trade-company master and still
    // reads customers.billing_address / partner_companies.address. Prefer the
    // current trade-company master so an address registered on the current
    // 取引会社 / 下請け会社 screen immediately becomes selectable on the map.
    try {
      final tradeRaw = await _client.rpc('trade_company_workspace');
      if (tradeRaw is List) {
        final tradeRows = tradeRaw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);

        customers = _mergeCompanyPlaces(
          master: tradeRows
              .where((row) => _hasRole(row, 'customer'))
              .map(
                (row) => {
                  'trade_company_id': row['id'],
                  'customer_id': row['customer_id'],
                  'customer_name': row['name']?.toString() ?? '',
                  'address': row['address']?.toString() ?? '',
                },
              )
              .toList(growable: false),
          legacy: legacyCustomers,
          nameKey: 'customer_name',
        );

        partners = _mergeCompanyPlaces(
          master: tradeRows
              .where((row) => _hasRole(row, 'subcontractor'))
              .map(
                (row) => {
                  'trade_company_id': row['id'],
                  'partner_id': row['partner_company_id'],
                  'partner_name': row['name']?.toString() ?? '',
                  'address': row['address']?.toString() ?? '',
                },
              )
              .toList(growable: false),
          legacy: legacyPartners,
          nameKey: 'partner_name',
        );
      }
    } catch (_) {
      // Older/non-management accounts can still use the legacy map workspace.
    }

    return SiteMapWorkspace(
      canViewAll: value['can_view_all'] == true,
      sites: rows('sites'),
      customers: customers,
      partners: partners,
      workers: rows('workers'),
      company: object('company'),
      home: object('home'),
      employeeHomes: rows('employee_homes'),
    );
  }

  static bool _hasRole(Map<String, dynamic> row, String role) {
    final value = row['trade_role']?.toString() ?? '';
    return value == role || value == 'both';
  }

  static List<Map<String, dynamic>> _mergeCompanyPlaces({
    required List<Map<String, dynamic>> master,
    required List<Map<String, dynamic>> legacy,
    required String nameKey,
  }) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};

    void add(Map<String, dynamic> row) {
      final address = row['address']?.toString().trim() ?? '';
      final name = row[nameKey]?.toString().trim() ?? '';
      if (address.isEmpty || name.isEmpty) return;
      final key = '${name.toLowerCase()}|${address.toLowerCase()}';
      if (!seen.add(key)) return;
      result.add(row);
    }

    for (final row in master) {
      add(row);
    }
    for (final row in legacy) {
      add(row);
    }
    return List.unmodifiable(result);
  }
}
