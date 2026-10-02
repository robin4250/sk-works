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

    return SiteMapWorkspace(
      canViewAll: value['can_view_all'] == true,
      sites: rows('sites'),
      customers: rows('customers'),
      partners: rows('partners'),
      workers: rows('workers'),
      company: object('company'),
      home: object('home'),
      employeeHomes: rows('employee_homes'),
    );
  }
}
