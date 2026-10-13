import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class TodayAttendanceRecord {
  const TodayAttendanceRecord({
    required this.workerId,
    required this.workerName,
    required this.affiliation,
    required this.partnerCompanyName,
    required this.siteName,
    required this.lastEventType,
    required this.lastConfirmedAt,
    required this.clockInAt,
    required this.clockOutAt,
  });

  final String workerId;
  final String workerName;
  final String affiliation;
  final String? partnerCompanyName;
  final String? siteName;
  final String? lastEventType;
  final DateTime? lastConfirmedAt;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;

  bool get isPartner => affiliation == 'partner_company';
  bool get isWorking => lastEventType == 'clock_in';

  String get companyLabel =>
      isPartner && partnerCompanyName?.trim().isNotEmpty == true
          ? partnerCompanyName!.trim()
          : (isPartner ? '下請け' : '自社');
}


class TodayAttendanceHistoryDay {
  const TodayAttendanceHistoryDay({
    required this.date,
    required this.records,
  });

  final DateTime date;
  final List<TodayAttendanceRecord> records;

  List<TodayAttendanceRecord> get ownCompany =>
      records.where((record) => !record.isPartner).toList(growable: false);

  List<TodayAttendanceRecord> get subcontractors =>
      records.where((record) => record.isPartner).toList(growable: false);
}

class TodayAttendanceSnapshot {
  const TodayAttendanceSnapshot({
    required this.records,
    required this.history,
    required this.loadedAt,
  });

  final List<TodayAttendanceRecord> records;
  final List<TodayAttendanceHistoryDay> history;
  final DateTime loadedAt;

  List<TodayAttendanceRecord> get ownCompany =>
      records.where((record) => !record.isPartner).toList(growable: false);

  List<TodayAttendanceRecord> get subcontractors =>
      records.where((record) => record.isPartner).toList(growable: false);
}

class TodayAttendanceRepository {
  TodayAttendanceRepository._(this._client);

  final SupabaseClient _client;

