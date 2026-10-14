import 'package:flutter/material.dart';
import '../../international/language_controller.dart';

Future<bool> confirmChatGroupDeletion(BuildContext context, {
  required String name, required bool lineLinked,
}) async {
  final english = SkoLanguageController.isEnglish;
  return await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
    title: Text(english ? 'Delete this group?' : 'グループを削除しますか？'),
    content: SingleChildScrollView(child: Text(
      english
        ? 'Delete "$name" for every participant. Messages, notes, albums and related LINE monthly import drafts are also deleted. This cannot be undone.'
          '${lineLinked ? "\nThe same shared group disappears from both SKO Chat and LINE Talk. The group and history in the LINE app itself are not deleted." : ""}'
        : '「$name」を参加者全員の一覧から削除します。メッセージ・ノート・アルバム・LINE取込の月別表などの関連データも削除されます。この操作は元に戻せません。'
          '${lineLinked ? "\nSKOチャットとLINEトークで共有している同じグループが削除されます。LINE本体のグループや履歴は削除されません。" : ""}',
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext, false),
        child: Text(english ? 'Back' : '戻る')),
      FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
        child: Text(english ? 'Delete group' : 'グループを削除')),
    ],
  )) ?? false;
}
