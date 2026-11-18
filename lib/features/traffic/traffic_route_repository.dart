import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'traffic_shortcut_store.dart';

enum TrafficRouteTarget { home, company }

enum TrafficRouteProblem { addressMissing, permissionDenied, locationOff }

class TrafficRouteException implements Exception {
  const TrafficRouteException(this.problem);
  final TrafficRouteProblem problem;
}

typedef TrafficRouteLoader =
    Future<Uri> Function(TrafficShortcutScope scope, TrafficRouteTarget target);

Uri trafficTransitUri({
  required double latitude,
  required double longitude,
  required String destination,
}) => Uri.https('www.google.com', '/maps/dir/', {
  'api': '1',
  'origin': '$latitude,$longitude',
  'destination': destination.trim(),
  'travelmode': 'transit',
});

class TrafficRouteRepository {
  TrafficRouteRepository(this._client);

  final SupabaseClient _client;

  static TrafficRouteRepository? maybeCreate() => SupabaseBackend.isInitialized
      ? TrafficRouteRepository(SupabaseBackend.client)
      : null;

  Future<Uri> load(
    TrafficShortcutScope scope,
    TrafficRouteTarget target,
  ) async {
    final session = _client.auth.currentSession;
    void checkSession() {
      if (session == null ||
          session.isExpired ||
          session.user.id != scope.actorId ||
          _client.auth.currentSession?.accessToken != session.accessToken) {
        throw StateError('Traffic session changed');
      }
    }

    checkSession();
    final authorization = 'Bearer ${session!.accessToken}';
    final memberships = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', scope.actorId)
        .limit(2)
        .setHeader('Authorization', authorization);
    checkSession();
    if (memberships.length != 1 ||
        memberships.single['company_id'] != scope.companyId) {
      throw StateError('Traffic company scope changed');
    }
    final Object? row = switch (target) {
      TrafficRouteTarget.home =>
        await _client
            .rpc('current_worker_personnel_profile')
            .setHeader('Authorization', authorization),
      TrafficRouteTarget.company =>
        await _client
            .from('companies')
            .select('address')
            .eq('id', scope.companyId)
            .single()
            .setHeader('Authorization', authorization),
    };
    checkSession();
    if (row != null && row is! Map) {
      throw StateError('Traffic address unavailable');
    }
    final address = row is Map ? row['address']?.toString().trim() : null;
    if (address == null || address.isEmpty) {
      throw const TrafficRouteException(TrafficRouteProblem.addressMissing);
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const TrafficRouteException(TrafficRouteProblem.locationOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const TrafficRouteException(TrafficRouteProblem.permissionDenied);
    }
    checkSession();
    late final Position origin;
    try {
      origin = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on PermissionDeniedException {
      throw const TrafficRouteException(TrafficRouteProblem.permissionDenied);
    } on LocationServiceDisabledException {
      throw const TrafficRouteException(TrafficRouteProblem.locationOff);
    }
    checkSession();
    return trafficTransitUri(
      latitude: origin.latitude,
      longitude: origin.longitude,
      destination: address,
    );
  }
}
