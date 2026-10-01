import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../attendance/attendance_verification_repository.dart';

enum PersonalAttendanceState {
  notClockedIn,
  working,
  clockedOut,
}

class PersonalAttendanceStatus {
  const PersonalAttendanceStatus({
    required this.mode,
    required this.siteId,
    required this.siteName,
    required this.state,
    required this.clockInAt,
    required this.clockOutAt,
  });

  const PersonalAttendanceStatus.initial()
      : mode = 'manual',
        siteId = null,
        siteName = null,
        state = PersonalAttendanceState.notClockedIn,
        clockInAt = null,
        clockOutAt = null;

  final String mode;
  final String? siteId;
  final String? siteName;
  final PersonalAttendanceState state;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;

  String get modeLabel => switch (mode) {
        'location' => '位置情報',
        'location_photo' => '位置情報＋写真',
        _ => '手動',
      };

  String get siteLabel =>
      siteName?.trim().isNotEmpty == true ? siteName!.trim() : '未選択';

  bool get shouldHighlightClockOut => state == PersonalAttendanceState.working;

  bool get shouldHighlightClockIn =>
      state == PersonalAttendanceState.notClockedIn ||
      state == PersonalAttendanceState.clockedOut;
}

class PersonalAttendanceStatusRepository {
  PersonalAttendanceStatusRepository._(
    this._client,
    this._verificationRepository,
  );

  final SupabaseClient _client;
  final AttendanceVerificationRepository _verificationRepository;

  static PersonalAttendanceStatusRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    final verificationRepository =
        AttendanceVerificationRepository.maybeCreate();
    if (verificationRepository == null) return null;
    return PersonalAttendanceStatusRepository._(
      client,
      verificationRepository,
    );
  }

  Future<PersonalAttendanceStatus> load() async {
    final workerId = await _client.rpc('ensure_current_user_worker');
    final id = workerId?.toString() ?? '';
    if (id.isEmpty) {
      throw StateError('本人の作業員情報を確認できません。');
    }

    final settings = await _verificationRepository.loadSettings();
    final companyId = settings['company_id']?.toString() ?? '';
    final preferredSiteId =
        await _verificationRepository.loadPreferredSiteId();

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    final rows = await _client
        .from('attendance_verifications')
        .select(
          'event_type, confirmed_at, site_id, '
          'sites!attendance_verifications_site_id_fkey(id, name)',
        )
        .eq('company_id', companyId)
        .eq('worker_id', id)
        .gte('confirmed_at', start.toUtc().toIso8601String())
        .lt('confirmed_at', end.toUtc().toIso8601String())
        .order('confirmed_at');

    String? latestSiteId;
    String? latestSiteName;
    String? latestEvent;
    DateTime? latestAt;
    DateTime? clockInAt;
    DateTime? clockOutAt;

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final confirmed =
          DateTime.tryParse(row['confirmed_at']?.toString() ?? '')?.toLocal();
      if (confirmed == null) continue;

      final eventType = row['event_type']?.toString();
      if (eventType == 'clock_in') {
        clockInAt ??= confirmed;
      } else if (eventType == 'clock_out') {
        clockOutAt = confirmed;
      }

      if (latestAt == null || confirmed.isAfter(latestAt)) {
        latestAt = confirmed;
        latestEvent = eventType;
        latestSiteId = row['site_id']?.toString();
        final site = row['sites'];
        if (site is Map && site['name']?.toString().trim().isNotEmpty == true) {
          latestSiteName = site['name'].toString().trim();
        }
      }
    }

    final siteId = preferredSiteId ?? latestSiteId;
    String? siteName = latestSiteId == siteId ? latestSiteName : null;

    if (siteId != null && siteId.isNotEmpty && siteName == null) {
      final site = await _client
          .from('sites')
          .select('id, name')
          .eq('company_id', companyId)
          .eq('id', siteId)
          .maybeSingle();
      if (site != null) {
        final text = site['name']?.toString().trim() ?? '';
        if (text.isNotEmpty) siteName = text;
      }
    }

    final state = switch (latestEvent) {
      'clock_in' => PersonalAttendanceState.working,
      'clock_out' => PersonalAttendanceState.clockedOut,
      _ => PersonalAttendanceState.notClockedIn,
    };

    return PersonalAttendanceStatus(
      mode: settings['mode']?.toString() ?? 'manual',
      siteId: siteId,
      siteName: siteName,
      state: state,
      clockInAt: clockInAt,
      clockOutAt: clockOutAt,
    );
  }
}
