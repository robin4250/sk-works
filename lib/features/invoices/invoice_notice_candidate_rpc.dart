import 'package:supabase_flutter/supabase_flutter.dart';
import 'invoice_notice_ticket_controller.dart';

/// Explicit review-only binding to ungranted candidate endpoints.
/// Never enable before production gates, compatibility and recovery pass.
/// Caller owns auth/lifecycle invalidation and must reload saved approval
/// after an unconfirmed result. No legacy approval or seal RPC fallback.
InvoiceNoticeTicketController? createInvoiceNoticeCandidateController({
  required SupabaseClient client,
  required String? Function() actor,
  required String? Function() session,
  bool enabled = false,
}) {
  if (!enabled) { return null; }
  return InvoiceNoticeTicketController(
    actor: actor,
    session: session,
    openTicket: (id) async => await client.rpc(
      'invoice_notice_open_candidate', params: {'p_notification': id}),
    submitApproval: (id) async => await client.rpc(
      'invoice_approve_notice_candidate', params: {'p_ticket': id}),
  );
}
