import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AdminSiteFinancialRecord {
  const AdminSiteFinancialRecord({
    required this.siteId,
    required this.siteName,
    required this.status,
    required this.workerDailyRateYen,
    required this.overtimeHourRateYen,
    required this.earlyHourRateYen,
    required this.nightHourRateYen,
    required this.billingUnitPriceYen,
    required this.welfareRate,
  });

  final String siteId;
  final String siteName;
  final String status;
  final int workerDailyRateYen;
  final int overtimeHourRateYen;
  final int earlyHourRateYen;
  final int nightHourRateYen;
  final int billingUnitPriceYen;
  final double welfareRate;
}

class AdminSiteFinancialRepository {
  AdminSiteFinancialRepository._(this._client);

  final SupabaseClient _client;

  static AdminSiteFinancialRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AdminSiteFinancialRepository._(client);
  }

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');

    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');

    final role = rows.first['role']?.toString() ?? 'viewer';
    if (role != 'owner' && role != 'admin') {
      throw StateError('管理者権限が必要です。');
    }

    return rows.first['company_id'] as String;
  }

  Future<List<AdminSiteFinancialRecord>> loadAll() async {
    final companyId = await _companyId();

    final sites = await _client
        .from('sites')
        .select('id, name, status')
        .eq('company_id', companyId)
        .order('created_at', ascending: false);

    final settings = await _client
        .from('site_financial_settings')
        .select(
          'site_id, worker_daily_rate_yen, overtime_hour_rate_yen, early_hour_rate_yen, night_hour_rate_yen, billing_unit_price_yen, welfare_rate',
        )
        .eq('company_id', companyId);

    final bySite = <String, Map<String, dynamic>>{
      for (final raw in settings)
        raw['site_id'].toString(): Map<String, dynamic>.from(raw),
    };

    return sites.map<AdminSiteFinancialRecord>((raw) {
      final row = Map<String, dynamic>.from(raw);
      final siteId = row['id'].toString();
      final s = bySite[siteId] ?? const <String, dynamic>{};

      return AdminSiteFinancialRecord(
        siteId: siteId,
        siteName: row['name']?.toString() ?? '',
        status: row['status']?.toString() ?? 'preparation',
        workerDailyRateYen:
            (s['worker_daily_rate_yen'] as num?)?.toInt() ?? 0,
        overtimeHourRateYen:
            (s['overtime_hour_rate_yen'] as num?)?.toInt() ?? 0,
        earlyHourRateYen:
            (s['early_hour_rate_yen'] as num?)?.toInt() ?? 0,
        nightHourRateYen:
            (s['night_hour_rate_yen'] as num?)?.toInt() ?? 0,
        billingUnitPriceYen:
            (s['billing_unit_price_yen'] as num?)?.toInt() ?? 0,
        welfareRate: (s['welfare_rate'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  Future<void> save(AdminSiteFinancialRecord record) async {
    final companyId = await _companyId();

    await _client.from('site_financial_settings').upsert({
      'site_id': record.siteId,
      'company_id': companyId,
      'worker_daily_rate_yen': record.workerDailyRateYen,
      'overtime_hour_rate_yen': record.overtimeHourRateYen,
      'early_hour_rate_yen': record.earlyHourRateYen,
      'night_hour_rate_yen': record.nightHourRateYen,
      'billing_unit_price_yen': record.billingUnitPriceYen,
      'welfare_rate': record.welfareRate,
      'updated_by': _client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
