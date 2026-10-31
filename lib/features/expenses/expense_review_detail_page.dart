import 'package:flutter/material.dart';
import 'expense_claim.dart';
import 'expense_receipt_preview.dart';
import 'expense_review_flow_dialog.dart';

class ExpenseReviewDetailPage extends StatelessWidget {
  const ExpenseReviewDetailPage({super.key, required this.claim, this.onEdit, this.onHistory, this.onDelete});
  final ExpenseClaim claim;
  final Future<void> Function()? onEdit, onHistory, onDelete;

  @override
  Widget build(BuildContext context) {
    final approved = claim.approval == ExpenseApproval.approved;
    final rejected = claim.approval == ExpenseApproval.rejected;
    final status = claim.managerDeleted ? '管理者削除（原本保持）' : approved ? '承認済み' : rejected ? '却下済み' : '承認待ち';
    final time = claim.reviewedAt?.toUtc().add(const Duration(hours: 9));
    final colors = Theme.of(context).colorScheme;
    final statusColor = approved ? Colors.green.shade800 : rejected ? Colors.red.shade800 : colors.primary;
    final statusBackground = approved ? Colors.green.shade50 : rejected ? Colors.red.shade50 : colors.primaryContainer;
    final statusIcon = approved ? Icons.check_circle : rejected ? Icons.cancel : Icons.schedule;
    final amount = claim.amountYen.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},');

    Widget detailRow(IconData icon, String label, String value, {bool statusRow = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Semantics(label: '$label：$value', excludeSemantics: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22, color: statusRow ? statusColor : colors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('$label：$value', style: TextStyle(
            fontSize: 15, height: 1.5,
            fontWeight: statusRow ? FontWeight.w700 : FontWeight.w500,
            color: statusRow ? statusColor : colors.onSurface))),
        ])),
    );

    return Scaffold(appBar: AppBar(title: const Text('経費の承認・振り分け'), actions: [
      IconButton(tooltip: 'ヘルプ', icon: const Icon(Icons.help_outline), onPressed: () => showDialog<void>(
        context: context, builder: (context) => AlertDialog(title: const Text('経費の承認・振り分け'),
          content: const SingleChildScrollView(child: Text('確定した承認状態・負担先・精算方法・メモを確認できます。内容を修正すると承認待ちへ戻ります。確定済み帳票に使われた経費は変更できません。履歴で過去の確定内容を確認し、「一覧へ戻る」で経費一覧へ戻ります。')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
        ),
      )),
    ]), body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(margin: EdgeInsets.zero, elevation: 1, color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.primary.withValues(alpha: .12))),
        child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerRight, child: Chip(
              avatar: Icon(statusIcon, size: 20, color: statusColor),
              label: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
              backgroundColor: statusBackground, side: BorderSide.none)),
            if (claim.receiptObjectPath != null) ...[
              ExpenseReceiptPreview(objectPath: claim.receiptObjectPath!),
              const SizedBox(height: 12),
            ],
            Text('$amount円', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('利用日：${claim.incurredOn.year}/${claim.incurredOn.month}/${claim.incurredOn.day}'),
            const SizedBox(height: 4), Text('申請者：${claim.applicantName}'),
            const SizedBox(height: 8), Text(claim.description),
            if (time != null) ...[
              const SizedBox(height: 12),
              Text('確認日時：${time.year}/${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: colors.onSurfaceVariant)),
            ],
            if (claim.reviewedBy != null) Text('担当：${claim.reviewedByName ?? '経費承認担当'}',
              style: TextStyle(color: colors.onSurfaceVariant)),
          ]),
        )),
      const SizedBox(height: 16),
      Card(margin: EdgeInsets.zero, elevation: 1, color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.primary.withValues(alpha: .12))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          detailRow(statusIcon, '承認', status, statusRow: true),
          if (approved) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            detailRow(Icons.business, '負担先', '${expenseBurdenLabel(claim.allocation.category)}${claim.allocation.counterpartyName == null ? '' : ' / ${claim.allocation.counterpartyName}'}'),
          ],
          if (claim.settlement != null) ...[
              const Divider(height: 1, indent: 14, endIndent: 14),
              detailRow(Icons.payments_outlined, approved ? '精算方法' : '前回の精算設定', claim.settlement!.label),
              detailRow(Icons.calendar_month, '精算対象月（申請月）', '${claim.settlement!.month.year}年${claim.settlement!.month.month}月'),
          ] else ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            detailRow(Icons.payments_outlined, '精算方法', '未設定'),
          ],
          const Divider(height: 1, indent: 14, endIndent: 14),
          detailRow(Icons.notes, rejected ? 'メモ（却下理由）' : 'メモ',
            claim.reviewMemo == null || claim.reviewMemo!.isEmpty ? 'なし' : claim.reviewMemo!),
        ])),
      const SizedBox(height: 24),
      OutlinedButton.icon(onPressed: claim.managerDeleted ? null : onEdit, icon: const Icon(Icons.edit_outlined),
        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        label: const Text('内容を修正する')),
      if (onDelete != null && !claim.managerDeleted) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: onDelete, icon: const Icon(Icons.delete_outline),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), foregroundColor: colors.error,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          label: const Text('削除')),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: onHistory, icon: const Icon(Icons.history),
        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        label: const Text('履歴を確認')),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.list),
        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        label: const Text('一覧へ戻る')),
    ]));
  }
}

