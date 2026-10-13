import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'expense_claim.dart';
import 'expense_submission_repository.dart';

class ExpenseEditDialog extends StatefulWidget {
  const ExpenseEditDialog({
    super.key,
    required this.claim,
    required this.actor,
  });
  final ExpenseClaim claim;
  final String actor;
  @override
  State<ExpenseEditDialog> createState() => _ExpenseEditDialogState();
}

class _ExpenseEditDialogState extends State<ExpenseEditDialog> {
  late final _description = TextEditingController(
    text: widget.claim.description,
  );
  late final _amount = TextEditingController(text: '${widget.claim.amountYen}');
  late DateTime _date = widget.claim.incurredOn;
  String? _error;
  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('経費申請を編集'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('保存すると承認待ちに戻ります。承認済みの振り分けは解除され、再承認が必要です。確定済み帳票は変更されません。'),
          OutlinedButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (mounted && date != null) setState(() => _date = date);
            },
            child: Text('利用日 ${_date.year}/${_date.month}/${_date.day}'),
          ),
          TextField(
            controller: _description,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '内容'),
          ),
          const Text('いつ・どこで・何のために・何を購入／利用したかを具体的に記入してください。'),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '金額（円）'),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final draft = ExpenseSubmission.create(
              widget.actor,
              widget.claim.companyId,
              widget.claim.applicantId,
              _date,
              _description.text,
              _amount.text,
            );
            Navigator.pop(context, draft);
          } catch (_) {
            setState(() => _error = '内容と金額（1円以上の整数）を確認してください。');
          }
        },
        child: const Text('変更して再申請'),
      ),
    ],
  );
}
