import 'dart:convert';
import 'dart:math';

/// Client command for the versioned canonical publisher. Merely constructing or
/// retaining this object never calls an RPC, activates payroll, or resends it.
class CommonPayrollCanonicalPublicationCommand {
  CommonPayrollCanonicalPublicationCommand._(this.params);

  static const reconciliation =
      'inherit_absent_or_same_rate_otherwise_unresolved';
  static const quantityBasis = 'attendance_selected_distinct_dates';
  static const _keys = {
    'p_company_id', 'p_payroll_type', 'p_starts_on', 'p_common_version',
    'p_common_source', 'p_timeline_version', 'p_legacy_quantities',
    'p_individual_reconciliation', 'p_request_id', 'p_preview_token',
    'p_approve_activation',
  };
  final Map<String, dynamic> params;
  String get companyId => params['p_company_id'] as String;
  String get requestId => params['p_request_id'] as String;
  String get payrollType => params['p_payroll_type'] as String;
  String get startsOn => params['p_starts_on'] as String;
  String get previewToken => params['p_preview_token'] as String;
  bool get approvesActivation => params['p_approve_activation'] as bool;

  factory CommonPayrollCanonicalPublicationCommand.fromParams(Object? raw) {
    if (raw is! Map || raw.length != _keys.length ||
        !_keys.every(raw.containsKey)) {
      throw const FormatException('給与適用の確認内容を読み取れません');
    }
    final value = canonicalPublicationJsonCopy(raw);
    final map = value as Map<String, dynamic>;
    bool version(Object? v) => v is int && v >= 0 && v <= 9007199254740991;
    final start = map['p_starts_on'];
    if (!canonicalPublicationUuid(map['p_company_id']) ||
        !canonicalPublicationUuid(map['p_request_id']) ||
        !const ['daily', 'hourly', 'monthly'].contains(map['p_payroll_type']) ||
        start is! String ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(start) ||
        !version(map['p_common_version']) || !version(map['p_timeline_version']) ||
        map['p_common_source'] is! Map ||
        map['p_individual_reconciliation'] != reconciliation ||
        map['p_preview_token'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(map['p_preview_token'] as String) ||
        map['p_approve_activation'] is! bool ||
        map['p_legacy_quantities'] is! List) {
      throw const FormatException('給与適用の確認内容が一致しません');
    }
    final identities = <String>{};
    for (final item in map['p_legacy_quantities'] as List) {
      const keys = {'id', 'generation', 'source_unit', 'basis', 'aliases'};
      if (item is! Map || item.length != keys.length ||
          !keys.every(item.containsKey) || !canonicalPublicationUuid(item['id']) ||
          !version(item['generation']) || item['generation'] == 0 ||
          !identities.add(item['id'] as String) ||
          item['basis'] != quantityBasis ||
          item['source_unit'] is! String ||
          (item['source_unit'] as String).trim().isEmpty ||
          (item['source_unit'] as String).length > 80 ||
          item['aliases'] is! List || (item['aliases'] as List).length != 1 ||
          (item['aliases'] as List).single is! String ||
          ((item['aliases'] as List).single as String).trim().isEmpty ||
          ((item['aliases'] as List).single as String).length > 160) {
        throw const FormatException('共通手当の数量条件を確認してください');
      }
    }
    return CommonPayrollCanonicalPublicationCommand._(map);
  }

  static String newRequestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Read-only receipt lookup must use this exact approved command. A missing
  /// receipt is not permission to issue another publish command automatically.
  Map<String, dynamic> get receiptParams => Map.unmodifiable({
    'p_company_id': companyId,
    'p_request_id': requestId,
    'p_expected_command': params,
  });
}

bool canonicalPublicationUuid(Object? value) => value is String &&
    RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(value);

/// JSON values only; retain no session, token, or mutable caller-owned object.
/// The size limit also bounds damaged or unsupported pending records on disk.
Object? canonicalPublicationJsonCopy(Object? value) {
  final encoded = jsonEncode(value);
  if (utf8.encode(encoded).length > 262144) {
    throw const FormatException('給与適用の確認内容が大きすぎます');
  }
  Object? freeze(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      if (keys.any((key) => const {
        'access_token', 'refresh_token', 'authorization', 'service_role',
        'service_role_key', 'apikey', 'anon_key', 'jwt',
      }.contains(key.toLowerCase()))) {
        throw const FormatException('認証情報を給与適用記録へ保存できません');
      }
      return Map<String, dynamic>.unmodifiable({
        for (final key in keys) key: freeze(item[key]),
      });
    }
    if (item is List) return List<Object?>.unmodifiable(item.map(freeze));
    return item;
  }
  return freeze(jsonDecode(encoded));
}

String canonicalPublicationJson(Object? value) =>
    jsonEncode(canonicalPublicationJsonCopy(value));
