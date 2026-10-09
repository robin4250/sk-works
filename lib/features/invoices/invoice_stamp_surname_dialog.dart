import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'invoice_approval_repository.dart';

Future<bool> editInvoiceStampSurname(
  BuildContext context,
  InvoiceApprovalRepository repository,
  String invoiceId, {
  String? initialSurname,
}) async {
  final controller = TextEditingController(text: initialSurname ?? '');
  String? error;
  var busy = false;
  try {
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(SkoLanguageController.isEnglish
              ? 'Surname on your approval seal'
              : '承認印に表示する名字'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(SkoLanguageController.isEnglish
                  ? 'Enter your surname explicitly. Your profile name and previous approvals remain unchanged.'
                  : '名字を明示入力してください。プロフィールの氏名と過去の承認印は変更しません。'),
              TextField(
                controller: controller,
                maxLength: 30,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: SkoLanguageController.isEnglish ? 'Surname' : '名字',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext, false),
              child: Text(SkoLanguageController.isEnglish ? 'Cancel' : '取消'),
            ),
            FilledButton(
              onPressed: busy ? null : () async {
                setDialogState(() { busy = true; error = null; });
                try {
                  await repository.setStampSurname(invoiceId, controller.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (_) {
                  if (dialogContext.mounted) {
                    setDialogState(() {
                      busy = false;
                      error = SkoLanguageController.isEnglish
                          ? 'Could not save. Check the surname, pending approval and server availability.'
                          : '保存できません。名字・承認待ち状態・サーバー準備状況を確認してください。';
                    });
                  }
                }
              },
              child: Text(SkoLanguageController.isEnglish ? 'Save' : '保存'),
            ),
          ],
        ),
      ),
    ) ?? false;
  } finally {
    controller.dispose();
  }
}
