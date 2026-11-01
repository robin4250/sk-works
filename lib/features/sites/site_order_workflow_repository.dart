import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../../domain/company_seal_snapshot.dart';
import '../shared/trade_document_form_renderer.dart';
import '../shared/trade_document_form_session.dart';
import 'site_order_approval_journal.dart';
import 'site_order_outgoing_journal.dart';
import 'site_order_outgoing_entries.dart';
import 'site_order_outgoing_consent.dart';
import 'site_order_outgoing_execution.dart';
import 'site_order_original_review.dart';
import 'site_order_delivery_journal.dart';
import 'site_order_outgoing_consent_preview.dart';

String siteOrderRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class SiteOrderResultUnknown implements Exception {
  const SiteOrderResultUnknown();
}

abstract class SiteOrderWorkflowApi extends ChangeNotifier {
  bool _uiRetired = false;
  bool get uiRetired => _uiRetired;
  /// Retires client access only; never cancels server work or clears journals.
  void retireUiScope() {
    if (_uiRetired) return;
    _uiRetired = true;
    notifyListeners();
  }
  /// Read-only context for an opt-in notification read receipt. Unknown until
  /// current membership verification succeeds; never exposes an access token.
  ({String actorId, String companyId, String sessionId})? get notificationReadBinding => null;
  bool isNotificationReadClient(Object client) => false;
  /// Opt-in parent notification lifetime; unsupported APIs fail closed.
  bool bindNotificationUiContext(bool Function() current) => false;
  bool get invalidated;
  void requireCurrent();
  Future<Map<String, dynamic>> detail(String packageId);
  Future<List<Map<String, dynamic>>> history({
    String? before,
    String? beforeId,
  });
  Future<List<Map<String, dynamic>>> historyForSite(
    String siteId, {
    String? before,
    String? beforeId,
  }) async => throw StateError('現場の注文履歴を確認できません。');
  Future<Map<String, dynamic>> outgoingContext(String siteId, String tradeId) async =>
      throw StateError('注文書の登録元を確認できません。');
  Future<Map<String, dynamic>> observePrepare(String siteId, String documentId, String localId, String tradeId) async =>
      throw StateError('注文書の準備結果を確認できません。');
  Future<List<Map<String, dynamic>>> targets(String packageId);
  Future<Map<String, dynamic>> preview(
    String packageId,
    Map<String, dynamic> target,
  );
  Future<Uint8List> renderReview(Map<String, dynamic> preview);
  Future<Map<String, dynamic>> approve(
    Map<String, dynamic> preview,
    String requestId,
  );
  Future<Map<String, dynamic>> resume(String packageId);
  Future<Uint8List> original(String packageId, String kind);
  Future<Map<String, dynamic>> originalPayload(String packageId, String kind);
  Future<void> verify();
  Future<bool> hasPendingReplyRecovery(String id) async => false;
  Future<String?> reconcileReplyRecovery(String id) async => null;
  Future<Map<String, dynamic>> previewReplyRecovery(String id) async =>
      throw StateError('請書の再確認を開始できません。');
  Future<Uint8List> renderReplyRecovery(Map<String, dynamic> preview) async =>
      throw StateError('請書の再確認を開始できません。');
  Future<Map<String, dynamic>> recoverReply(
    Map<String, dynamic> preview,
    String requestId,
  ) async => throw StateError('請書の再開を確認できません。');
  Future<bool> hasPendingRefusal(String packageId) async => false;
  Future<String?> reconcileRefusal(String packageId) async => null;
  Future<Map<String, dynamic>> refuse(
    String packageId,
    String requestId,
  ) async => throw StateError('注文の辞退を確認できません。');
  Future<bool> hasPendingApproval(String packageId) async => false;
  Future<String?> reconcileApproval(String packageId) async => null;
  Future<List<SiteOrderPendingPrepare>> pendingOutgoing(String siteId) async => const [];
  Future<String> inspectOutgoing(SiteOrderPendingPrepare entry) async =>
      throw StateError('注文の準備結果を確認できません。');
  Future<String> retireOutgoing(SiteOrderPendingPrepare entry, {required bool confirmed}) async =>
      throw StateError('注文の準備停止を確認できません。');
  Future<bool> canCreateOutgoing() async => false;
  Future<void> prepareUnsignedOutgoing(SiteOrderPendingPrepare entry,
      Map<String, dynamic> body, String connectionFingerprint) async =>
      throw StateError('注文の準備を保存できません。');
  Future<String> inspectUnsignedForReview(SiteOrderPendingPrepare entry) async =>
      throw StateError('同じログイン状態の準備結果を確認できません。');
  Future<Uint8List> renderUnsignedOutgoing(SiteOrderOutgoingConsentPreview preview) async =>
      throw StateError('注文の押印前表示を確認できません。');
  Future<List<SiteOrderConsentReference>> pendingOutgoingConsents(String siteId) async => const [];
  Future<SiteOrderOutgoingConsentPreview> previewUnsignedOutgoing(SiteOrderPendingPrepare entry) async =>
      throw StateError('注文の押印前確認を開始できません。');
  Future<SiteOrderConsentObservation> confirmUnsignedOutgoing(SiteOrderConsentReference reference, {required bool confirmed}) async =>
      throw StateError('注文の確認を保存できません。');
  Future<SiteOrderConsentObservation> inspectOutgoingConsent(SiteOrderConsentReference reference) async =>
      throw StateError('注文の結果を確認できません。');
  Future<bool> canMutateOutgoingReference(SiteOrderConsentReference reference) async => false;
  Future<List<SiteOrderDeliveryRecord>> recordedOutgoing(String siteId) async => const [];
  Future<SiteOrderDeliveryRecord> recordOutgoingDelivery(SiteOrderConsentReference reference, {required String jobId, required String recipientCompanyId}) async => throw StateError('共有結果の保管を確認できません。');
  Future<SiteOrderExecutionObservation> resolveOutgoingExecutionForReview(SiteOrderConsentReference reference, {required String jobId}) async => throw StateError('保存した注文の共有先を確認できません。');
  Future<SiteOrderExecutionObservation> inspectOutgoingExecution(SiteOrderConsentReference reference,
      {required String jobId, required String recipientCompanyId}) async =>
      throw StateError('原本の保存状態を確認できません。');
  Future<SiteOrderExecutionObservation> registerOutgoingOriginal(SiteOrderConsentReference reference,
      {required String jobId, required String recipientCompanyId, required bool confirmed}) async =>
      throw StateError('原本の保存を確認できません。');
  Future<SiteOrderExecutionObservation> shareOutgoingOriginal(SiteOrderConsentReference reference,
      {required String jobId, required String recipientCompanyId, required bool confirmed}) async =>
      throw StateError('注文の共有を確認できません。');
  Future<SiteOrderOriginalReview> reviewOutgoingOriginal(SiteOrderConsentReference reference,
      {required String jobId, required String recipientCompanyId}) async =>
      throw StateError('保存原本を確認できません。');
  Future<Uint8List> outgoingOriginalBytes(SiteOrderConsentReference reference,
      SiteOrderOriginalReview review) async => throw StateError('保存原本を表示できません。');
  Future<List<SiteOrderRegisteredTarget>> registeredOutgoingTargets(String siteId) async =>
      throw StateError('登録済み協力会社を確認できません。');
}

