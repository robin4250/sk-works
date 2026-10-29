import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import '../shared/trade_document_confirmation_model.dart';
import '../shared/trade_document_confirmation_approved_pdf.dart';
import 'invoice_notice_recovery_controller.dart';

/// Fixed build-time backend, fixed function path; never a route/body URL.
/// No production call occurs while the entry's release constant remains false.
InvoiceNoticeRecoveryController? createInvoiceNoticeCandidateController({
  required SupabaseClient client, required String invoiceId, required String sourceRevision,
  bool enabled = false, @visibleForTesting http.Client Function()? transportClientFactory,
}) {
  if (!enabled) { return null; }
  final origin = Uri.tryParse(SupabaseBackendConfig.url);
  if (origin == null || origin.scheme != 'https' || origin.host.isEmpty ||
      origin.userInfo.isNotEmpty || origin.query.isNotEmpty || origin.fragment.isNotEmpty ||
      origin.path != '' && origin.path != '/') { return null; }
  final connections = <http.Client>{};
  void release(http.Client value) { if (connections.remove(value)) { value.close(); } }
  final actor = client.auth.currentUser?.id;
  String? sid() {
    try {
      final session = client.auth.currentSession;
      if (session == null) { return null; }
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(session.accessToken.split('.')[1]))));
      final id = claims is Map ? claims['session_id'] : null;
      return claims is Map && claims['sub'] == session.user.id && tradeConfirmationUuid(id) ? id as String : null;
    } catch (_) { return null; }
  }
  final originalSid = sid();
  if (actor == null || originalSid == null) { return null; }
  InvoiceNoticeOperation? operation;
  TradeConfirmationPreview? preview;
  late InvoiceNoticeRecoveryController recovery;
  var generation = 0;
  bool current(int value) => generation == value && recovery.state != InvoiceNoticeRecoveryState.invalidated &&
      client.auth.currentUser?.id == actor && sid() == originalSid;
  Future<Object?> post(String action, Map<String, dynamic> body) async {
    final version = generation;
    if (!current(version)) { throw StateError('ログイン情報が変わりました'); }
    final bearer = client.auth.currentSession!.accessToken;
    final connection = transportClientFactory?.call() ?? http.Client();
    connections.add(connection);
    final watch = Stopwatch()..start();
    Future<Object?> read() async {
    final request = http.Request('POST', origin.replace(path: '/functions/v1/invoice-notice/$action'))
      ..followRedirects = false
      ..headers.addAll({'authorization': 'Bearer $bearer', 'content-type': 'application/json'})
      ..body = jsonEncode(body);
    final reply = await connection.send(request);
    if (!current(version) || reply.statusCode != 200 || reply.isRedirect ||
        reply.headers['content-type']?.split(';').first != 'application/json') {
      await reply.stream.listen((_) {}).cancel();
      throw StateError('承認状態を確認できません');
    }
    // Open includes two server preview copies; each existing model is bounded
    // at 4 MiB and may contain the registered 1 MiB PNG unchanged.
    final bytes = <int>[];
    await for (final chunk in reply.stream) {
      if (!current(version) || bytes.length + chunk.length > 9 * 1024 * 1024) { throw StateError('承認状態を確認できません'); }
      bytes.addAll(chunk);
    }
    if (!current(version)) { throw StateError('ログイン情報が変わりました'); }
    final result = jsonDecode(utf8.decode(bytes));
    if (watch.elapsed >= const Duration(seconds: 20)) { throw TimeoutException('承認状態の確認期限を超えました'); }
    return result;
    }
    try { return await read().timeout(const Duration(seconds: 20)); }
    finally { release(connection); }
  }
  recovery = InvoiceNoticeRecoveryController(actor: () => client.auth.currentUser?.id, session: sid,
    authClient: client, explicitConsentRequired: true,
    openTicket: (notice) async {
      final version = ++generation; operation = null; preview = null;
      final raw = await post('open', {'notification_id': notice, 'invoice_id': invoiceId, 'source_revision': sourceRevision});
      if (!current(version) || raw is! Map || raw['actor_id'] != actor || raw['session_id'] != originalSid ||
          raw['notification_id'] != notice || raw['invoice_id'] != invoiceId || raw['operation'] is! Map) {
        throw const FormatException('通知の対象を確認できません');
      }
      final workspace = TradeConfirmationWorkspace.parse(raw['workspace'], kind: 'invoice', parentId: invoiceId,
        sourceRevision: sourceRevision, actorId: actor);
      final shown = TradeConfirmationPreview.parse(raw['preview'], workspace);
      final value = raw['operation'] as Map;
      final expected = value['expected_preview'];
      final display = {...shown.display}..remove('body');
      if (value['ticket_id'] != raw['ticket_id'] || value['local_document_id'] != shown.expected.localId ||
          value['company_id'] != shown.expected.companyId || value['revision'] != shown.expected.revision ||
          value['expected_hash'] != shown.expected.value['preview_hash'] || expected is! Map ||
          !_sameJson(expected, display)) { throw const FormatException('確認する書類が一致しません'); }
      final saved = InvoiceNoticeOperation(ticketId: value['ticket_id'] as String,
        localDocumentId: value['local_document_id'] as String, companyId: value['company_id'] as String,
        revision: value['revision'] as int, requestId: value['request_id'] as String,
        expectedHash: value['expected_hash'] as String, expectedPreview: Map<String, dynamic>.from(expected));
      if (!current(version)) { throw StateError('ログイン情報が変わりました'); }
      operation = saved; preview = shown;
      return raw;
    },
    operationForTicket: (ticket) {
      final saved = operation;
      if (saved == null || saved.ticketId != ticket) { throw StateError('承認対象を確認できません'); }
      return saved;
    },
    // This fence remains even if a future caller bypasses the consent API.
    confirm: (_) async => throw StateError('明示確認が必要です'),
    confirmWithConsent: (value, {required financialConfirmed, required sealConfirmed}) => post('confirm', {
      ...value.parameters, 'financial_confirmed': financialConfirmed, 'seal_confirmed': sealConfirmed}),
    readResult: (value) => post('result', value.parameters),
    buildOwnPreview: () async {
      final version = generation, shown = preview;
      if (!current(version) || shown == null) { throw StateError('確認用の書類がありません'); }
      final bytes = await TradeConfirmationPdf.ownPreview(shown);
      if (!current(version) || bytes.isEmpty) { throw StateError('確認用の書類が変わりました'); }
      return bytes;
    },
    closeTransport: () { generation++; operation = null; preview = null; for (final connection in connections.toList()) { release(connection); } },
  );
  return recovery;
}

bool _sameJson(Object? a, Object? b) {
  Object? ordered(Object? value) {
    if (value is Map) { final keys = value.keys.map((key) => key.toString()).toList()..sort(); return {for (final key in keys) key: ordered(value[key])}; }
    if (value is List) { return value.map(ordered).toList(); }
    return value;
  }
  return jsonEncode(ordered(a)) == jsonEncode(ordered(b));
}
