import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import '../../domain/company_uploaded_seal_png.dart';
import '../shared/trade_document_actor_boundary.dart';

typedef UploadedSealCompany = ({String companyId, String name});
class CompanySealPngSettings {
  const CompanySealPngSettings({required this.company, required this.available,
    this.enabled = false, this.revision = 0, this.png, this.versionId});
  final UploadedSealCompany company;
  final bool available, enabled;
  final int revision;
  final CompanyUploadedSealPng? png;
  final String? versionId;
}
abstract class CompanySealPngSource {
  Future<CompanySealPngSettings> load(UploadedSealCompany company);
  Future<CompanySealPngSettings> save(CompanySealPngSettings settings,
      {CompanyUploadedSealPng? png, required bool enabled});
}
class CompanySealPngRepository implements CompanySealPngSource {
  CompanySealPngRepository._(this._client);
  @visibleForTesting
  CompanySealPngRepository.forTesting(this._client);
  final SupabaseClient _client;
  static CompanySealPngRepository? maybeCreate() => SupabaseBackend.isInitialized &&
      SupabaseBackend.client.auth.currentUser != null
      ? CompanySealPngRepository._(SupabaseBackend.client) : null;

  CompanySealPngSettings _parse(Object? raw, UploadedSealCompany company) {
    if (raw is! Map || raw['company_id'] != company.companyId || raw['company_name'] != company.name ||
        raw['available'] != true || raw['enabled'] is! bool || raw['revision'] is! int ||
        (raw['revision'] as int) < 0) {
      throw StateError('会社角印の設定が一致しません。');
    }
    final encoded = raw['png_base64'];
    final hash = raw['png_sha256'];
    final id = raw['version_id'];
    CompanyUploadedSealPng? png;
    if (encoded != null || hash != null || id != null) {
      if (encoded is! String || hash is! String || id is! String ||
          !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
        throw StateError('保存したPNGを確認できません。');
      }
      png = CompanyUploadedSealPng.fromBase64(encoded, expectedSha256: hash);
      if (raw['width'] != png.width || raw['height'] != png.height) throw StateError('保存したPNGの大きさが一致しません。');
    }
    if (raw['enabled'] == true && png == null) throw StateError('会社角印のPNGがありません。');
    return CompanySealPngSettings(company: company, available: true,
      enabled: raw['enabled'] as bool, revision: raw['revision'] as int,
      png: png, versionId: id as String?);
  }
  TradeDocumentActorLease _lease() => TradeDocumentActorLease.forClient(_client);
  @override
  Future<CompanySealPngSettings> load(UploadedSealCompany company) async {
    if (_client.auth.currentUser == null) throw StateError('ログインが必要です。');
    final lease = _lease();
    try {
      final raw = await _client.rpc('company_uploaded_seal_settings',
          params: {'p_company_id': company.companyId});
      lease.verify();
      return _parse(raw, company);
    } on PostgrestException catch (e) {
      lease.verify();
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      return CompanySealPngSettings(company: company, available: false);
    } finally { lease.dispose(); }
  }
  @override
  Future<CompanySealPngSettings> save(CompanySealPngSettings settings,
      {CompanyUploadedSealPng? png, required bool enabled}) async {
    if (!settings.available || _client.auth.currentUser == null) throw StateError('PNGの保存はまだ利用できません。');
    final lease = _lease();
    try {
      final raw = await _client.rpc('save_company_uploaded_seal', params: {
        'p_company_id': settings.company.companyId, 'p_expected_name': settings.company.name,
        'p_expected_revision': settings.revision, 'p_png_base64': png?.base64,
        'p_png_sha256': png?.sha256, 'p_enabled': enabled,
      });
      lease.verify();
      final result = _parse(raw, settings.company);
      if (result.revision != settings.revision + 1 || result.enabled != enabled ||
          (png != null && result.png?.sha256 != png.sha256)) {
        throw StateError('PNGの保存結果を確認できません。');
      }
      return result;
    } finally { lease.dispose(); }
  }
}