/// One captured SDK session/gateway lease. No automatic mutation retry or new
/// request ID after an uncertain response; the caller must read saved status.
class SiteOrderWorkflowRepository extends SiteOrderWorkflowApi {
  SiteOrderWorkflowRepository(
    this._client, {
    @visibleForTesting SiteOrderApprovalJournal? approvalJournal,
    @visibleForTesting SiteOrderOutgoingJournal? outgoingJournal,
  }) : _approvalJournal = approvalJournal ?? SiteOrderApprovalJournal(),
       _outgoingJournal = outgoingJournal ?? SiteOrderOutgoingJournal(),
       _token = _client.auth.currentSession!.accessToken,
       _session = TradeDocumentFormSession(_client) {
    _session.addListener(_scopeChanged);
  }
  static SiteOrderWorkflowRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized ||
        SupabaseBackend.client.auth.currentSession?.isExpired != false) {
      return null;
    }
    try {
      return SiteOrderWorkflowRepository(SupabaseBackend.client);
    } on StateError {
      return null;
    }
  }

  final SupabaseClient _client;
  final String _token;
  final TradeDocumentFormSession _session;
  final _retired = Completer<void>();
  final SiteOrderApprovalJournal _approvalJournal;
  final SiteOrderOutgoingJournal _outgoingJournal;
  final _consentJournal = SiteOrderConsentJournal();
  final _executionJournal = SiteOrderExecutionJournal();
  final _deliveryJournal = SiteOrderDeliveryJournal();
  final _replyJournal = SiteOrderApprovalJournal.forReplyRecovery();
  final _refusalJournal = SiteOrderRefusalJournal();
  String get _actor => _client.auth.currentUser!.id;
  String? _company, _role;
  bool _invalid = false, _disposed = false;
  bool Function()? _notificationUiContext;
  @override
  bool bindNotificationUiContext(bool Function() current) {
    if (invalidated || _notificationUiContext != null) return false;
    _notificationUiContext = current;
    try { _requireNotificationUiContext(); return true; }
    catch (_) { return false; }
  }
  void _requireNotificationUiContext() {
    final current = _notificationUiContext;
    if (current == null) return; // Existing non-notification callers unchanged.
    bool allowed;
    try { allowed = current(); } catch (_) { allowed = false; }
    if (!allowed) {
      _invalidate(deferNotification: true);
      throw StateError('通知一覧から開き直してください。');
    }
  }
  @override
  void retireUiScope() {
    if (uiRetired) return;
    super.retireUiScope();
    _invalidate();
  }
  @override
  ({String actorId, String companyId, String sessionId})? get notificationReadBinding {
    requireCurrent();
    final company = _company, sid = _capturedSessionId;
    if (company == null || sid == null || _role == null) return null;
    return (actorId: _actor, companyId: company, sessionId: sid);
  }
  @override
  bool isNotificationReadClient(Object client) => identical(client, _client);
  @override
  bool get invalidated => _invalid || uiRetired;
  void _scopeChanged() {
    if (!_session.isCurrent) _invalidate();
  }

  void _invalidate({bool deferNotification = false}) {
    if (_invalid) return;
    _invalid = true;
    if (!_retired.isCompleted) _retired.complete();
    if (deferNotification) {
      // A child's initState may discover parent-context retirement while its
      // route is being built. Deny now, notify surviving siblings after build.
      scheduleMicrotask(() { if (!_disposed) notifyListeners(); });
    } else {
      notifyListeners();
    }
  }

  @override
  void requireCurrent() {
    _requireNotificationUiContext();
    if (invalidated) throw StateError('画面を開き直してください。');
    _session.requireScope();
  }

  @override
  Future<void> verify() async {
    try {
      _requireNotificationUiContext();
      if (invalidated) throw StateError('画面を開き直してください。');
      await _session.ready();
      _requireNotificationUiContext();
      final raw = await _session.readOwnMemberships();
      _requireNotificationUiContext();
      if (raw is! List || raw.length != 1 || raw.single is! Map) {
        throw StateError('会社登録を確認してください。');
      }
      final row = raw.single as Map;
      final company = row['company_id']?.toString(),
          role = row['role']?.toString();
      if (company == null ||
          !const {'owner', 'admin', 'manager'}.contains(role) ||
          (_company != null && (_company != company || _role != role))) {
        throw StateError('会社・権限が変わりました。開き直してください。');
      }
      _company ??= company;
      _role ??= role;
      _session.requireScope();
    } catch (_) {
      _invalidate();
      rethrow;
    }
  }

  Future<Object?> _call(Map<String, dynamic> body, {bool write = false, bool outgoing = false}) async {
    await verify();
    requireCurrent();
    try {
      final response = await _client.functions
          .invoke(
            outgoing ? 'site-order-workflow/outgoing' : 'site-order-workflow',
            headers: {'Authorization': 'Bearer $_token'},
            body: body,
            abortSignal: _retired.future,
          )
          .timeout(const Duration(seconds: 60));
      await verify();
      return response.data;
    } on FunctionException catch (error) {
      await verify();
      if (error.status == 409 ||
          (write && (error.status == 0 || error.status >= 500))) {
        throw const SiteOrderResultUnknown();
      }
      throw StateError('注文・請書を確認できません。状態を確認して開き直してください。');
    } on TimeoutException {
      if (write) throw const SiteOrderResultUnknown();
      throw StateError('読み込みを確認できません。もう一度開いてください。');
    } catch (_) {
      if (write) throw const SiteOrderResultUnknown();
      rethrow;
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw StateError('保存状態を確認できません。');
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> _result(Map<String, dynamic> command) async =>
      _map(_map(await _call(command))['result']);

  @override
  Future<List<SiteOrderPendingPrepare>> pendingOutgoing(String siteId) async {
    await verify();
    final entries = await _outgoingJournal.read(_actor, _company!, siteId);
    await verify();
    return entries;
  }

  @override
  Future<bool> canCreateOutgoing() async {
    await verify();
    try {
      final value = _map(await _session.rpc('standalone_trade_document_access', {}));
      await verify();
      return _exactKeys(value, const {'contract_version', 'actor_id', 'session_id',
        'company_id', 'role', 'master_enabled', 'can_generate', 'context_contract_version'}) &&
        value['contract_version'] == 1 && value['context_contract_version'] == 1 &&
        value['actor_id'] == _actor && value['company_id'] == _company &&
        value['session_id'] == _capturedSessionId && _capturedSessionId != null &&
        value['role'] == _role && value['master_enabled'] == true && value['can_generate'] == true;
    } catch (_) {
      await verify();
      return false;
    }
  }

  @override
  Future<void> prepareUnsignedOutgoing(SiteOrderPendingPrepare entry,
      Map<String, dynamic> body, String connectionFingerprint) async {
    final immutable = Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map);
    await verify();
    if (entry.sessionId != _capturedSessionId ||
        immutable['transaction_id'] != entry.documentId ||
        immutable['issuer_company_id'] != _company || immutable['kind'] != 'order' ||
        immutable.containsKey('company_seal_snapshot') || immutable.containsKey('company_seal_enabled') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(connectionFingerprint) ||
        utf8.encode(jsonEncode(immutable)).length > 32768) {
      throw StateError('注文の入力元が変わりました。');
    }
    await _outgoingJournal.begin(_actor, _company!, entry);
    await verify();
    final value = _map(_map(await _call({...entry.command('prepare'),
      'connection_fingerprint': connectionFingerprint, 'body': immutable},
      write: true, outgoing: true))['result']);
    if (!_exactKeys(value, const {'contract_version', 'operation_state', 'operation_id',
      'company_id', 'request_id', 'site_id', 'document_id', 'local_document_id',
      'trade_company_id', 'body_hash', 'source_hash', 'seal_hash', 'prepared_at',
      'retired', 'journal_clearable', 'retry_automatically', 'may_prepare_again', 'can_send'}) ||
      value['contract_version'] != 1 || value['operation_state'] != 'prepared_review_required' ||
      value['company_id'] != _company || value['request_id'] != entry.requestId ||
      value['site_id'] != entry.siteId || value['document_id'] != entry.documentId ||
      value['local_document_id'] != entry.localId || value['trade_company_id'] != entry.tradeId ||
      !_savedId(value['operation_id']) || value['retired'] != false ||
      value['journal_clearable'] != false || value['retry_automatically'] != false ||
      value['may_prepare_again'] != false || value['can_send'] != false ||
      value['prepared_at'] is! String || DateTime.tryParse(value['prepared_at']) == null ||
      !['body_hash', 'source_hash', 'seal_hash'].every((k) => value[k] is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value[k]))) {
      throw const SiteOrderResultUnknown();
    }
  }

  @override
  Future<Uint8List> renderUnsignedOutgoing(SiteOrderOutgoingConsentPreview preview) async {
    await verify();
    final bytes = await preview.render();
    await verify();
    return bytes;
  }

  @override
  Future<List<SiteOrderConsentReference>> pendingOutgoingConsents(String siteId) async {
    await verify();
    final entries = await _consentJournal.read(_actor, _company!, siteId);
    await verify();
    return entries;
  }

  @override
  Future<SiteOrderOutgoingConsentPreview> previewUnsignedOutgoing(SiteOrderPendingPrepare entry) async {
    await verify();
    if (entry.sessionId != _capturedSessionId) {
      throw StateError('ログイン状態が変わりました。結果照会を先に行ってください。');
    }
    final value = _map(_map(await _call(entry.command('preview_unsigned'), write: true, outgoing: true))['result']);
    if (value['document_id'] != entry.documentId ||
        (value['body'] as Map?)?['issuer_company_id'] != _company) {
      throw StateError('注文の確認元が変わりました。');
    }
    return SiteOrderOutgoingConsentPreview.fromServerEnvelope(value);
  }

  @override
  Future<SiteOrderConsentObservation> confirmUnsignedOutgoing(SiteOrderConsentReference reference, {required bool confirmed}) async {
    if (!confirmed) throw StateError('押印内容の明示確認が必要です。');
    await verify();
    if (reference.prepare.sessionId != _capturedSessionId) {
      throw StateError('ログイン状態が変わりました。結果照会を先に行ってください。');
    }
    // Persist only IDs/digest before the first mutation; unknown results retain it.
    if (!await _consentJournal.save(_actor, _company!, reference)) {
      throw StateError('確認中の注文があります。再送せず保存結果を照会してください。');
    }
    await verify();
    final result = _map(_map(await _call({...reference.command('confirm_unsigned'), 'confirmed': true}, write: true, outgoing: true))['result']);
    return SiteOrderConsentObservation.decode(result, reference, _company!);
  }

  @override
  Future<SiteOrderConsentObservation> inspectOutgoingConsent(SiteOrderConsentReference reference) async {
    await verify();
    final result = _map(_map(await _call(reference.command('decision_status'), outgoing: true))['result']);
    return SiteOrderConsentObservation.decode(result, reference, _company!);
  }

  @override
  Future<List<SiteOrderDeliveryRecord>> recordedOutgoing(String siteId) async {
    await verify();final entries=await _deliveryJournal.read(_actor,_company!,siteId);
    await verify();return entries;
  }
  @override
  Future<SiteOrderDeliveryRecord> recordOutgoingDelivery(SiteOrderConsentReference reference,
      {required String jobId,required String recipientCompanyId}) async {
    await verify();
    // Fresh server observation is mandatory even when a local marker exists.
    final observation=await inspectOutgoingExecution(reference,jobId:jobId,recipientCompanyId:recipientCompanyId);
    await verify();
    final result=await _deliveryJournal.record(_actor,_company!,reference,observation,verifyScope:verify);
    await verify();return result;
  }

  @override
  Future<bool> canMutateOutgoingReference(SiteOrderConsentReference reference) async {
    await verify();
    return reference.prepare.sessionId == _capturedSessionId && await canCreateOutgoing();
  }

  @override
  Future<SiteOrderOriginalReview> reviewOutgoingOriginal(
    SiteOrderConsentReference reference, {
    required String jobId, required String recipientCompanyId,
  }) async {
    await verify();
    final result=_map(_map(await _call(reference.command('original_review'),outgoing:true))['result']);
    return SiteOrderOriginalReview.decode(result,reference,_company!,jobId:jobId,
      recipientCompanyId:recipientCompanyId);
  }

  @override
  Future<Uint8List> outgoingOriginalBytes(SiteOrderConsentReference reference,
      SiteOrderOriginalReview review) async {
    final raw=await _call(reference.command('original_bytes'),outgoing:true);
    return review.verifyBytes(raw);
  }

  @override
  Future<SiteOrderExecutionObservation> resolveOutgoingExecutionForReview(
      SiteOrderConsentReference reference, {required String jobId}) async {
    await verify();
    final result=_map(_map(await _call(reference.command('original_status'),outgoing:true))['result']);
    final recipient=result['recipient_company_id'];
    if(!SiteOrderPendingPrepare.validId(recipient))throw StateError('保存した共有先を照合できません。');
    // First pin is from the immutable server purpose, never today's directory.
    return SiteOrderExecutionObservation.decode(result,reference,_company!,jobId:jobId,
      recipientCompanyId:recipient as String);
  }

  @override
  Future<SiteOrderExecutionObservation> inspectOutgoingExecution(
    SiteOrderConsentReference reference, {
    required String jobId,
    required String recipientCompanyId,
  }) async {
    await verify();
    final result = _map(_map(await _call(
      reference.command('original_status'), outgoing: true,
    ))['result']);
    return SiteOrderExecutionObservation.decode(result, reference, _company!,
      jobId: jobId, recipientCompanyId: recipientCompanyId);
  }

  Future<SiteOrderExecutionObservation> _executeOutgoingStage(
    SiteOrderConsentReference reference, {
    required String jobId,
    required String recipientCompanyId,
    required String stage,
    required bool confirmed,
  }) async {
    if (!confirmed) throw StateError('保存・共有内容の明示確認が必要です。');
    await verify();
    if (reference.prepare.sessionId != _capturedSessionId) {
      throw StateError('ログイン状態が変わりました。結果照会を先に行ってください。');
    }
    if (!SiteOrderPendingPrepare.validId(jobId) ||
        !SiteOrderPendingPrepare.validId(recipientCompanyId)) {
      throw StateError('注文の原本・共有先を確認できません。');
    }
    if (!await _executionJournal.begin(_actor, _company!, reference, stage)) {
      throw StateError('保存・共有を確認中です。再送せず状態を照会してください。');
    }
    await verify();
    await _call({
      ...reference.command(stage == 'original'
          ? 'register_outgoing_original' : 'share_confirmed'),
      if (stage == 'share') 'confirmed': true,
    }, write: true, outgoing: true);
    // Observe durable server evidence in a separate request. A mutation response
    // alone never clears quarantine or claims recipient acknowledgement.
    final result = await inspectOutgoingExecution(reference,
      jobId: jobId, recipientCompanyId: recipientCompanyId);
    if (stage == 'original' ? !result.originalSaved : !result.recipientStored) {
      throw const SiteOrderResultUnknown();
    }
    return result;
  }

  @override
  Future<SiteOrderExecutionObservation> registerOutgoingOriginal(
    SiteOrderConsentReference reference, {
    required String jobId,
    required String recipientCompanyId,
    required bool confirmed,
  }) => _executeOutgoingStage(reference, jobId: jobId,
    recipientCompanyId: recipientCompanyId, stage: 'original', confirmed: confirmed);

  @override
  Future<SiteOrderExecutionObservation> shareOutgoingOriginal(
    SiteOrderConsentReference reference, {
    required String jobId,
    required String recipientCompanyId,
    required bool confirmed,
  }) => _executeOutgoingStage(reference, jobId: jobId,
    recipientCompanyId: recipientCompanyId, stage: 'share', confirmed: confirmed);

  @override
  Future<List<SiteOrderRegisteredTarget>> registeredOutgoingTargets(String siteId) async {
    if(!_savedId(siteId)) throw StateError('現場を確認してください。');
    final targets=<SiteOrderRegisteredTarget>[], seen=<String>{};
    String? cursor;
    for(var page=0;page<200;page++) {
      await verify();
      final value=_map(_map(await _call({'action':'targets','site_id':siteId,'before':cursor,'limit':50},outgoing:true))['result']);
      if(!_exactKeys(value,const {'contract_version','actor_id','session_id','company_id','site_id','entries','has_more','next_cursor','read_only','can_send'})||
          value['contract_version']!=1||value['actor_id']!=_actor||value['session_id']!=_capturedSessionId||
          _capturedSessionId==null||value['company_id']!=_company||value['site_id']!=siteId||
          value['entries'] is! List||value['has_more'] is! bool||value['read_only']!=true||value['can_send']!=false) {
        throw StateError('登録済み協力会社の状態を確認できません。');
      }
      final rows=value['entries'] as List;
      if(rows.length>50) throw StateError('登録会社の件数を確認できません。');
      String? last=cursor;
      for(final raw in rows) {
        final row=_map(raw);
        if(!_exactKeys(row,const {'id','name'})||!_savedId(row['id'])||row['name'] is! String||
            (row['name'] as String).trim().isEmpty||(row['name'] as String).runes.length>240||
            !seen.add(row['id'] as String)||(last!=null&&(row['id'] as String).compareTo(last)<=0)) {
          throw StateError('登録会社の識別情報を確認できません。');
        }
        last=row['id'] as String;targets.add(SiteOrderRegisteredTarget(id:last,name:row['name'] as String));
      }
      if(value['has_more']==false) {
        if(value['next_cursor']!=null) throw StateError('登録会社の続き状態を確認できません。');
        await verify();return List.unmodifiable(targets);
      }
      if(rows.length!=50||last==null||value['next_cursor']!=last) {
        throw StateError('登録会社の続き状態を確認できません。');
      }
      cursor=last;
    }
    // Never return a truncated list as if it covered the company directory.
    throw StateError('登録会社の全件を確認できません。画面を開き直してください。');
  }

  Future<String> _outgoingState(
    SiteOrderPendingPrepare entry, {
    required bool retire,
    bool requireSameSession = false,
  }) async {
    await verify();
    if (requireSameSession && entry.sessionId != _capturedSessionId) {
      throw StateError('ログイン状態が変わりました。結果照会から確認してください。');
    }
    final actor = _actor, company = _company!;
    final saved = await _outgoingJournal.read(actor, company, entry.siteId);
    if (!saved.any(
      (e) => jsonEncode(e.toJson()) == jsonEncode(entry.toJson()),
    )) {
      throw StateError('保存された注文を確認できません。');
    }
    final value = _map(
      _map(
        await _call(
          {
            ...entry.command(retire ? 'retire' : 'status'),
            if (retire) 'confirmed': true,
          },
          write: retire,
          outgoing: true,
        ),
      )['result'],
    );
    final state = value['operation_state'];
    if (value['contract_version'] != 1 ||
        value['company_id'] != company ||
        value['site_id'] != entry.siteId ||
        value['document_id'] != entry.documentId ||
        value['local_document_id'] != entry.localId ||
        value['trade_company_id'] != entry.tradeId ||
        value['request_id'] != entry.requestId ||
        value['retry_automatically'] != false ||
        value['may_prepare_again'] != false ||
        value['can_send'] != false ||
        !const {
          'not_observed',
          'prepared_review_required',
          'advanced',
          'changed',
          'retired',
        }.contains(state)) {
      throw const SiteOrderResultUnknown();
    }
    if (requireSameSession && state != 'retired' &&
        (value['same_session'] != true || value['requires_fresh_review'] != true)) {
      throw const SiteOrderResultUnknown();
    }
    if (state == 'retired') {
      if (value['retired'] != true ||
          value['order_cancelled'] != false ||
          value['journal_clearable'] != true ||
          !_savedId(value['retirement_id']) ||
          (value['verified_prepared_operation'] != true &&
              value['verified_prepared_operation'] != false) ||
          (value['verified_prepared_operation'] == true &&
              !_savedId(value['operation_id'])) ||
          (value['verified_prepared_operation'] == false &&
              value['operation_id'] != null)) {
        throw const SiteOrderResultUnknown();
      }
      await verify();
      await _outgoingJournal.resolveRetired(actor, company, entry);
      await verify();
    } else if (value['retired'] != false ||
        value['journal_clearable'] != false) {
      throw const SiteOrderResultUnknown();
    }
    return state as String;
  }

  @override
  Future<String> inspectUnsignedForReview(SiteOrderPendingPrepare entry) =>
      _outgoingState(entry, retire: false, requireSameSession: true);

  @override
  Future<String> inspectOutgoing(SiteOrderPendingPrepare entry) =>
      _outgoingState(entry, retire: false);

  @override
  Future<String> retireOutgoing(
    SiteOrderPendingPrepare entry, {
    required bool confirmed,
  }) {
    if (!confirmed) throw StateError('準備停止の確認が必要です。');
    return _outgoingState(entry, retire: true);
  }

  @override
  Future<Map<String, dynamic>> detail(String id) =>
      _result({'action': 'detail', 'package_id': id});

  String? get _capturedSessionId {
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(_token.split('.')[1]))));
      final value = payload is Map ? payload['session_id'] : null;
      return _savedId(value) ? value as String : null;
    } catch (_) { return null; }
  }

  bool _exactKeys(Map<String, dynamic> value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);

  @override
  Future<Map<String, dynamic>> outgoingContext(String siteId, String tradeId) async {
    final value = await _result({'action': 'outgoing_context', 'site_id': siteId, 'trade_id': tradeId});
    if (!_exactKeys(value, const {'contract_version','actor_id','session_id','company_id',
          'site_id','trade_company_id','counterparty_company_id','connection_fingerprint',
          'issuer','counterparty','site','own_seal','creates_document','records_consent','can_send'}) ||
        value['contract_version'] != 1 || value['actor_id'] != _actor ||
        value['session_id'] != _capturedSessionId || _capturedSessionId == null ||
        value['company_id'] != _company || value['site_id'] != siteId || value['trade_company_id'] != tradeId ||
        value['issuer'] is! Map || value['counterparty'] is! Map || value['site'] is! Map ||
        value['own_seal'] is! Map || value['creates_document'] != false ||
        value['records_consent'] != false || value['can_send'] != false ||
        !_savedId(value['counterparty_company_id']) || value['counterparty_company_id'] == _company ||
        value['connection_fingerprint'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['connection_fingerprint'] as String)) {
      throw StateError('注文書の登録元・会社を確認できません。');
    }
    final issuer = _map(value['issuer']), counterparty = _map(value['counterparty']);
    if (!_exactKeys(issuer, const {'name','address','representative_name','corporate_number','phone','fax'}) ||
        !_exactKeys(counterparty, const {'name','address','representative_name','corporate_number','phone'}) ||
        !_exactKeys(_map(value['site']), const {'name','address','period_start','period_end'}) ||
        issuer.values.any((v) => v is! String) || counterparty.values.any((v) => v is! String) ||
        (issuer['name'] as String).trim().isEmpty || (counterparty['name'] as String).trim().isEmpty) {
      throw StateError('注文書の登録情報を確認できません。');
    }
    final seal = _map(value['own_seal']);
    if (!_exactKeys(seal, const {'snapshot','seal_hash','version_id','asset_hash','version_key','renderer_contract'}) ||
        seal['version_key'] is! String || seal['renderer_contract'] is! String ||
        seal['snapshot'] is! Map || seal['seal_hash'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(seal['seal_hash'] as String)) {
      throw StateError('自社の登録角印を確認できません。');
    }
    final snapshot = CompanySealSnapshot.fromJson(seal['snapshot']);
    if (snapshot.name != issuer['name'] || (snapshot.companyId != null && snapshot.companyId != _company)) {
      throw StateError('自社の登録角印を確認できません。');
    }
    requireCurrent();
    return value;
  }

  @override
  Future<Map<String, dynamic>> observePrepare(String siteId, String documentId, String localId, String tradeId) async {
    final value = await _result({'action': 'observe_prepare', 'site_id': siteId,
      'document_id': documentId, 'local_id': localId, 'trade_id': tradeId});
    final keys = <String>{'contract_version','company_id','site_id','document_id','local_document_id',
      'trade_company_id','retry_automatically','may_prepare_again','can_send','journal_clearable','operation_state',
      if (value['operation_state'] == 'prepared_review_required') ...{
        'revision','body','body_hash','may_request_fresh_preview','reuses_previous_consent'}};
    if (!_exactKeys(value, keys) || value['contract_version'] != 1 || value['company_id'] != _company ||
        value['site_id'] != siteId || value['document_id'] != documentId ||
        value['local_document_id'] != localId || value['trade_company_id'] != tradeId ||
        value['retry_automatically'] != false || value['may_prepare_again'] != false ||
        value['can_send'] != false || value['journal_clearable'] != false ||
        !const {'not_observed','changed','not_a_pending_prepare','prepared_review_required'}.contains(value['operation_state'])) {
      throw const SiteOrderResultUnknown();
    }
    if (value['operation_state'] == 'prepared_review_required') {
      final body = value['body'];
      if (body is! Map || body['transaction_id'] != documentId || body['issuer_company_id'] != _company ||
          !_savedId(body['counterparty_company_id']) || body['counterparty_company_id'] == _company ||
          const ['company_seal_snapshot','company_seal_enabled','seals','approved_by','actor_id'].any(body.containsKey) ||
          body['kind'] != 'order' || value['revision'] != 1 || value['body_hash'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['body_hash'] as String) ||
          value['may_request_fresh_preview'] != true || value['reuses_previous_consent'] != false) {
        throw const SiteOrderResultUnknown();
      }
    } else if (value.containsKey('body') || value.containsKey('body_hash')) {
      throw const SiteOrderResultUnknown();
    }
    // This read never clears a journal or turns absence into cancellation.
    requireCurrent();
    return value;
  }
  @override
  Future<List<Map<String, dynamic>>> history({
    String? before,
    String? beforeId,
  }) async {
    final value = _map(
      await _call({
        'action': 'list',
        'before': before,
        'before_id': beforeId,
        'limit': 50,
      }),
    )['result'];
    if (value is! List) throw StateError('履歴を確認できません。');
    return value.map(_map).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> historyForSite(
    String siteId, {
    String? before,
    String? beforeId,
  }) async {
    final value = _map(
      await _call({
        'action': 'site_history',
        'site_id': siteId,
        'before': before,
        'before_id': beforeId,
        'limit': 50,
      }),
    )['result'];
    if (value is! List) { throw StateError('現場の注文履歴を確認できません。'); }
    return value.map(_map).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> targets(String id) async {
    final value = _map(
      await _call({'action': 'recipient_targets', 'package_id': id}),
    )['result'];
    if (value is! List) throw StateError('取引会社の登録を確認してください。');
    return value.map(_map).toList(growable: false);
  }

  bool _savedId(Object? value) =>
      value is String &&
      RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(value);
  @override
  Future<Map<String, dynamic>> preview(
    String id,
    Map<String, dynamic> target,
  ) async {
    final value = await _result({
      'action': 'preview_approval',
      'package_id': id,
      'trade_id': target['trade_id'],
      'connection_fingerprint': target['connection_fingerprint'],
      'request_id': siteOrderRequestId(),
    });
    if (value['package_id'] != id ||
        !_savedId(value['preview_id']) ||
        value['body_hash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['body_hash'] as String)) {
      throw StateError('確認する注文の保存版が変わりました。');
    }
    return value;
  }

  @override
  Future<bool> hasPendingReplyRecovery(String id) async {
    await verify();
    return await _replyJournal.read(_actor, _company!, id) != null;
  }

  @override
  Future<String?> reconcileReplyRecovery(String id) async {
    await verify();
    final pending = await _replyJournal.read(_actor, _company!, id);
    if (pending == null) return null;
    final result = _map(
      _map(
        await _call({
          'action': 'reconcile_reply_recovery',
          ...pending,
        }, write: true),
      )['result'],
    );
    if (result['package_id'] != id ||
        result['preview_id'] != pending['preview_id'] ||
        result['request_id'] != pending['request_id'] ||
        !const {'accepted', 'cancelled'}.contains(result['operation_state'])) {
      throw const SiteOrderResultUnknown();
    }
    await verify();
    await _replyJournal.resolve(_actor, _company!, id, pending['request_id']!);
    return result['operation_state'] as String;
  }

  @override
  Future<Map<String, dynamic>> previewReplyRecovery(String id) async {
    await verify();
    if (await hasPendingReplyRecovery(id)) throw const SiteOrderResultUnknown();
    final result = await _result({
      'action': 'preview_reply_recovery',
      'package_id': id,
      'request_id': siteOrderRequestId(),
    });
    if (result['package_id'] != id || !_savedId(result['preview_id'])) {
      throw StateError('請書の保存版を確認できません。');
    }
    return result;
  }

  @override
  Future<Uint8List> renderReplyRecovery(Map<String, dynamic> preview) async {
    final evidence = _map(preview['evidence']);
    final seals = evidence['seals'];
    if (seals is! List || seals.length != 1) throw StateError('自社印を確認できません。');
    return renderReview({
      'body': preview['body'],
      'own_seal': {'snapshot': _map(seals.single)['seal_snapshot']},
    });
  }

  @override
  Future<Map<String, dynamic>> recoverReply(
    Map<String, dynamic> preview,
    String requestId,
  ) async {
    await verify();
    final id = preview['package_id'];
    if (!_savedId(id) ||
        !_savedId(preview['preview_id']) ||
        !_savedId(requestId)) {
      throw StateError('請書の再確認情報が変わりました。');
    }
    await _replyJournal.begin(
      _actor,
      _company!,
      id as String,
      preview['preview_id'] as String,
      requestId,
    );
    try {
      final lease = _map(
        _map(
          await _call({
            'action': 'confirm_reply_recovery',
            'preview_id': preview['preview_id'],
            'body_hash': preview['body_hash'],
            'render_hash': preview['render_hash'],
            'seal_hash': preview['seal_hash'],
            'confirmed': true,
            'request_id': requestId,
          }, write: true),
        )['result'],
      );
      if (lease['package_id'] != id ||
          !_savedId(lease['lease_id']) ||
          lease['status'] != 'reply_recovery_confirmed') {
        throw const SiteOrderResultUnknown();
      }
      final outcome = _writeOutcome(
        await _call({
          'action': 'process_recovered_reply',
          'package_id': id,
          'lease_id': lease['lease_id'],
        }, write: true),
        id,
      );
      // Only the serialized delivery/cancellation barrier clears this journal.
      // A queued/unknown worker response remains quarantined across restarts.
      if (_map(outcome['result'])['status'] == 'recipient_stored') {
        if (await reconcileReplyRecovery(id) != 'accepted') {
          throw const SiteOrderResultUnknown();
        }
      }
      return outcome;
    } catch (_) {
      throw const SiteOrderResultUnknown();
    }
  }

  Map<String, dynamic> _writeOutcome(Object? raw, Object? expectedPackage) {
    try {
      final envelope = _map(raw), result = _map(envelope['result']);
      if (result['package_id'] != expectedPackage) {
        throw const SiteOrderResultUnknown();
      }
      final terminal =
          result['status'] == 'recipient_stored' &&
          _savedId(result['original_receipt_id']) &&
          envelope['reply_processing'] == null;
      final pending =
          result['status'] == 'approved_reply_queued' &&
          _savedId(result['job_id']) &&
          const {
            'pending',
            'result_unknown',
          }.contains(envelope['reply_processing']) &&
          envelope['retry_automatically'] == false;
      if (!terminal && !pending) throw const SiteOrderResultUnknown();
      return envelope;
    } catch (_) {
      throw const SiteOrderResultUnknown();
    }
  }

  @override
  Future<Uint8List> renderReview(Map<String, dynamic> review) async {
    await verify();
    final body = _map(jsonDecode(jsonEncode(review['body'])));
    final ownSeal = _map(review['own_seal']);
    final snapshot = _map(ownSeal['snapshot']);
    if (body['kind'] != 'acceptance' ||
        body['issuer_company_id'] != _company ||
        CompanySealSnapshot.fromJson(snapshot).registeredName('') !=
            _map(body['issuer'])['name']) {
      throw StateError('自社印と請書の内容を確認できません。');
    }
    final bytes = await TradeDocumentFormRenderer.canonical({
      ...body,
      'company_seal_snapshot': snapshot,
      'company_seal_enabled': true,
    });
    await verify();
    return bytes; // Review only: never registered/exported as an original.
  }

  @override
  Future<bool> hasPendingApproval(String packageId) async {
    await verify();
    return await _approvalJournal.read(_actor, _company!, packageId) != null;
  }

  @override
  Future<String?> reconcileApproval(String packageId) async {
    await verify();
    final pending = await _approvalJournal.read(_actor, _company!, packageId);
    if (pending == null) return null;
    final result = _map(
      _map(
        await _call({'action': 'reconcile_approval', ...pending}, write: true),
      )['result'],
    );
    if (result['package_id'] != packageId ||
        result['request_id'] != pending['request_id'] ||
        result['preview_id'] != pending['preview_id'] ||
        !const {'accepted', 'cancelled'}.contains(result['operation_state'])) {
      throw const SiteOrderResultUnknown();
    }
    await verify();
    await _approvalJournal.resolve(
      _actor,
      _company!,
      packageId,
      pending['request_id']!,
    );
    return result['operation_state'] as String;
  }

  @override
  Future<Map<String, dynamic>> approve(
    Map<String, dynamic> review,
    String requestId,
  ) async {
    await verify();
    final id = review['package_id'];
    if (!_savedId(id) ||
        !_savedId(review['preview_id']) ||
        !_savedId(requestId)) {
      throw StateError('承認内容を確認できません。');
    }
    if (await hasPendingApproval(id as String) || await hasPendingRefusal(id)) {
      throw const SiteOrderResultUnknown();
    }
    await _approvalJournal.begin(
      _actor,
      _company!,
      id,
      review['preview_id'] as String,
      requestId,
    );
    try {
      final result = _writeOutcome(
        await _call({
          'action': 'approve',
          'preview_id': review['preview_id'],
          'body_hash': review['body_hash'],
          'seal_hash': _map(review['own_seal'])['seal_hash'],
          'confirmed': true,
          'request_id': requestId,
        }, write: true),
        id,
      );
      await _approvalJournal.resolve(_actor, _company!, id, requestId);
      return result;
    } catch (_) {
      // The persisted entry outlives this page/session. Never infer rejection
      // from a network error, cancellation or a negative package-detail read.
      throw const SiteOrderResultUnknown();
    }
  }

  @override
  Future<bool> hasPendingRefusal(String packageId) async {
    await verify();
    return await _refusalJournal.read(_actor, _company!, packageId) != null;
  }

  @override
  Future<String?> reconcileRefusal(String packageId) async {
    await verify();
    final pending = await _refusalJournal.read(_actor, _company!, packageId);
    if (pending == null) return null;
    final result = _map(
      _map(
        await _call({'action': 'reconcile_refusal', ...pending}, write: true),
      )['result'],
    );
    if (result['package_id'] != packageId ||
        result['request_id'] != pending['request_id'] ||
        !const {'accepted', 'cancelled'}.contains(result['operation_state'])) {
      throw const SiteOrderResultUnknown();
    }
    await verify();
    await _refusalJournal.resolve(
      _actor,
      _company!,
      packageId,
      pending['request_id']!,
    );
    return result['operation_state'] as String;
  }

  @override
  Future<Map<String, dynamic>> refuse(
    String packageId,
    String requestId,
  ) async {
    await verify();
    if (!_savedId(packageId) || !_savedId(requestId)) {
      throw StateError('注文を確認できません。');
    }
    if (await hasPendingApproval(packageId) ||
        await hasPendingRefusal(packageId)) {
      throw const SiteOrderResultUnknown();
    }
    await _refusalJournal.begin(_actor, _company!, packageId, requestId);
    try {
      final result = _map(
        _map(
          await _call({
            'action': 'refuse',
            'confirmed': true,
            'package_id': packageId,
            'request_id': requestId,
          }, write: true),
        )['result'],
      );
      if (result['package_id'] != packageId ||
          result['request_id'] != requestId ||
          result['status'] != 'rejected') {
        throw const SiteOrderResultUnknown();
      }
      await _refusalJournal.resolve(_actor, _company!, packageId, requestId);
      return result;
    } catch (_) {
      throw const SiteOrderResultUnknown();
    }
  }

  @override
  Future<Map<String, dynamic>> resume(String id) async => _writeOutcome(
    await _call({'action': 'process_reply', 'package_id': id}, write: true),
    id,
  );
  @override
  Future<Map<String, dynamic>> originalPayload(String id, String kind) =>
      _result({'action': 'archive_payload', 'package_id': id, 'kind': kind});

  @override
  Future<Uint8List> original(String id, String kind) async {
    final raw = await _call({
      'action': 'archive',
      'package_id': id,
      'kind': kind,
    });
    if (raw is! Uint8List ||
        raw.length < 16 ||
        raw.length > 20 * 1024 * 1024 ||
        ascii.decode(raw.sublist(0, 5), allowInvalid: true) != '%PDF-') {
      throw StateError('保存済み原本を確認できません。');
    }
    return Uint8List.fromList(raw);
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidate();
    _session.removeListener(_scopeChanged);
    if (!_retired.isCompleted) _retired.complete();
    _session.dispose();
    super.dispose();
  }
}
