import 'package:flutter/material.dart';
import 'expense_claim.dart';
import 'expense_settlement_choice.dart';

class ExpenseReviewDecision {
  const ExpenseReviewDecision(this.approve, this.destination, this.settlement, this.memo);
  final bool approve;
  final ExpenseAllocation? destination;
  final ExpenseSettlementChoice? settlement;
  final String memo;
}

String expenseBurdenLabel(ExpenseCategory category) => switch (category) {
  ExpenseCategory.ownCompany => '自社',
  ExpenseCategory.subcontractor => '下請け会社',
  ExpenseCategory.customer => '取引会社',
  ExpenseCategory.other => 'その他（承認のみ）',
  ExpenseCategory.unallocated => '未振り分け',
};

class ExpenseReviewFlowDialog extends StatefulWidget {
  const ExpenseReviewFlowDialog({super.key, required this.claim, required this.destinations});
  final ExpenseClaim claim;
  final List<ExpenseAllocation> destinations;
  @override
  State<ExpenseReviewFlowDialog> createState() => _ExpenseReviewFlowDialogState();
}
class _ExpenseReviewFlowDialogState extends State<ExpenseReviewFlowDialog> {
  int _step = 0;
  bool _approve = true;
  ExpenseCategory? _category;
  ExpenseAllocation? _destination;
  ExpenseSettlementMethod? _method;
  final _memo = TextEditingController();
  @override
  void dispose() { _memo.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final month = ExpenseSettlementChoice.applicationMonth(widget.claim.submittedAt);
    final ready = switch (_step) { 1 => _destination != null, 2 => _method != null, _ => true };
    final companies = widget.destinations.where((v) => v.category == _category && v.counterpartyId != null).toList();
    Widget choose(String label, bool selected, VoidCallback onTap) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      title: Text(label), onTap: onTap);
    return AlertDialog(
      title: Text(['① 承認・却下', '② 費用の負担先', '③ 精算方法', '④ メモ', '⑤ 最終確認'][_step]),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.claim.applicantName}　${widget.claim.amountYen}円'),
          Text(widget.claim.description), const SizedBox(height: 12),
          if (_step == 0) ...[
            choose('承認する（振り分けへ進む）', _approve, () => setState(() => _approve = true)),
            choose('却下する（メモへ進む）', !_approve, () => setState(() => _approve = false)),
          ],
          if (_step == 1) ...[
            for (final category in [ExpenseCategory.ownCompany, ExpenseCategory.subcontractor, ExpenseCategory.customer, ExpenseCategory.other])
              choose(expenseBurdenLabel(category), _category == category, () => setState(() {
                _category = category;
                _destination = category == ExpenseCategory.ownCompany || category == ExpenseCategory.other
                  ? ExpenseAllocation(category) : null;
              })),
            if (_category == ExpenseCategory.subcontractor || _category == ExpenseCategory.customer) ...[
              const Text('会社を選択してください'),
              if (companies.isEmpty) const Text('登録済みの会社がありません。戻って負担先を選び直してください。'),
              for (final company in companies)
                choose(company.counterpartyName ?? '登録会社', _destination?.counterpartyId == company.counterpartyId,
                  () => setState(() => _destination = company)),
            ],
          ],
          if (_step == 2) ...[
            for (final method in [ExpenseSettlementMethod.paid, ExpenseSettlementMethod.cash, ExpenseSettlementMethod.payroll, ExpenseSettlementMethod.advance])
              choose(ExpenseSettlementChoice(method, month).label, _method == method, () => setState(() => _method = method)),
            Text('精算対象月（申請月）：${month.year}年${month.month}月'),
          ],
          if (_step == 3) TextField(controller: _memo, maxLength: 1000, maxLines: 3,
            decoration: InputDecoration(labelText: _approve ? 'メモ（任意）' : '却下理由・メモ')),
          if (_step == 4) ...[
            Text(_approve ? '承認する' : '却下する'),
            if (_approve) ...[
              Text('負担先：${expenseBurdenLabel(_destination!.category)}${_destination!.counterpartyName == null ? '' : ' / ${_destination!.counterpartyName}'}'),
              Text('精算方法：${ExpenseSettlementChoice(_method!, month).label}'),
              Text('精算対象月（申請月）：${month.year}年${month.month}月'),
            ],
            Text('メモ：${_memo.text.trim().isEmpty ? 'なし' : _memo.text.trim()}'),
            const SizedBox(height: 12), const Text('「確定」を押すまで保存されません。'),
          ],
        ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        if (_step > 0) TextButton(onPressed: () => setState(() {
          _step = _step == 3 && !_approve ? 0 : _step - 1;
        }), child: const Text('戻る')),
        FilledButton(onPressed: !ready ? null : () {
          if (_step == 4) {
            Navigator.pop(context, ExpenseReviewDecision(_approve, _approve ? _destination : null,
              _approve ? ExpenseSettlementChoice(_method!, month) : null, _memo.text.trim()));
          } else { setState(() => _step = _step == 0 && !_approve ? 3 : _step + 1); }
        }, child: Text(_step == 4 ? '確定' : '次へ')),
      ],
    );
  }
}
