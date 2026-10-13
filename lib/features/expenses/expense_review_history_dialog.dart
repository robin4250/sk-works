import 'package:flutter/material.dart';
import 'expense_claim.dart';
import 'expense_settlement_choice.dart';

class ExpenseReviewHistoryDialog extends StatelessWidget {
  const ExpenseReviewHistoryDialog({super.key, required this.events});
  final List<Map<String, dynamic>> events;
  String _event(Map<String, dynamic> event) {
    final result = Map<String, dynamic>.from(event['result']);
    final command = Map<String, dynamic>.from(event['command']);
    final date = DateTime.parse(event['occurred_at']).toUtc().add(const Duration(hours: 9));
    final title = command['action'] == 'edit' ? '内容を修正' : command['action'] == 'withdraw' ? '申請を取り下げ' :
      command['action'] == 'allocate' || event['kind'] == 'allocation' ? '負担先を変更' : event['kind'] == 'settlement' ? '精算方法を設定' :
      result['approval'] == 'approved' ? '承認済み' : result['approval'] == 'rejected' ? '却下済み' : '申請を変更';
    final lines = <String>[
      '${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}　$title',
      if (result['reviewed_by_name'] != null) '担当：${result['reviewed_by_name']}',
      if (result['allocation'] is String) '負担先：${expenseCategoryLabel(ExpenseCategory.values.byName(result['allocation']))}${result['counterparty_name'] == null ? '' : ' / ${result['counterparty_name']}'}',
      if (result['settlement_method'] is String && result['settlement_month'] is String)
        '精算方法：${ExpenseSettlementChoice.decode(result['settlement_method'], result['settlement_month']).label}',
      if (result['before_row'] is Map) '修正前：${result['before_row']['description']}　${result['before_row']['amount_yen']}円',
      if (command['action'] == 'edit') '修正後：${result['description']}　${result['amount_yen']}円',
      if (result['review_memo'] is String && (result['review_memo'] as String).isNotEmpty) 'メモ：${result['review_memo']}',
    ];
    return lines.join('\n');
  }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('経費の履歴'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [if (events.isEmpty) const Text('この申請の変更履歴はまだありません。'),
        for (final event in events) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_event(event)))])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]);
}
