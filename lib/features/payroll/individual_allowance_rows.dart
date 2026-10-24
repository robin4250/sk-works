import 'dart:convert';

import 'payroll_unit_item_editor.dart';

/// UI-only IDs retain the original worker setting slot. They are never sent to
/// the unit-condition API or converted into a second payable item.
const individualAllowanceSlotPrefix = 'worker-allowance-slot-';

int? individualAllowanceSlot(String id) {
  final match = RegExp(r'^worker-allowance-slot-([123])$').firstMatch(id);
  return match == null ? null : int.parse(match.group(1)!);
}

List<PayrollUnitItemDraft> individualAllowanceRows(Map<String, dynamic> values) => [
  for (var slot = 1; slot <= 3; slot++)
    if ((values['allowance_name_$slot']?.toString().trim() ?? '').isNotEmpty ||
        (num.tryParse(values['allowance_$slot']?.toString() ?? '') ?? 0) != 0)
      PayrollUnitItemDraft(id: '$individualAllowanceSlotPrefix$slot',
        section: PayrollItemSection.earning, unit: PayrollItemUnit.day,
        name: values['allowance_name_$slot']?.toString() ?? '',
        rate: values['allowance_$slot']?.toString() ?? '0',
        source: 'selected_allowance_days'),
];

class IndividualAllowanceRows {
  const IndividualAllowanceRows(this.workerValues, this.unitItems);
  final Map<String, dynamic> workerValues;
  final List<PayrollUnitItemDraft> unitItems;
}

IndividualAllowanceRows splitIndividualAllowanceRows(List<PayrollUnitItemDraft> items) {
  final values = <String, dynamic>{
    for (var slot = 1; slot <= 3; slot++) ...{
      'allowance_name_$slot': '', 'allowance_$slot': 0,
    },
  };
  final seen = <int>{};
  final unit = <PayrollUnitItemDraft>[];
  for (final item in items) {
    final slot = individualAllowanceSlot(item.id);
    if (slot == null) {
      if (item.id.startsWith(individualAllowanceSlotPrefix)) {
        throw const FormatException('手当の保存先を確認できません');
      }
      unit.add(item);
      continue;
    }
    final amount = int.tryParse(item.rate.trim());
    if (!seen.add(slot) || item.section != PayrollItemSection.earning ||
        item.unit != PayrollItemUnit.day || item.name.trim().isEmpty ||
        item.name.trim().length > 100 || amount == null || amount < 0 ||
        amount > 2147483647) {
      throw const FormatException('手当の名称と金額を確認してください');
    }
    values['allowance_name_$slot'] = item.name.trim();
    values['allowance_$slot'] = amount;
  }
  return IndividualAllowanceRows(Map.unmodifiable(values), List.unmodifiable(unit));
}


bool samePayrollUnitItems(List<PayrollUnitItemDraft> a, List<PayrollUnitItemDraft> b) {
  List<String> values(List<PayrollUnitItemDraft> items) => items.map((item) => jsonEncode([
    item.id, item.section.name, item.unit.name, item.name.trim(),
    int.tryParse(item.rate.trim()), item.source, item.quantity.trim(),
  ])).toList()..sort();
  return jsonEncode(values(a)) == jsonEncode(values(b));
}
