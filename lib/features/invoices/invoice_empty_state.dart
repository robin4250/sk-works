import 'package:flutter/material.dart';
import '../../international/language_controller.dart';

/// Saved invoices can change while the user completes reports or approvals.
/// Reload reads the existing list; it never creates attendance or quantities.
class InvoiceEmptyState extends StatelessWidget {
  const InvoiceEmptyState({
    super.key,
    required this.onReload,
    required this.showGenerationGuidance,
  });
  final Future<void> Function() onReload;
  final bool showGenerationGuidance;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          SkoLanguageController.isEnglish
              ? 'No invoices for this period.'
              : 'この期間の請求書はありません',
          style: const TextStyle(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          SkoLanguageController.isEnglish
              ? 'Complete the report or approval, then reload this list.'
              : '日報の登録や承認後は、一覧を再読み込みしてください。',
          textAlign: TextAlign.center,
        ),
        if (showGenerationGuidance) ...[
          const SizedBox(height: 12),
          Text(
            SkoLanguageController.isEnglish
                ? 'For ordinary work, check the saved and signed daily report and its customer. For route work, submit the customer billing quantity and have its quantity and unit price approved. Clock-in or clock-out alone does not complete these steps.'
                : '通常勤務は、日報の保存・サインと現場の取引会社を確認してください。ルート勤務は、取引会社ごとの請求数量を申請し、数量・単価の承認を確認してください。出勤・退勤の確定だけでは、これらの手続きは完了しません。',
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onReload,
          icon: const Icon(Icons.refresh),
          label: Text(SkoLanguageController.isEnglish ? 'Reload List' : '一覧を再読み込み'),
        ),
      ]),
    ),
  );
}
