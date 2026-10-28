import 'package:flutter/material.dart';
import '../../international/language_controller.dart';
import 'invoice_notice_approval_panel.dart';
import 'invoice_notice_ticket_controller.dart';

/// Fixed OFF in production until the notification flow is independently ready.
/// It is not controlled by remote config, endpoint failure or a build define.
const bool invoiceNoticeApprovalReleased = false;

/// OFF preserves the existing action; ON has no route back to that action,
/// including missing controllers, failed reads and uncertain submissions.
class InvoiceApprovalEntryActions extends StatelessWidget {
  const InvoiceApprovalEntryActions({super.key, required this.notificationOnly,
    required this.canApprove, required this.isPendingApprover,
    required this.fromNotification, required this.busy,
    required this.onLegacyApprove, required this.controller,
    required this.notificationId, required this.invoiceId,
    required this.revision, required this.confirmSavedApproval});
  final bool notificationOnly, canApprove, isPendingApprover, fromNotification, busy;
  final VoidCallback? onLegacyApprove;
  final InvoiceNoticeTicketController? controller;
  final String notificationId, invoiceId, revision;
  final Future<bool> Function() confirmSavedApproval;

  @override
  Widget build(BuildContext context) {
    if (!notificationOnly) {
      if (!canApprove) { return const SizedBox.shrink(); }
      return FilledButton.icon(
        onPressed: busy ? null : onLegacyApprove,
        icon: const Icon(Icons.approval_outlined),
        label: Text(busy
            ? (SkoLanguageController.isEnglish ? 'Approving…' : '承認中…')
            : (SkoLanguageController.isEnglish ? 'Approve' : '承認')),
      );
    }
    if (!isPendingApprover) { return const SizedBox.shrink(); }
    if (!fromNotification) {
      return const Text('承認は通知から請求書を開いて行います。');
    }
    return InvoiceNoticeApprovalPanel(controller: controller,
      notificationId: notificationId, invoiceId: invoiceId, revision: revision,
      isApprover: canApprove, confirmSavedApproval: confirmSavedApproval);
  }
}
