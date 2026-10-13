import 'package:flutter/material.dart';

import '../../international/language_controller.dart';

List<String> payrollConditionWarnings(Map<String, dynamic> detail) {
  final raw = detail['calculation_warnings'];
  if (raw is! List) return const [];
  return raw
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
}


/// Translate only server-owned warning templates, preserving any employee-name prefix.
String localizedPayrollConditionWarning(String warning) {
  final patterns = <(RegExp, String, String)>[
    (RegExp(r'有給([0-9]+)日：有給単価が0円です。個別給与設定の有給額を確認してください。$'),
      '有給{count}日：有給単価が0円です。個別給与設定の有給額を確認してください。', 'count'),
    (RegExp(r'有給([0-9]+)日：日給・時給の有給支給額は現在の自動計算に含まれていません。会社の有給給与条件と支給額を確認してください。$'),
      '有給{count}日：日給・時給の有給支給額は現在の自動計算に含まれていません。会社の有給給与条件と支給額を確認してください。', 'count'),
    (RegExp(r'通常勤務に夜間([0-9]+(?:\.[0-9]+)?)時間が登録されています。夜間時間だけの割増は現在の自動計算に含まれません。勤務区分と会社の夜間給与条件を確認してください。$'),
      '通常勤務に夜間{hours}時間が登録されています。夜間時間だけの割増は現在の自動計算に含まれません。勤務区分と会社の夜間給与条件を確認してください。', 'hours'),
    (RegExp(r'月給の((?:夜勤|休日勤務|休日夜勤)(?:・(?:夜勤|休日勤務|休日夜勤))*)実績に未登録の単価があります。会社の追加支給条件と給与設定を確認してください。$'),
      '月給の{categories}実績に未登録の単価があります。会社の追加支給条件と給与設定を確認してください。', 'categories'),
  ];
  for (final pattern in patterns) {
    final match = pattern.$1.firstMatch(warning);
    if (match == null) continue;
    var value = match.group(1)!;
    if (pattern.$3 == 'categories') {
      value = value.split('・').map(SkoLanguageController.tr).join(' / ');
      if (!SkoLanguageController.isEnglish) value = match.group(1)!;
    }
    return warning.substring(0, match.start) +
        SkoLanguageController.trParams(pattern.$2, {pattern.$3: value});
  }
  return warning;
}

class PayrollConditionWarning extends StatelessWidget {
  const PayrollConditionWarning({super.key, required this.warnings});
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade700),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(SkoLanguageController.tr('給与条件の確認が必要です'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final warning in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(localizedPayrollConditionWarning(warning)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmPayrollConditions(BuildContext context, List<String> warnings) async {
  if (warnings.isEmpty) return true;
  return await showDialog<bool>(
    context: context,
    builder: (context) {
      SkoLanguageController.watch(context);
      return AlertDialog(
      title: Text(SkoLanguageController.tr('給与条件を確認してください')),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in warnings) Padding(
            padding: const EdgeInsets.only(bottom: 12), child: Text(localizedPayrollConditionWarning(warning)),
          ),
          Text(SkoLanguageController.tr('支給額と会社の給与条件を確認してから、確認を登録してください。')),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(SkoLanguageController.tr('戻って確認'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(SkoLanguageController.tr('条件と金額を確認して続行'))),
      ],
      );
    },
  ) ?? false;
}
