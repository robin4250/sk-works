import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class SiteMapWorkspace {
  const SiteMapWorkspace({
    required this.canViewAll,
    required this.sites,
    required this.customers,
    required this.partners,
    required this.workers,
  });

  final bool canViewAll;
  final List<Map<String, dynamic>> sites;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> partners;
  final List<Map<String, dynamic>> workers;
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

    return SiteMapWorkspace(
      canViewAll: value['can_view_all'] == true,
      sites: rows('sites'),
      customers: rows('customers'),
      partners: rows('partners'),
      workers: rows('workers'),
    );
  }
}