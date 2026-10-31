import 'package:flutter/material.dart';
import '../../international/language_controller.dart';
import 'home_attention_repository.dart';

/// Unknown evidence is distinct from a confirmed pending obligation or success.
class RequiredDocumentEvidenceNotice extends StatelessWidget {
  const RequiredDocumentEvidenceNotice({super.key, required this.attention, required this.onOpen});
  final RequiredDocumentAttention attention;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (!attention.hasUnknownDocumentEvidence) { return const SizedBox.shrink(); }
    return Card(child: ListTile(
      leading: const Icon(Icons.help_outline),
      title: Text(SkoLanguageController.tr('書類の確認状況')),
      subtitle: Text(SkoLanguageController.tr(attention.documentEvidenceUnavailable
          ? '状態を確認できません。再読み込みしてください。'
          : '添付・登録情報の確認が必要です。')),
      trailing: attention.documentEvidenceUnavailable ? null : Text(
        '${SkoLanguageController.tr('未確定')} ${attention.unknownDocumentNames.length}'),
      onTap: onOpen,
    ));
  }
}
