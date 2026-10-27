/// Read-only UI preparation for a candidate notice ticket API. It cannot
/// approve an invoice or use a seal; server-side authority is mandatory.
/// Tickets are memory-only and discarded on expiry, account/session change,
/// app background, or when the notification is reopened.
typedef NoticeTicketOpener = Future<Object?> Function(String notificationId);

class InvoiceNoticeTicketController {
  InvoiceNoticeTicketController({required this.actor, required this.session,
    required this.openTicket, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final String? Function() actor;
  final String? Function() session;
  final NoticeTicketOpener openTicket;
  final DateTime Function() _now;
  String? _actor, _session, _ticket;
  DateTime? _expires;
  int _generation = 0;
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');

  void invalidate() {
    _generation++;
    _actor = null; _session = null; _ticket = null; _expires = null;
  }

  bool get hasValidTicket {
    final valid = _ticket != null && _actor != null && _session != null &&
        actor() == _actor && session() == _session && _expires != null && _now().toUtc().isBefore(_expires!);
    if (!valid) invalidate();
    return valid;
  }

  /// Server revalidates recipient, notice, session, invoice and expiry.
  /// The response must bind both notification and invoice to the server receipt.
  /// A ticket alone never enables approval or replaces seal consent.
  Future<bool> open(String notificationId, {required String invoiceId}) async {
    invalidate();
    if (!_uuid.hasMatch(notificationId) || !_uuid.hasMatch(invoiceId)) return false;
    final currentActor = actor(), currentSession = session();
    if (currentActor == null || currentActor.isEmpty || currentSession == null || currentSession.isEmpty) return false;
    final generation = _generation;
    try {
      final result = await openTicket(notificationId);
      if (generation != _generation || actor() != currentActor || session() != currentSession || result is! Map ||
          result['notification_id'] != notificationId || result['invoice_id'] != invoiceId) return false;
      final ticket = result['ticket_id'];
      final expires = result['expires_at'];
      if (ticket is! String || !_uuid.hasMatch(ticket) || expires is! String ||
          !RegExp(r'(?:Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(expires)) return false;
      final at = DateTime.tryParse(expires)?.toUtc();
      final remaining = at?.difference(_now().toUtc());
      if (at == null || remaining == null || remaining <= Duration.zero || remaining > const Duration(minutes: 6)) return false;
      _actor = currentActor; _session = currentSession; _ticket = ticket; _expires = at;
      return true;
    } catch (_) {
      return false;
    }
  }
}
