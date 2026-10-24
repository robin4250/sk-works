import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../shared/company_allowance_label_repository.dart';
import 'daily_report_company_allowance_selection.dart';

/// Company choices update only explicit selection metadata and the existing
/// newline report text. Discovery never adopts or replaces a saved label.
class DailyReportAllowanceNameField extends StatelessWidget {
  const DailyReportAllowanceNameField({super.key, required this.controller,
    required this.enabled, this.registeredItems = const [], this.selections, this.eligibleKeys, this.needsSavedReport = false,
    this.onSelectionsChanged, this.loading = false, this.unavailable = false});

  final TextEditingController controller;
  final bool enabled;
  final Set<String>? eligibleKeys;
  final bool needsSavedReport;
  final List<CompanyAllowanceLabel> registeredItems;
  final DailyReportCompanyAllowanceSelections? selections;
  final ValueChanged<DailyReportCompanyAllowanceSelections>? onSelectionsChanged;
  final bool loading, unavailable;

  bool _validName(String name) => name.isNotEmpty && name.trim() == name &&
      !name.contains('\n') && !name.contains('\r');
  String _key(CompanyAllowanceLabel item) => item.id == null
      ? '${item.origin}/unprepared/${item.legacySlot ?? item.name}'
      : '${item.origin}/${item.id}';

  bool _matches(DailyReportCompanyAllowanceSelection saved, CompanyAllowanceLabel item) =>
    saved.key == _key(item) && saved.nameSnapshot == item.name && saved.unit == item.unit &&
    saved.generation == item.generation && saved.registrationVersion == item.registrationVersion;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    // Payroll type (employee wage basis) and allowance unit are independent.
    // Monthly allowances belong to individual payroll, never checkout choices.
    final visible = registeredItems.where((item) =>
      const ['day', 'hour'].contains(item.unit)).toList();
    final counts = <String, int>{};
    for (final item in visible) {
      counts[_key(item)] = (counts[_key(item)] ?? 0) + 1;
    }
    final rendered = <CompanyAllowanceLabel>[];
    final renderedKeys = <String>{};
    for (final item in visible) {
      if (_validName(item.name) && renderedKeys.add(_key(item))) rendered.add(item);
    }
    final unselectable = visible.any((item) => !item.selectable ||
      !_validName(item.name) || counts[_key(item)] != 1);
    final selected = selections?.items ?? const <DailyReportCompanyAllowanceSelection>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (loading) const LinearProgressIndicator(),
      if (visible.isNotEmpty) ...[
        Text(SkoLanguageController.tr('現在の会社共通手当')),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final item in rendered)
            FilterChip(key: ValueKey('company-checkout-choice-${_key(item)}'),
              label: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(item.name),
                Text('${SkoLanguageController.tr(item.unit == 'hour' ? '時間単位' : '日単位')}・${SkoLanguageController.tr(item.section == 'deduction' ? '控除' : '支給')}',
                  style: Theme.of(context).textTheme.labelSmall),
                if (item.payrollType != 'all') Text(SkoLanguageController.tr(
                  switch (item.payrollType) {
                    'hourly' => '時間単位給与', 'monthly' => '月単位給与',
                    _ => '日単位給与',
                  }), style: Theme.of(context).textTheme.labelSmall),
              ]),
              selected: selected.any((value) => _matches(value, item)),
              onSelected: enabled && item.selectable && eligibleKeys?.contains(_key(item)) == true && counts[_key(item)] == 1 &&
                  onSelectionsChanged != null ? (choose) {
                final next = DailyReportCompanyAllowanceSelections([
                  ...selected.where((value) => value.key != _key(item)),
                  if (choose) DailyReportCompanyAllowanceSelection.registered(item),
                ]);
                var raw = controller.text;
                final previous = selected.where((value) => value.key == _key(item)).firstOrNull;
                if (choose && previous != null && previous.nameSnapshot != item.name &&
                    !next.items.any((value) => value.nameSnapshot == previous.nameSnapshot)) {
                  raw = raw.split('\n').where((line) => line.trim() != previous.nameSnapshot).join('\n');
                }
                final existingLines = raw.split('\n').map((line) => line.trim()).toSet();
                final nextText = choose
                  ? existingLines.contains(item.name) ? raw
                    : raw.trim().isEmpty ? item.name : '$raw\n${item.name}'
                  : next.items.any((value) => value.nameSnapshot == item.name) ? raw
                    : raw.split('\n').where((line) => line.trim() != item.name).join('\n');
                onSelectionsChanged!(next);
                controller.value = TextEditingValue(text: nextText,
                  selection: TextSelection.collapsed(offset: nextText.length));
              } : null),
        ]),
        const SizedBox(height: 8),
        if (!needsSavedReport && eligibleKeys != null && rendered.any((item) => !eligibleKeys!.contains(_key(item))))
          Text(SkoLanguageController.tr('適用を確認できた項目だけ選択できます。保存済みの選択は明示的に解除できます。')),
      ],
      if (selected.any((saved) => visible.any((item) => saved.key == _key(item) && !_matches(saved, item))))
        Text(SkoLanguageController.tr('登録内容が更新された項目は、現在の内容を確認して選び直してください。')),
      for (final saved in selected.where((saved) =>
          !visible.any((item) => saved.key == _key(item)) ||
          eligibleKeys?.contains(saved.key) != true))
        InputChip(label: Text('${saved.nameSnapshot}（${SkoLanguageController.tr('保存済み')}）'),
          onDeleted: enabled && onSelectionsChanged != null ? () {
            final next = DailyReportCompanyAllowanceSelections(selected.where((item) => item.key != saved.key));
            var raw = controller.text;
            if (!next.items.any((item) => item.nameSnapshot == saved.nameSnapshot)) {
              raw = raw.split('\n').where((line) => line.trim() != saved.nameSnapshot).join('\n');
            }
            onSelectionsChanged!(next);
            controller.value = TextEditingValue(text: raw,
              selection: TextSelection.collapsed(offset: raw.length));
          } : null),
      if (needsSavedReport) Text(SkoLanguageController.tr('日報を保存すると、各メンバーに適用できる手当を選択できます。')),
      if (!needsSavedReport && !loading && !unavailable && visible.isNotEmpty && eligibleKeys == null)
        Text(SkoLanguageController.tr('手当の適用対象を確認できないため選択できません。再読み込みしてください。')),
      if (unselectable) Text(SkoLanguageController.tr(
        '選択できない登録項目があります。会社の登録状態を確認してください。')),
      if (unavailable) Text(SkoLanguageController.tr(
        '会社共通手当の候補を確認できません。保存済みの手当名は保持しています。')),
      if (!loading && !unavailable && visible.isEmpty)
        Text(SkoLanguageController.tr('退勤で選択する会社共通手当はありません。')),
      TextField(controller: controller, enabled: enabled, readOnly: true,
        minLines: 1, maxLines: 4,
        decoration: InputDecoration(labelText: SkoLanguageController.tr('選択した手当名'),
          helperText: SkoLanguageController.tr('会社の登録項目から選択します。保存済みの入力は保持します。'))),
    ]);
  }
}