  static TodayAttendanceRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return TodayAttendanceRepository._(client);
  }

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return rows.first['company_id'] as String;
  }

  Future<TodayAttendanceSnapshot> loadToday() async {
    final companyId = await _companyId();
    final now = DateTime.now();
    final localStart = DateTime(now.year, now.month, now.day);
    final localEnd = localStart.add(const Duration(days: 1));

    final rows = await _client
        .from('attendance_verifications')
        .select(
          'id, worker_id, site_id, event_type, confirmed_at, '
          'workers!attendance_verifications_worker_id_fkey('
          'id, name, affiliation, partner_company_id, '
          'partner_companies!workers_partner_company_id_fkey(name)), '
          'sites!attendance_verifications_site_id_fkey(id, name)',
        )
        .eq('company_id', companyId)
        .gte('confirmed_at', localStart.toUtc().toIso8601String())
        .lt('confirmed_at', localEnd.toUtc().toIso8601String())
        .order('confirmed_at');

    final byWorker = <String, _TodayDraft>{};

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final worker = row['workers'];
      if (worker is! Map) continue;

      final workerId = row['worker_id']?.toString() ?? '';
      if (workerId.isEmpty) continue;

      final draft = byWorker.putIfAbsent(
        workerId,
        () => _TodayDraft(
          workerId: workerId,
          workerName: worker['name']?.toString().trim().isNotEmpty == true
              ? worker['name'].toString().trim()
              : '名前未登録',
          affiliation: worker['affiliation']?.toString() ?? 'employee',
          partnerCompanyName: _partnerName(worker['partner_companies']),
        ),
      );

      final site = row['sites'];
      if (site is Map && site['name']?.toString().trim().isNotEmpty == true) {
        draft.siteName = site['name'].toString().trim();
      }

      final confirmed =
          DateTime.tryParse(row['confirmed_at']?.toString() ?? '')?.toLocal();
      if (confirmed == null) continue;

      final eventType = row['event_type']?.toString();
      if (eventType == 'clock_in') {
        draft.clockInAt ??= confirmed;
      } else if (eventType == 'clock_out') {
        draft.clockOutAt = confirmed;
      }

      if (draft.lastConfirmedAt == null ||
          confirmed.isAfter(draft.lastConfirmedAt!)) {
        draft.lastConfirmedAt = confirmed;
        draft.lastEventType = eventType;
      }
    }

    final records = byWorker.values.map((draft) => draft.toRecord()).toList()
      ..sort((a, b) {
        final at = a.lastConfirmedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastConfirmedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });

    final history = await _loadHistory(companyId, localStart);
    return TodayAttendanceSnapshot(
      records: records,
      history: history,
      loadedAt: DateTime.now(),
    );
  }

  Future<List<TodayAttendanceHistoryDay>> _loadHistory(
    String companyId,
    DateTime todayStart,
  ) async {
    final historyStart = todayStart.subtract(const Duration(days: 30));
    final rows = await _client
        .from('attendance_verifications')
        .select(
          'id, worker_id, site_id, event_type, confirmed_at, '
          'workers!attendance_verifications_worker_id_fkey('
          'id, name, affiliation, partner_company_id, '
          'partner_companies!workers_partner_company_id_fkey(name)), '
          'sites!attendance_verifications_site_id_fkey(id, name)',
        )
        .eq('company_id', companyId)
        .gte('confirmed_at', historyStart.toUtc().toIso8601String())
        .lt('confirmed_at', todayStart.toUtc().toIso8601String())
        .order('confirmed_at');

    final draftsByDay = <DateTime, Map<String, _TodayDraft>>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final worker = row['workers'];
      if (worker is! Map) continue;

      final workerId = row['worker_id']?.toString() ?? '';
      if (workerId.isEmpty) continue;

      final confirmed =
          DateTime.tryParse(row['confirmed_at']?.toString() ?? '')?.toLocal();
      if (confirmed == null) continue;

      final day = DateTime(confirmed.year, confirmed.month, confirmed.day);
      final byWorker = draftsByDay.putIfAbsent(day, () => <String, _TodayDraft>{});
      final draft = byWorker.putIfAbsent(
        workerId,
        () => _TodayDraft(
          workerId: workerId,
          workerName: worker['name']?.toString().trim().isNotEmpty == true
              ? worker['name'].toString().trim()
              : '名前未登録',
          affiliation: worker['affiliation']?.toString() ?? 'employee',
          partnerCompanyName: _partnerName(worker['partner_companies']),
        ),
      );

      final site = row['sites'];
      if (site is Map && site['name']?.toString().trim().isNotEmpty == true) {
        draft.siteName = site['name'].toString().trim();
      }

      final eventType = row['event_type']?.toString();
      if (eventType == 'clock_in') {
        if (draft.clockInAt == null || confirmed.isBefore(draft.clockInAt!)) {
          draft.clockInAt = confirmed;
        }
      } else if (eventType == 'clock_out') {
        if (draft.clockOutAt == null || confirmed.isAfter(draft.clockOutAt!)) {
          draft.clockOutAt = confirmed;
        }
      }

      if (draft.lastConfirmedAt == null ||
          confirmed.isAfter(draft.lastConfirmedAt!)) {
        draft.lastConfirmedAt = confirmed;
        draft.lastEventType = eventType;
      }
    }

    return [
      for (var offset = 1; offset <= 30; offset++)
        () {
          final date = todayStart.subtract(Duration(days: offset));
          final key = DateTime(date.year, date.month, date.day);
          final records = (draftsByDay[key]?.values
                      .map((draft) => draft.toRecord())
                      .toList(growable: false) ??
                  const <TodayAttendanceRecord>[])
              .toList()
            ..sort((a, b) {
              final at =
                  a.lastConfirmedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bt =
                  b.lastConfirmedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bt.compareTo(at);
            });
          return TodayAttendanceHistoryDay(date: key, records: records);
        }(),
    ];
  }

  String? _partnerName(Object? value) {
    if (value is Map) {
      final text = value['name']?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }
    return null;
  }
}

class _TodayDraft {
  _TodayDraft({
    required this.workerId,
    required this.workerName,
    required this.affiliation,
    required this.partnerCompanyName,
  });

  final String workerId;
  final String workerName;
  final String affiliation;
  final String? partnerCompanyName;
  String? siteName;
  String? lastEventType;
  DateTime? lastConfirmedAt;
  DateTime? clockInAt;
  DateTime? clockOutAt;

  TodayAttendanceRecord toRecord() => TodayAttendanceRecord(
        workerId: workerId,
        workerName: workerName,
        affiliation: affiliation,
        partnerCompanyName: partnerCompanyName,
        siteName: siteName,
        lastEventType: lastEventType,
        lastConfirmedAt: lastConfirmedAt,
        clockInAt: clockInAt,
        clockOutAt: clockOutAt,
      );
}
