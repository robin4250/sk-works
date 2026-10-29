import 'dart:convert';

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
typedef InvoiceNoticeOperationTransport = Future<Object?> Function(InvoiceNoticeOperation operation);

/// Memory-only, opt-in composition with the existing ticket controller.
/// Transports must bind to the private candidate confirmation/result contracts.
/// No public endpoint, grants, rollout or cross-login recovery is supplied here.
class InvoiceNoticeRecoveryController {
  InvoiceNoticeRecoveryController({required this.actor, required this.session,
    required NoticeTicketOpener openTicket,
    required this.operationForTicket, required this.confirm, required this.readResult,
    this.timeout = const Duration(seconds: 20)}) {
    tickets = InvoiceNoticeTicketController(actor: actor, session: session,
      openTicket: (id) async {
        // Even a newly opened ticket must not create a second approval attempt
        // while an earlier operation has an unknown or missing outcome.
        if (_operation != null || _invalidated) { return null; }
        return openTicket(id);
      }, submitApproval: _submit);
  }
  final String? Function() actor, session;
  final InvoiceNoticeOperation Function(String ticket) operationForTicket;
  final InvoiceNoticeOperationTransport confirm, readResult;
  final Duration timeout;
  late final InvoiceNoticeTicketController tickets;
  InvoiceNoticeRecoveryState _state = InvoiceNoticeRecoveryState.idle;
  InvoiceNoticeRecoveryState get state => _state;
  InvoiceNoticeOperation? _operation;
  String? _actor, _session;
  bool _invalidated = false, _reading = false;
  int _generation = 0;

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
    _invalidated = true;
    _generation++;
    _operation = null; _actor = null; _session = null;
    _state = InvoiceNoticeRecoveryState.invalidated;
    tickets.invalidate();
  }

  Future<Object?> _submit(String ticket) async {
    if (_invalidated || _operation != null) { return false; }
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
      await confirm(operation).timeout(timeout);
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
