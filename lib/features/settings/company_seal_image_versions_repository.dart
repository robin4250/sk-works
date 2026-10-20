import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/company_uploaded_seal_png.dart';
import '../shared/trade_document_actor_boundary.dart';
import 'company_seal_png_repository.dart';
import 'master_feature_controls_repository.dart';

class CompanySealImageVersion {
  const CompanySealImageVersion({required this.id, required this.company,
    required this.sha256, required this.createdAt, required this.width, required this.height});
  final String id, sha256;
  final UploadedSealCompany company;
  final DateTime createdAt;
  final int width, height;
  static CompanySealImageVersion parse(Object? raw, UploadedSealCompany company) {
    if (raw is! Map || raw['company_id'] != company.companyId || raw['company_name'] != company.name ||
        raw['version_id'] is! String || raw['sha256'] is! String || raw['created_at'] is! String ||
        raw['width'] is! int || raw['height'] is! int) { throw StateError('角印の保存履歴を確認できません。'); }
    final id = raw['version_id'] as String;
    final hash = raw['sha256'] as String;
    final width = raw['width'] as int, height = raw['height'] as int;
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        width < 32 || width > 2048 || height < 32 || height > 2048) { throw StateError('角印の履歴が一致しません。'); }
    return CompanySealImageVersion(id: id, company: company, sha256: hash,
      createdAt: DateTime.parse(raw['created_at'] as String), width: width, height: height);
  }
}

/// Uses the immutable PNG versions installed by the original PNG candidate.
/// Register never changes the active selection; use remains an explicit CAS save.
class CompanySealImageVersionsRepository {
  CompanySealImageVersionsRepository(this.client);
  final SupabaseClient client;
  Future<bool> allowed() async => (await MasterFeatureControlsRepository.loadForClient(client)).companySealImageTools;
  Future<T> _guard<T>(Future<T> Function(String accessToken) action) async {
    final session = client.auth.currentSession;
    if (session == null) { throw StateError('ログイン情報を確認してください。'); }
    final lease = TradeDocumentActorLease.forClient(client);
    try {
      if (!await allowed()) { throw StateError('角印の画像編集は現在利用できません。'); }
      lease.verify();
      final result = await action(session.accessToken);
      lease.verify();
      if (!await allowed()) { throw StateError('角印の画像編集は現在利用できません。'); }
      lease.verify();
      return result;
    } finally { lease.dispose(); }
  }
  Future<CompanySealImageVersion> register(UploadedSealCompany company, CompanyUploadedSealPng png) => _guard((accessToken) async {
    final result = CompanySealImageVersion.parse(await client.rpc('register_company_seal_png_version', params: {
      'p_company_id': company.companyId, 'p_expected_name': company.name,
      'p_png_base64': png.base64, 'p_png_sha256': png.sha256,
    }).setHeader('Authorization', 'Bearer $accessToken'), company);
    if (result.sha256 != png.sha256 || result.width != png.width || result.height != png.height) {
      throw StateError('角印の追加保存結果が一致しません。');
    }
    return result;
  });
  Future<List<CompanySealImageVersion>> list(UploadedSealCompany company, {CompanySealImageVersion? before}) => _guard((accessToken) async {
    final raw = await client.rpc('company_seal_png_versions', params: {
      'p_company_id': company.companyId, 'p_expected_name': company.name,
      'p_before_created_at': before?.createdAt.toUtc().toIso8601String(), 'p_before_id': before?.id,
    }).setHeader('Authorization', 'Bearer $accessToken');
    if (raw is! List || raw.length > 20) { throw StateError('角印の保存履歴を確認できません。'); }
    return raw.map((row) => CompanySealImageVersion.parse(row, company)).toList(growable: false);
  });
  Future<CompanyUploadedSealPng> read(CompanySealImageVersion version) => _guard((accessToken) async {
    final raw = await client.rpc('company_seal_png_version', params: {
      'p_company_id': version.company.companyId, 'p_expected_name': version.company.name, 'p_version_id': version.id,
    }).setHeader('Authorization', 'Bearer $accessToken');
    final confirmed = CompanySealImageVersion.parse(raw, version.company);
    if (confirmed.id != version.id || confirmed.sha256 != version.sha256 || raw is! Map || raw['png_base64'] is! String) {
      throw StateError('選択した角印を確認できません。');
    }
    final png = CompanyUploadedSealPng.fromBase64(raw['png_base64'] as String, expectedSha256: version.sha256);
    if (png.width != version.width || png.height != version.height) { throw StateError('角印の大きさが一致しません。'); }
    return png;
  });
}
