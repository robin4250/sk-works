import 'package:flutter/material.dart';

/// Persisted options must come from the current company; no default is assigned
/// to existing workers until an administrator explicitly chooses one.
class EmployeeCategoryOption {
  const EmployeeCategoryOption({required this.id, required this.name, this.active = true});
  final String id;
  final String name;
  final bool active;
}

/// Selection is local until the owning personnel save flow succeeds.
class EmployeeCategorySelector extends StatelessWidget {
  const EmployeeCategorySelector({super.key, required this.options,
    required this.selectedId, required this.onChanged, this.onAdd});
  final List<EmployeeCategoryOption> options;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final visible = options.where((o) => o.active || o.id == selectedId).toList();
    final matches = visible.where((o) => o.id == selectedId).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        initialValue: matches == 1 ? selectedId : null,
        decoration: const InputDecoration(labelText: '従業員区分'),
        hint: Text(selectedId != null && matches != 1 ? '区分を確認できません' : '未設定'),
        items: [const DropdownMenuItem<String>(value: null, child: Text('未設定')),
          for (final option in visible)
          DropdownMenuItem(value: option.id,
            child: Text(option.active ? option.name : '${option.name}（使用停止）'))],
        onChanged: onChanged,
      ),
      if (onAdd != null) TextButton.icon(
        onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('区分を追加')),
    ]);
  }
}
