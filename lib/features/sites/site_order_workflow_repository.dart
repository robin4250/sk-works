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
  bool get invalidated;
  void requireCurrent();
  Future<Map<String, dynamic>> detail(String packageId);
  Future<List<Map<String, dynamic>>> history({
    String? before,
    String? beforeId,
  });
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
  Future<bool> hasPendingRefusal(String packageId) async => false;
  Future<String?> reconcileRefusal(String packageId) async => null;
  Future<Map<String, dynamic>> refuse(
    String packageId,
    String requestId,
  ) async => throw StateError('注文の辞退を確認できません。');
  Future<bool> hasPendingApproval(String packageId) async => false;
  Future<String?> reconcileApproval(String packageId) async => null;
}

/// One captured SDK session/gateway lease. No automatic mutation retry or new
/// request ID after an uncertain response; the caller must read saved status.
class SiteOrderWorkflowRepository extends SiteOrderWorkflowApi {
  SiteOrderWorkflowRepository(
    this._client, {
    @visibleForTesting SiteOrderApprovalJournal? approvalJournal,
  }) : _approvalJournal = approvalJournal ?? SiteOrderApprovalJournal(),
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
  final _refusalJournal = SiteOrderRefusalJournal();
  String get _actor => _client.auth.currentUser!.id;
  String? _company, _role;
  bool _invalid = false;
  @override
  bool get invalidated => _invalid;
  void _scopeChanged() {
    if (!_session.isCurrent) _invalidate();
  }

  void _invalidate() {
    if (_invalid) return;
    _invalid = true;
    if (!_retired.isCompleted) _retired.complete();
    notifyListeners();
  }

  @override
  void requireCurrent() {
    if (_invalid) throw StateError('画面を開き直してください。');
    _session.requireScope();
  }

  @override
  Future<void> verify() async {
    try {
      if (_invalid) throw StateError('画面を開き直してください。');
      await _session.ready();
      final raw = await _session.readOwnMemberships();
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

  Future<Object?> _call(Map<String, dynamic> body, {bool write = false}) async {
    await verify();
    try {
      final response = await _client.functions
          .invoke(
            'site-order-workflow',
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
  Future<Map<String, dynamic>> detail(String id) =>
      _result({'action': 'detail', 'package_id': id});
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
  Future<Map<String, dynamic>> refuse(String id, String requestId) async {
    await verify();
    if (!_savedId(id) || !_savedId(requestId)) {
      throw StateError('注文を確認できません。');
    }
    if (await hasPendingApproval(id) || await hasPendingRefusal(id)) {
      throw const SiteOrderResultUnknown();
    }
    await _refusalJournal.begin(_actor, _company!, id, requestId);
    try {
      final result = _map(
        _map(
          await _call({
            'action': 'refuse',
            'confirmed': true,
            'package_id': id,
            'request_id': requestId,
          }, write: true),
        )['result'],
      );
      if (result['package_id'] != id ||
          result['request_id'] != requestId ||
          result['status'] != 'rejected') {
        throw const SiteOrderResultUnknown();
      }
      await _refusalJournal.resolve(_actor, _company!, id, requestId);
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
    _invalidate();
    _session.removeListener(_scopeChanged);
    if (!_retired.isCompleted) _retired.complete();
    _session.dispose();
    super.dispose();
  }
}
