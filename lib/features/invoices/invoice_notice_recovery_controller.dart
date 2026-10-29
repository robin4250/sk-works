import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invoice_notice_ticket_controller.dart';

/// Private-candidate operation identity. JSON is snapshotted before dispatch so
/// subsequent edits to a preview cannot change historical result lookup scope.
class InvoiceNoticeOperation {
  InvoiceNoticeOperation({required this.ticketId, required this.localDocumentId,
    required this.companyId, required this.revision, required this.requestId,
    required this.expectedHash,
    required Map<String, dynamic> expectedPreview})
      : _preview = jsonEncode(expectedPreview) {
    final uuid = RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');
    if (![ticketId, localDocumentId, companyId, requestId].every(uuid.hasMatch) ||
        revision < 1 || expectedPreview.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) {
      throw ArgumentError('Invalid notice operation scope');
    }
  }
  final String ticketId, localDocumentId, companyId, requestId, expectedHash;
  final int revision;
  final String _preview;
  Map<String, dynamic> get parameters => {
    'ticket_id': ticketId, 'local_document_id': localDocumentId,
    'company_id': companyId, 'revision': revision,
    'request_id': requestId, 'expected_hash': expectedHash,
    'expected_preview': jsonDecode(_preview),
  };
}

enum InvoiceNoticeRecoveryState { idle, awaitingResult, recorded, unavailable, invalidated }
typedef InvoiceNoticeConsentTransport = Future<Object?> Function(InvoiceNoticeOperation operation, {required bool financialConfirmed, required bool sealConfirmed});
typedef InvoiceNoticeOperationTransport = Future<Object?> Function(InvoiceNoticeOperation operation);

/// Memory-only, opt-in composition with the existing ticket controller.
/// Transports must bind to the private candidate confirmation/result contracts.
/// No public endpoint, grants, rollout or cross-login recovery is supplied here.
class InvoiceNoticeRecoveryController extends ChangeNotifier {
  InvoiceNoticeRecoveryController({required this.actor, required this.session,
    required NoticeTicketOpener openTicket,
    required this.operationForTicket, required this.confirm, required this.readResult,
    this.timeout = const Duration(seconds: 20), SupabaseClient? authClient,
    this.explicitConsentRequired = false, this.confirmWithConsent, this.buildOwnPreview, this.closeTransport}) {
    tickets = InvoiceNoticeTicketController(actor: actor, session: session,
      openTicket: (id) async {
        // Even a newly opened ticket must not create a second approval attempt
        // while an earlier operation has an unknown or missing outcome.
        if (_operation != null || _invalidated) { return null; }
        return openTicket(id);
      }, submitApproval: _submit);
    if (authClient != null) { _observeAuth(authClient); }
  }
  final String? Function() actor, session;
  final InvoiceNoticeOperation Function(String ticket) operationForTicket;
  final InvoiceNoticeOperationTransport confirm, readResult;
  final Duration timeout;
  final bool explicitConsentRequired;
  final InvoiceNoticeConsentTransport? confirmWithConsent;
  final Future<Uint8List> Function()? buildOwnPreview;
  final VoidCallback? closeTransport;
  bool _financialConfirmed = false, _sealConfirmed = false;

  Future<InvoiceNoticeApprovalResult> approve({required bool financialConfirmed, required bool sealConfirmed}) async {
    if (explicitConsentRequired && (!financialConfirmed || !sealConfirmed)) { return InvoiceNoticeApprovalResult.notSubmitted; }
    _financialConfirmed = financialConfirmed; _sealConfirmed = sealConfirmed;
    try { return await tickets.approve(); } finally { _financialConfirmed = false; _sealConfirmed = false; }
  }
  late final InvoiceNoticeTicketController tickets;
  InvoiceNoticeRecoveryState _state = InvoiceNoticeRecoveryState.idle;
  InvoiceNoticeRecoveryState get state => _state;
  InvoiceNoticeOperation? _operation;
  String? _actor, _session;
  bool _invalidated = false, _reading = false;
  int _generation = 0;
  StreamSubscription<AuthState>? _authSubscription;

