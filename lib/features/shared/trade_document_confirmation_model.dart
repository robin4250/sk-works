import 'dart:convert';
import 'dart:math';

bool tradeConfirmationUuid(Object? value) => value is String && RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value);
bool _positive(Object? value) => value is int && value > 0 && value <= 2147483647;
bool _hash(Object? value) => value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
const _kinds = {'invoice', 'payment_certificate'};
bool _sameSourceRevision(String kind, Object? actual, String expected) {
  if (actual is! String) return false;
  if (actual == expected) return true;
  if (kind != 'invoice') return false;
  final a = DateTime.tryParse(actual), b = DateTime.tryParse(expected);
  return a != null && b != null && a.toUtc().isAtSameMomentAs(b.toUtc());
}

/// Stable JSON only. The approval journal never stores image bytes or sessions.
Object? tradeConfirmationCopy(Object? value, {bool journal = false}) {
  final encoded = jsonEncode(value);
  if (utf8.encode(encoded).length > (journal ? 65536 : 4194304)) {
    throw const FormatException('書類の確認内容が大きすぎます');
  }
  Object? freeze(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      if (keys.any((key) => const {'access_token', 'refresh_token', 'authorization',
          'service_role', 'service_role_key', 'apikey', 'anon_key', 'jwt'}.contains(key.toLowerCase()) ||
          journal && const {'png_base64', 'snapshot', 'own_seal', 'display_preview'}.contains(key))) {
        throw const FormatException('認証情報や印影画像を確認記録へ保存できません');
      }
      return Map<String, dynamic>.unmodifiable({for (final key in keys) key: freeze(item[key])});
    }
    if (item is List) return List<Object?>.unmodifiable(item.map(freeze));
    return item;
  }
  return freeze(jsonDecode(encoded));
}
String tradeConfirmationJson(Object? value) => jsonEncode(tradeConfirmationCopy(value, journal: true));

/// Keep the evidence ID as local response expectation. It is not an extra RPC
/// parameter and must never be derived from the render response itself.
Map<String, dynamic> tradeConfirmationRenderScope(Map source) {
  if (!tradeConfirmationUuid(source['company_id']) || !tradeConfirmationUuid(source['local_document_id']) ||
      !tradeConfirmationUuid(source['document_id']) || source['local_document_id'] == source['document_id'] ||
      !_positive(source['document_revision']) || !_kinds.contains(source['kind'])) {
    throw const FormatException('承認済み書類の保存先が一致しません');
  }
  return Map<String, dynamic>.unmodifiable({'p_company_id': source['company_id'],
    'p_local_document_id': source['local_document_id'], 'p_document_revision': source['document_revision'],
    'p_kind': source['kind'], 'expected_document_id': source['document_id']});
}

class TradeConfirmationWorkspace {
  TradeConfirmationWorkspace._(this.value);
  final Map<String, dynamic> value;
  String get kind => value['kind'] as String;
  String get companyId => value['company_id'] as String;
  String get actorId => value['actor_id'] as String;
  String get parentId => value['parent_id'] as String;
  String get sourceRevision => value['source_revision'] as String;
  bool get integrationRequired => value['integration_required'] == true;
  bool get canConfirm => value['can_integrated_confirm'] == true;
  String? get unavailableReason => value['unavailable_reason'] as String?;
  Map<String, dynamic> get scope => {
    'p_company_id': companyId, 'p_local_document_id': value['local_document_id'],
    'p_document_revision': value['document_revision'], 'p_kind': kind};
  factory TradeConfirmationWorkspace.parse(Object? raw, {required String kind,
      required String parentId, required String sourceRevision, required String actorId}) {
    if (raw is! Map || raw['contract_version'] is! int || raw['contract_version'] != 1 || raw['kind'] != kind || !_kinds.contains(kind) ||
        raw['parent_id'] != parentId || !_sameSourceRevision(kind, raw['source_revision'], sourceRevision) ||
        raw['actor_id'] != actorId || !tradeConfirmationUuid(raw['company_id']) ||
        raw['side'] != 'issued' || raw['integration_required'] is! bool ||
        raw['can_integrated_confirm'] is! bool || raw['can_render'] is! bool ||
        raw['unavailable_reason'] != null && raw['unavailable_reason'] is! String) {
      throw const FormatException('書類の対象を確認できません');
    }
    if (raw['can_integrated_confirm'] == true && (raw['integration_required'] != true ||
        !tradeConfirmationUuid(raw['local_document_id']) || !tradeConfirmationUuid(raw['document_id']) ||
        raw['local_document_id'] == raw['document_id'] || !_positive(raw['document_revision']) ||
        !_positive(raw['attachment_version']))) {
      throw const FormatException('書類の保存状態を確認できません');
    }
    return TradeConfirmationWorkspace._(tradeConfirmationCopy(raw) as Map<String, dynamic>);
  }
}

