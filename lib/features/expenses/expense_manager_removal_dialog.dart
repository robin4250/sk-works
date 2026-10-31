import 'package:flutter/material.dart';
import 'expense_claim.dart';

class ExpenseManagerRemovalDialog extends StatefulWidget {
  const ExpenseManagerRemovalDialog({super.key,required this.claim});
  final ExpenseClaim claim;
  @override State<ExpenseManagerRemovalDialog> createState()=>_ExpenseManagerRemovalDialogState();
}
class _ExpenseManagerRemovalDialogState extends State<ExpenseManagerRemovalDialog>{
  final _reason=TextEditingController();
  @override void dispose(){_reason.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('経費を削除しますか？'),
    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${widget.claim.applicantName}／${widget.claim.amountYen}円'),Text(widget.claim.description),
      const Text('申請者に削除通知を記録します。原本・写真・変更履歴は保持します。確定済み帳票に使われている場合、一覧で削除扱いにしても帳票や給与の金額は取消されず、別途訂正が必要です。'),
      TextField(controller:_reason,maxLength:1000,minLines:2,maxLines:5,decoration:const InputDecoration(labelText:'削除理由'),onChanged:(_)=>setState((){})),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('戻る')),
      FilledButton(onPressed:_reason.text.trim().isEmpty?null:()=>Navigator.pop(context,_reason.text.trim()),child:const Text('削除を確定'))]);
}