  // UI identity only. It is never an authorization decision: private SQL still
  // checks the live session and company permissions independently.
  String? _authIdentity(Session? value) {
    if (value == null) { return null; }
    try {
      final pieces = value.accessToken.split('.');
      if (pieces.length != 3) { return null; }
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(pieces[1]))));
      final sid = claims is Map ? claims['session_id'] : null;
      if (claims is! Map || claims['sub'] != value.user.id || sid is! String ||
          !RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(sid)) { return null; }
      return '${value.user.id}/$sid';
    } catch (_) { return null; }
  }

  void _observeAuth(SupabaseClient client) {
    final initialSession = client.auth.currentSession;
    final bound = _authIdentity(initialSession);
    if (bound == null || bound != '${actor()}/${session()}') { invalidate(); return; }
    var firstEvent = true;
    _authSubscription = client.auth.onAuthStateChange.listen((event) {
      // The SDK replays its last AuthState to a new subscriber. Accept only
      // that first exact captured Session object, never a later same-SID login.
      final initialReplay = firstEvent && identical(event.session, initialSession);
      firstEvent = false;
      // signedIn is a new login boundary even for actor/SID ABA. Refreshes
      // retain the operation only while the exact original identity remains.
      if (event.event == AuthChangeEvent.signedOut ||
          (event.event == AuthChangeEvent.signedIn && !initialReplay) ||
          _authIdentity(event.session) != bound || '${actor()}/${session()}' != bound) { invalidate(); }
    }, onError: (Object error, StackTrace trace) { invalidate(); }, onDone: invalidate);
  }

  @override
  void dispose() {
    invalidate();
    super.dispose();
  }

  bool _current(int generation) {
    final valid = !_invalidated && generation == _generation &&
      _actor != null && _session != null && actor() == _actor && session() == _session;
    if (!valid && !_invalidated) { invalidate(); }
    return valid;
  }

  /// Call synchronously at logout/account change, background or disposal.
  /// Terminal for this instance, even if the same SID is later supplied again.
  /// No secret, ticket or pending scope is persisted across that boundary.
  void invalidate() {
    if (_invalidated) { return; }
    _invalidated = true;
    _generation++;
    _operation = null; _actor = null; _session = null;
    _state = InvoiceNoticeRecoveryState.invalidated;
    tickets.invalidate();
    closeTransport?.call();
    final subscription = _authSubscription;
    _authSubscription = null;
    if (subscription != null) { unawaited(subscription.cancel()); }
    notifyListeners();
  }

  Future<Object?> _submit(String ticket) async {
    if (_invalidated || _operation != null ||
        explicitConsentRequired && (!_financialConfirmed || !_sealConfirmed || confirmWithConsent == null)) { return false; }
    final a = actor(), s = session();
    if (a == null || a.isEmpty || s == null || s.isEmpty) { return false; }
    final operation = operationForTicket(ticket);
    if (operation.ticketId != ticket) { return false; }
    _actor = a; _session = s; _operation = operation;
    final generation = _generation;
    _state = InvoiceNoticeRecoveryState.awaitingResult;
    if (!_current(generation)) { return false; }
    try {
      // A command return is provisional. Only explicit immutable readback can
      // establish a recorded result; errors/timeouts never resend confirmation.
      final submit = confirmWithConsent;
      if (submit != null) {
        await submit(operation, financialConfirmed: _financialConfirmed, sealConfirmed: _sealConfirmed).timeout(timeout);
      } else { await confirm(operation).timeout(timeout); }
    } catch (_) {}
    if (!_current(generation)) { return false; }
    return false;
  }

  bool _matchesRecordedScope(Object? value, InvoiceNoticeOperation operation) {
    if (value is! Map) { return false; }
    // The future server adapter must derive this envelope from the stored
    // receipt, never copy request parameters into an unbound response.
    final expected = {...operation.parameters}..remove('expected_preview');
    expected['actor_id'] = _actor;
    expected['session_id'] = _session;
    return expected.entries.every((entry) => value[entry.key] == entry.value);
  }

  Future<bool> reconcile() async {
    final operation = _operation;
    if (_reading || operation == null || !_current(_generation)) { return false; }
    final generation = _generation;
    _reading = true;
    try {
      final receipt = await readResult(operation).timeout(timeout);
      if (!_current(generation)) { return false; }
      final result = receipt is Map ? receipt['result'] : null;
      final recorded = receipt is Map && receipt['found'] == true &&
        receipt['status'] == 'recorded' &&
        _matchesRecordedScope(receipt['scope'], operation) && result is Map &&
        result['financial_approved'] == true && result['seal_consent_recorded'] == true;
      _state = recorded ? InvoiceNoticeRecoveryState.recorded : InvoiceNoticeRecoveryState.unavailable;
      return recorded;
    } catch (_) {
      if (_current(generation)) { _state = InvoiceNoticeRecoveryState.unavailable; }
      return false;
    } finally { _reading = false; }
  }
}
