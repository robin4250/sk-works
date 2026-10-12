import 'package:flutter/material.dart';
import 'expense_claim.dart';
import 'expense_receipt_preview.dart';
import 'expense_review_flow_dialog.dart';

class ExpenseReviewDetailPage extends StatelessWidget {
  const ExpenseReviewDetailPage({super.key, required this.claim, this.onEdit, this.onHistory});
  final ExpenseClaim claim;
  final Future<void> Function()? onEdit, onHistory;
  @override
  Widget build(BuildContext context) {
    final approved = claim.approval == ExpenseApproval.approved;
    final status = approved ? '承認済み' : claim.approval == ExpenseApproval.rejected ? '却下済み' : '承認待ち';
    final time = claim.reviewedAt?.toUtc().add(const Duration(hours: 9));
    return Scaffold(appBar: AppBar(title: const Text('経費の詳細')), body: ListView(padding: const EdgeInsets.all(16), children: [
      if (claim.receiptObjectPath != null) ExpenseReceiptPreview(objectPath: claim.receiptObjectPath!),
      Text('${claim.amountYen}円', style: Theme.of(context).textTheme.headlineSmall),
      Text('利用日：${claim.incurredOn.year}/${claim.incurredOn.month}/${claim.incurredOn.day}'),
      Text('申請者：${claim.applicantName}'),
      const SizedBox(height: 8), Text(claim.description), const SizedBox(height: 16),
      Chip(label: Text(status), backgroundColor: approved ? Colors.green.shade100 : claim.approval == ExpenseApproval.rejected ? Colors.red.shade100 : null),
      if (time != null) Text('確認日時：${time.year}/${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
      if (claim.reviewedBy != null) Text('担当：${claim.reviewedByName ?? '経費承認担当'}'),
      if (approved) ...[
        Text('負担先：${expenseBurdenLabel(claim.allocation.category)}${claim.allocation.counterpartyName == null ? '' : ' / ${claim.allocation.counterpartyName}'}'),
        if (claim.settlement != null) Text('精算方法：${claim.settlement!.label}'),
        if (claim.settlement != null) Text('精算対象月（申請月）：${claim.settlement!.month.year}年${claim.settlement!.month.month}月'),
      ],
      Text('メモ：${claim.reviewMemo == null || claim.reviewMemo!.isEmpty ? 'なし' : claim.reviewMemo}'),
      const SizedBox(height: 24),
      OutlinedButton(onPressed: onEdit, child: const Text('内容を修正する')),
      OutlinedButton(onPressed: onHistory, child: const Text('履歴を確認')),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('一覧へ戻る')),
    ]));
  }
}
