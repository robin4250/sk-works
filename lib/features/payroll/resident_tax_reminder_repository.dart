import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';

bool _uuid(Object? value) => value is String && RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(value);

class ResidentTaxReminderSettings {
  const ResidentTaxReminderSettings({required this.companyId, required this.enabled,
    required this.canEdit, required this.updatedAt});
  final String companyId;
  final bool enabled, canEdit;
  // Preserve the server timestamp string for an exact optimistic-lock token.
  final String? updatedAt;
  static ResidentTaxReminderSettings parse(Object? raw, String companyId) {
    if (!_uuid(companyId) || raw is! Map || raw['version'] != 1 || raw['company_id'] != companyId ||
        raw['enabled'] is! bool || raw['can_edit'] is! bool ||
        raw['updated_at'] != null && (raw['updated_at'] is! String || DateTime.tryParse(raw['updated_at'] as String) == null) ||
        raw['timezone'] != 'Asia/Tokyo' || raw['dates'] is! List || (raw['dates'] as List).length != 2 || (raw['dates'] as List)[0] != '05-01' || (raw['dates'] as List)[1] != '05-25') {
      throw const FormatException('住民税の通知設定を確認できません');
    }
    return ResidentTaxReminderSettings(companyId: companyId, enabled: raw['enabled'] as bool,
      canEdit: raw['can_edit'] as bool, updatedAt: raw['updated_at'] as String?);
  }
}

class ResidentTaxReminderTarget {
  const ResidentTaxReminderTarget({required this.companyId, required this.fiscalYear, required this.complete});
  final String companyId;
  final int fiscalYear;
  final bool complete;
  static ResidentTaxReminderTarget parse(Object? raw, String expectedCompanyId) {
    if (!_uuid(expectedCompanyId) || raw is! Map || raw['version'] != 1 || raw['company_id'] != expectedCompanyId ||
        raw['tax_year'] is! int || (raw['tax_year'] as int) < 2000 || (raw['tax_year'] as int) > 9999 ||
        !const ['month_before','week_before'].contains(raw['phase']) || raw['complete'] is! bool) {
      throw const FormatException('通知の会社・年度を確認できません');
    }
    return ResidentTaxReminderTarget(companyId: expectedCompanyId,
      fiscalYear: raw['tax_year'] as int, complete: raw['complete'] as bool);
  }
}

abstract interface class ResidentTaxReminderRepository {
  String? get actorId;
  Stream<String?> get actorChanges;
  Future<ResidentTaxReminderSettings> read(String companyId);
  Future<ResidentTaxReminderSettings> save(ResidentTaxReminderSettings expected, bool enabled);
  Future<ResidentTaxReminderTarget> target(String notificationId, String companyId, {bool requireWorkspace = true});
}

class SupabaseResidentTaxReminderRepository implements ResidentTaxReminderRepository {
  SupabaseResidentTaxReminderRepository(this.client);
  final SupabaseClient client;
  static SupabaseResidentTaxReminderRepository? maybeCreate() =>
      !SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null
          ? null : SupabaseResidentTaxReminderRepository(SupabaseBackend.client);
  @override String? get actorId => client.auth.currentUser?.id;
  @override Stream<String?> get actorChanges => client.auth.onAuthStateChange.map((event) => event.session?.user.id);

  Future<T> _request<T>(Future<T> Function(Future<dynamic> Function(String, Map<String,dynamic>)) operation) async {
    final actor = actorId, token = client.auth.currentSession?.accessToken;
    if (actor == null || token == null) throw StateError('ログイン状態を確認してください');
    var invalid = false;
    final subscription = actorChanges.listen((next) {if (next != actor) invalid = true;}, onError: (Object _) {invalid = true;});
    void check() {if (invalid || actorId != actor) throw StateError('ログイン状態が変わりました。画面を開き直してください');}
    Future<dynamic> call(String name, Map<String,dynamic> params) async {
      check();
      final raw = await client.rpc(name, params: params).setHeader('Authorization', 'Bearer $token');
      check();
      return raw;
    }
    try {check();final result = await operation(call);check();return result;}
    finally {await subscription.cancel();}
  }
  @override Future<ResidentTaxReminderSettings> read(String companyId) => _request((call) async =>
    ResidentTaxReminderSettings.parse(await call('read_resident_tax_reminder_settings', {'p_company_id': companyId}), companyId));
  @override Future<ResidentTaxReminderSettings> save(ResidentTaxReminderSettings expected, bool enabled) {
    if (!expected.canEdit) throw StateError('会社管理者のみ変更できます');
    return _request((call) async {
      final result = ResidentTaxReminderSettings.parse(await call('save_resident_tax_reminder_settings', {
        'p_company_id': expected.companyId, 'p_enabled': enabled, 'p_expected_updated_at': expected.updatedAt,
      }), expected.companyId);
      if (result.enabled != enabled || result.updatedAt == null) throw const FormatException('通知設定の保存を確認できません');
      return result;
    });
  }
  @override Future<ResidentTaxReminderTarget> target(String notificationId, String companyId, {bool requireWorkspace = true}) => _request((call) async {
    if (!_uuid(notificationId) || !_uuid(companyId)) throw const FormatException('通知の対象を確認できません');
    final result = ResidentTaxReminderTarget.parse(await call('resident_tax_reminder_target', {'p_notification_id': notificationId}), companyId);
    if (requireWorkspace) {
      final workspace = await call('payroll_workspace', {});
      if (workspace is! Map || workspace['company_id'] != result.companyId ||
          workspace['permissions'] is! Map || (workspace['permissions'] as Map)['view'] != true) {
        throw StateError('通知と現在の会社が異なります。対象会社に切り替えてから開いてください');
      }
    }
    return result;
  });
}
