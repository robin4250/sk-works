import 'package:flutter/material.dart';

import '../../international/language_controller.dart';

/// Opens the existing editor for an explicit first attachment; never saves.
class InvoiceAcceptanceNotice extends StatelessWidget {
  const InvoiceAcceptanceNotice({
    super.key,
    required this.missingCount,
    required this.singleInvoice,
    this.onReview,
  });

  final int missingCount;
  final bool singleInvoice;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    if (missingCount <= 0) return const SizedBox.shrink();
    final english = SkoLanguageController.isEnglish;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            english
                ? (singleInvoice
                    ? 'The order acceptance is not attached.'
                    : '$missingCount invoices have no order acceptance.')
                : (singleInvoice
                    ? '注文請書が未添付です。'
                    : '請求書$missingCount件に注文請書が未添付です。'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            english
                ? (singleInvoice
                    ? 'Approval or seal history prevents automatic addition. An administrator can review and attach it while preserving the original invoice.'
                    : 'Approval or seal history prevents automatic addition. Open each invoice separately to review and attach it.')
                : (singleInvoice
                    ? '承認や印影固定の履歴があるため、自動追加していません。管理者が元の請求書を保持して内容を確認できます。'
                    : '承認や印影固定の履歴があるため、自動追加していません。各請求書を個別に開いて内容を確認してください。'),
          ),
          if (singleInvoice) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.note_add_outlined),
                label: Text(english
                    ? 'Review and attach order acceptance'
                    : '注文請書を確認・添付'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

