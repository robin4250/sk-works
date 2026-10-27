import 'package:flutter/material.dart';

/// Display data only. The server must independently enforce approval eligibility
/// in the same transaction as the approval itself. Unrecognised and mismatched
/// results always fail closed. Not connected to any live endpoint or screen.
enum InvoiceApprovalReadinessState {
  checking,
  unavailable,
  monthNotClosed,
  checkoutPending,
  reportPending,
  ready,
  alreadyApproved,
}

class InvoiceApprovalReadiness {
  const InvoiceApprovalReadiness._(this.state);
  const InvoiceApprovalReadiness.checking() : state = InvoiceApprovalReadinessState.checking;
  final InvoiceApprovalReadinessState state;

  factory InvoiceApprovalReadiness.fromServer(
    Object? value, {
    required String invoiceId,
    required String revision,
  }) {
    if (value is! Map || invoiceId.isEmpty || revision.isEmpty ||
        value['invoice_id'] != invoiceId || value['source_revision'] != revision) {
      return const InvoiceApprovalReadiness._(InvoiceApprovalReadinessState.unavailable);
    }
    final state = switch (value['status']) {
      'period_open' => InvoiceApprovalReadinessState.monthNotClosed,
      'checkout_pending' => InvoiceApprovalReadinessState.checkoutPending,
      'report_pending' => InvoiceApprovalReadinessState.reportPending,
      'ready' => InvoiceApprovalReadinessState.ready,
      'already_approved' => InvoiceApprovalReadinessState.alreadyApproved,
      _ => InvoiceApprovalReadinessState.unavailable,
    };
    return InvoiceApprovalReadiness._(state);
  }
}

/// The parent must re-fetch server state after invoice/account changes. The
/// callback must call a server-side atomic approval gate, not a legacy RPC.
class InvoiceApprovalReadinessNotice extends StatelessWidget {
  const InvoiceApprovalReadinessNotice({super.key, required this.readiness,
    required this.isApprover, required this.busy, required this.onApprove,
    required this.onReload});
  final InvoiceApprovalReadiness readiness;
  final bool isApprover;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final state = readiness.state;
    final label = switch (state) {
      InvoiceApprovalReadinessState.checking => '承認できる状態を確認しています',
      InvoiceApprovalReadinessState.unavailable => '承認できる状態を確認できません。管理者に確認してください。',
      InvoiceApprovalReadinessState.monthNotClosed => '対象月が終わるまで承認できません。',
      InvoiceApprovalReadinessState.checkoutPending => '対象となる勤務の退勤が必要です。',
      InvoiceApprovalReadinessState.reportPending => '対象となる日報の確定が必要です。',
      InvoiceApprovalReadinessState.ready => '対象月の退勤と日報の確定を確認しました。',
      InvoiceApprovalReadinessState.alreadyApproved => '承認済み',
    };
    final color = state == InvoiceApprovalReadinessState.alreadyApproved
        ? Colors.green.shade700 : Theme.of(context).colorScheme.onSurface;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: color)),
      if (state == InvoiceApprovalReadinessState.ready && !isApprover)
        const Text('承認は担当者が行います。'),
      if (state == InvoiceApprovalReadinessState.unavailable && onReload != null)
        TextButton(onPressed: busy ? null : onReload, child: const Text('再読み込み')),
      if (state == InvoiceApprovalReadinessState.ready && isApprover)
        FilledButton.icon(
          onPressed: busy ? null : onApprove,
          icon: const Icon(Icons.approval_outlined),
          label: Text(busy ? '承認中…' : '承認する'),
        ),
    ]);
  }
}
