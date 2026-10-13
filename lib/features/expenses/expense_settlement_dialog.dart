import 'package:flutter/material.dart';
import 'expense_claim.dart';
import 'expense_settlement_choice.dart';

class ExpenseSettlementDialog extends StatefulWidget {
  const ExpenseSettlementDialog({super.key, required this.claim});
  final ExpenseClaim claim;
  @override
  State<ExpenseSettlementDialog> createState() => _ExpenseSettlementDialogState();
}

class _ExpenseSettlementDialogState extends State<ExpenseSettlementDialog> {
  ExpenseSettlementMethod? _method;
  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    final month = ExpenseSettlementChoice.applicationMonth(claim.submittedAt);
    final ready = _method != null;
    return AlertDialog(
      title: const Text('承認と精算方法'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(claim.applicantName),
          Text('${claim.amountYen}円', style: Theme.of(context).textTheme.titleLarge),
          Text(claim.description),
          const SizedBox(height: 16),
          const Text('精算方法'),
          for (final method in [ExpenseSettlementMethod.cash, ExpenseSettlementMethod.payroll])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_method == method ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: _method == method ? Theme.of(context).colorScheme.primary : null),
              title: Text(method == ExpenseSettlementMethod.cash ? '現金精算' : '給料精算'),
              onTap: () => setState(() => _method = method),
            ),
          const SizedBox(height: 12),
          const Text('精算対象月（申請月）'),
          Text('${month.year}年${month.month}月',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('現金精算・給料精算とも、申請した月に精算予定として保存します。費用の負担先は承認後に振り分けます。'),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('戻る')),
        FilledButton(onPressed: !ready ? null : () => Navigator.of(context).pop(
          ExpenseSettlementChoice(_method!, month)), child: const Text('承認して保存')),
      ],
    );
  }
}