class TradeConfirmationDescriptor {
  TradeConfirmationDescriptor._(this.value);
  static const keys = {'contract_version', 'kind', 'company_id', 'actor_id', 'parent_id',
    'source_revision', 'attachment_version', 'local_document_id', 'document_id',
    'document_revision', 'body_hash', 'preview_hash'};
  final Map<String, dynamic> value;
  String get companyId => value['company_id'] as String;
  String get actorId => value['actor_id'] as String;
  String get parentId => value['parent_id'] as String;
  String get kind => value['kind'] as String;
  String get localId => value['local_document_id'] as String;
  String get documentId => value['document_id'] as String;
  int get revision => value['document_revision'] as int;
  Map<String, dynamic> get scope => {'p_company_id': companyId, 'p_local_document_id': localId,
    'p_document_revision': revision, 'p_kind': kind};
  factory TradeConfirmationDescriptor.parse(Object? raw) {
    if (raw is! Map || raw.length != keys.length || !keys.every(raw.containsKey) ||
        raw['contract_version'] is! int || raw['contract_version'] != 1 || !_kinds.contains(raw['kind']) ||
        const ['company_id', 'actor_id', 'parent_id', 'local_document_id', 'document_id']
          .any((key) => !tradeConfirmationUuid(raw[key])) ||
        raw['local_document_id'] == raw['document_id'] ||
        raw['source_revision'] is! String || (raw['source_revision'] as String).isEmpty ||
        (raw['source_revision'] as String).length > 160 || !_positive(raw['attachment_version']) ||
        !_positive(raw['document_revision']) || !_hash(raw['body_hash']) || !_hash(raw['preview_hash'])) {
      throw const FormatException('書類の確認内容が一致しません');
    }
    return TradeConfirmationDescriptor._(tradeConfirmationCopy(raw, journal: true) as Map<String, dynamic>);
  }
}

class TradeConfirmationCommand {
  TradeConfirmationCommand({required this.expected, required this.requestId}) {
    if (!tradeConfirmationUuid(requestId)) throw const FormatException('確認申請を識別できません');
  }
  final TradeConfirmationDescriptor expected;
  final String requestId;
  Map<String, dynamic> get params => {'p_expected_command': expected.value, 'p_request_id': requestId,
    'p_document_confirmed': true, 'p_seal_confirmed': true};
  Map<String, dynamic> get receiptParams => {'p_company_id': expected.companyId,
    'p_request_id': requestId, 'p_expected_command': expected.value};
  static String newRequestId() {
    final r = Random.secure(); final bytes = List.generate(16, (_) => r.nextInt(256));
    bytes[6] = bytes[6] & 15 | 64; bytes[8] = bytes[8] & 63 | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

class TradeConfirmationPreview {
  TradeConfirmationPreview._(this.expected, this.display);
  final TradeConfirmationDescriptor expected;
  final Map<String, dynamic> display;
  factory TradeConfirmationPreview.parse(Object? raw, TradeConfirmationWorkspace workspace) {
    if (!workspace.canConfirm || raw is! Map || raw['contract_version'] is! int || raw['contract_version'] != 1 ||
        raw['expected_command'] is! Map || raw['display_preview'] is! Map) {
      throw const FormatException('確認用の書類を取得できません');
    }
    final expected = TradeConfirmationDescriptor.parse(raw['expected_command']);
    final w = workspace.value;
    if (expected.value.entries.any((entry) => const {'kind', 'company_id', 'actor_id',
        'parent_id', 'source_revision', 'attachment_version', 'local_document_id',
        'document_id', 'document_revision'}.contains(entry.key) && w[entry.key] != entry.value) ||
        raw['preview_hash'] != expected.value['preview_hash']) {
      throw const FormatException('確認用の書類が更新されています');
    }
    final display = raw['display_preview'] as Map;
    if (display['body_hash'] != expected.value['body_hash'] || display['body'] is! Map ||
        display['own_seal'] is! Map) {
      throw const FormatException('書類の本文と印影を確認できません');
    }
    return TradeConfirmationPreview._(expected, tradeConfirmationCopy(display) as Map<String, dynamic>);
  }
}

class TradeConfirmationResult {
  TradeConfirmationResult._(this.value);
  final Map<String, dynamic> value;
  factory TradeConfirmationResult.parse(Object? raw, TradeConfirmationCommand command) {
    final e = command.expected;
    if (raw is! Map || raw['contract_version'] is! int || raw['contract_version'] != 1 || raw['request_id'] != command.requestId ||
        raw['kind'] != e.kind || raw['company_id'] != e.companyId || raw['actor_id'] != e.actorId ||
        raw['local_document_id'] != e.localId || raw['document_id'] != e.documentId ||
        raw['document_revision'] != e.revision || raw['seal_consent_recorded'] != true ||
        raw['operation'] != (e.kind == 'invoice' ? 'invoice_final_approval_with_seal' : 'monthly_content_review_with_seal') ||
        raw['result'] is! Map) {
      throw const FormatException('書類の確認結果が一致しません');
    }
    final result = raw['result'] as Map;
    if (result['document_id'] != e.documentId || result['revision'] != e.revision ||
        result['request_id'] != command.requestId || result['seal_consent_recorded'] != true ||
        (e.kind == 'invoice' ? result['financial_approved'] != true
          : result['monthly_review_recorded'] != true || result['financial_finalized'] != false ||
            result['financial_parent_unchanged'] != true)) {
      throw const FormatException('書類と承認の保存結果が一致しません');
    }
    return TradeConfirmationResult._(tradeConfirmationCopy(raw) as Map<String, dynamic>);
  }
}
