import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../attendance/attendance_verification_repository.dart';
import 'weather_forecast_policy.dart';

class HomeWeatherLocation {
  const HomeWeatherLocation({
    required this.selection,
    this.companyAddressMissing = false,
  });
  final WeatherAddressSelection selection;
  final bool companyAddressMissing;
}

/// Reads only the actor's current company/personnel/selected active site.
class HomeWeatherLocationRepository {
  HomeWeatherLocationRepository._(this._client);
  @visibleForTesting
  factory HomeWeatherLocationRepository.forTesting(SupabaseClient client) =>
      HomeWeatherLocationRepository._(client);
  final SupabaseClient _client;

  static HomeWeatherLocationRepository? maybeCreate() =>
      SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser != null
      ? HomeWeatherLocationRepository._(SupabaseBackend.client)
      : null;

  Future<HomeWeatherLocation> load(HomeAttendanceStatus status) async {
    final actor = _client.auth.currentUser?.id;
    if (actor == null) {
      throw StateError('Weather location unavailable');
    }
    void checkActor() {
      if (_client.auth.currentUser?.id != actor) {
        throw StateError('Session changed');
      }
    }

    final memberships = await _client
        .from('company_members')
        .select('company_id,role')
        .eq('user_id', actor)
        .limit(2);
    checkActor();
    if (memberships.isEmpty) {
      return const HomeWeatherLocation(
        selection: WeatherAddressSelection(
          WeatherAddressKind.unavailable,
          null,
        ),
        companyAddressMissing: true,
      );
    }
    if (memberships.length != 1) {
      throw StateError('Company selection unavailable');
    }
    final companyId = memberships.single['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw StateError('Company selection unavailable');
    }
    final companies = await _client
        .from('companies')
        .select('address')
        .eq('id', companyId)
        .limit(1);
    checkActor();
    // An inaccessible row is not evidence that the company has no address.
    if (companies.length != 1) {
      throw StateError('Company address unavailable');
    }
    final company = companies.single['address']?.toString();
    final role = memberships.single['role'];
    final admin = role == 'owner' || role == 'admin';
    String? home;
    String? site;
    if (!admin) {
      final personnel = await _client.rpc('current_worker_personnel_profile');
      checkActor();
      if (personnel != null && personnel is! Map) {
        throw StateError('Personnel unavailable');
      }
      home = personnel is Map ? personnel['address']?.toString() : null;
      if (status.phase == HomeAttendancePhase.unknown) {
        throw StateError('Attendance unavailable');
      }
      if (status.phase == HomeAttendancePhase.working &&
          status.openShifts.length == 1) {
        final shift = status.openShifts.single;
        // A route's clock-in site is not proof of the current visit destination.
        final siteId = (shift.routeId?.trim().isNotEmpty ?? false)
            ? null
            : shift.siteId;
        if (siteId != null && siteId.isNotEmpty) {
          final sites = await _client
              .from('sites')
              .select('address')
              .eq('company_id', companyId)
              .eq('id', siteId)
              .limit(1);
          checkActor();
          if (sites.length != 1) {
            throw StateError('Site address unavailable');
          }
          site = sites.single['address']?.toString();
        }
      }
    }
    final selection = selectWeatherAddress(
      companyAddress: company,
      homeAddress: home,
      activeSiteAddress: site,
      working: status.phase == HomeAttendancePhase.working,
      isAdministrator: admin,
    );
    final companyRequired = admin || home == null || home.trim().isEmpty;
    return HomeWeatherLocation(
      selection: selection,
      companyAddressMissing:
          companyRequired && (company == null || company.trim().isEmpty),
    );
  }
}
