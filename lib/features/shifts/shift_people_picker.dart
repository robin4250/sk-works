import 'package:flutter/material.dart';

/// Selection only: the caller must load authorized company members and persist
/// their visibility choices after verifying authorization on the server.
class ShiftPersonOption {
  const ShiftPersonOption({required this.id, required this.name});
  final String id;
  final String name;
}

class ShiftPeoplePicker extends StatelessWidget {
  const ShiftPeoplePicker({super.key, required this.people,
    required this.selectedIds, required this.onChanged});
  final List<ShiftPersonOption> people;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final available = people.map((person) => person.id).toSet();
    final selected = selectedIds.intersection(available);
    final allSelected = available.isNotEmpty && selected.length == available.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CheckboxListTile(
        title: const Text('すべて選択'),
        value: allSelected,
        onChanged: available.isEmpty ? null : (value) {
          onChanged(value == true ? Set.unmodifiable(available) : const <String>{});
        },
      ),
      for (final person in people)
        CheckboxListTile(
          key: ValueKey('shift-person-${person.id}'),
          title: Text(person.name),
          value: selected.contains(person.id),
          onChanged: (value) {
            final next = Set<String>.of(selected);
            if (value == true) {
              next.add(person.id);
            } else {
              next.remove(person.id);
            }
            onChanged(Set.unmodifiable(next));
          },
        ),
    ]);
  }
}
