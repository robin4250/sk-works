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
  int? _year, _month;
  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    final first = claim.incurredOn.year > 1900 ? claim.incurredOn.year - 1 : 1900;
    final last = DateTime.now().year + 2;
    final ready = _method != null && _year != null && _month != null;
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
          for (final method in ExpenseSettlementMethod.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_method == method ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: _method == method ? Theme.of(context).colorScheme.primary : null),
              title: Text(method == ExpenseSettlementMethod.cash ? '現金精算' : '給料精算'),
              onTap: () => setState(() => _method = method),
            ),
          const SizedBox(height: 12),
          const Text('精算対象月'),
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(
              isExpanded: true, initialValue: _year,
              decoration: const InputDecoration(labelText: '年'),
              items: [for (var y = first; y <= last; y++) DropdownMenuItem(value: y, child: Text('$y年'))],
              onChanged: (value) => setState(() => _year = value),
            )),
            const SizedBox(width: 12),
            Expanded(child: DropdownButtonFormField<int>(
              isExpanded: true, initialValue: _month,
              decoration: const InputDecoration(labelText: '月'),
              items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('$m月'))],
              onChanged: (value) => setState(() => _month = value),
            )),
          ]),
          const SizedBox(height: 12),
          const Text('選択した対象月に精算予定として保存します。費用の負担先は承認後に振り分けます。'),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('戻る')),
        FilledButton(onPressed: !ready ? null : () => Navigator.of(context).pop(
          ExpenseSettlementChoice(_method!, DateTime.utc(_year!, _month!))), child: const Text('承認して保存')),
      ],
    );
  }
}
