import 'package:flutter/material.dart';
import 'payroll_insurance_calculation_evidence.dart';

class PayrollInsuranceEvidenceCard extends StatelessWidget {
  const PayrollInsuranceEvidenceCard({super.key, required this.detail, required this.month});
  final Map<String, dynamic> detail;
  final String month;

  @override
  Widget build(BuildContext context) {
    final evidence = PayrollInsuranceCalculationEvidence.fromDetail(detail, month: month);
    if (evidence.isEmpty) return const SizedBox.shrink();
    return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        key: const ValueKey('payroll-insurance-calculation-evidence'),
        title: const Text('保険料の計算根拠'),
        subtitle: const Text('保存済みの対象期間・料率・本人負担額'),
        children: [ConstrainedBox(constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(evidence.referenceText),
              const SizedBox(height: 6),
              Text(evidence.provenanceText, style: Theme.of(context).textTheme.bodySmall),
              const Divider(),
              for (final row in evidence.rows) Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(row.formula),
                ]),
              ),
              const Text('？ 保存された本人負担額を表示します。端数処理後の金額です。現在の設定で過去の明細を再計算しません。'),
            ]),
          ),
        )],
      ),
    );
  }
}
