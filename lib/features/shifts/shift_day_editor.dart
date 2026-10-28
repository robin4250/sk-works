import 'package:flutter/material.dart';

/// Editable values only; saving and authorization belong to the caller.
class ShiftDayDraft {
  const ShiftDayDraft({required this.holiday, required this.night,
    required this.siteId, required this.start, required this.end,
    required this.checkLate, required this.checkEarly});
  final bool holiday, night, checkLate, checkEarly;
  final String? siteId;
  final TimeOfDay start, end;

  ShiftDayDraft copyWith({bool? holiday, bool? night, String? siteId,
    TimeOfDay? start, TimeOfDay? end, bool? checkLate, bool? checkEarly}) =>
      ShiftDayDraft(holiday: holiday ?? this.holiday, night: night ?? this.night,
        siteId: siteId ?? this.siteId, start: start ?? this.start, end: end ?? this.end,
        checkLate: checkLate ?? this.checkLate, checkEarly: checkEarly ?? this.checkEarly);
}

class ShiftSiteOption {
  const ShiftSiteOption({required this.id, required this.name});
  final String id, name;
}

class ShiftDayEditor extends StatelessWidget {
  const ShiftDayEditor({super.key, required this.value, required this.sites,
    required this.onChanged});
  final ShiftDayDraft value;
  final List<ShiftSiteOption> sites;
  final ValueChanged<ShiftDayDraft> onChanged;

  Future<void> _pickTime(BuildContext context, bool start) async {
    final chosen = await showTimePicker(context: context,
      initialTime: start ? value.start : value.end);
    if (chosen != null) {
      onChanged(start ? value.copyWith(start: chosen) : value.copyWith(end: chosen));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSite = sites.any((s) => s.id == value.siteId) ? value.siteId : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CheckboxListTile(title: const Text('休日'), value: value.holiday,
        onChanged: (v) => onChanged(value.copyWith(holiday: v ?? false))),
      if (!value.holiday) ...[
        CheckboxListTile(title: const Text('夜勤'), value: value.night,
          onChanged: (v) => onChanged(value.copyWith(night: v ?? false))),
        DropdownButtonFormField<String>(
          initialValue: currentSite,
          decoration: const InputDecoration(labelText: '出勤先'),
          items: [for (final site in sites)
            DropdownMenuItem(value: site.id, child: Text(site.name))],
          onChanged: (id) { if (id != null) onChanged(value.copyWith(siteId: id)); },
        ),
        ListTile(title: const Text('出勤時間'), trailing: Text(value.start.format(context)),
          onTap: () => _pickTime(context, true)),
        ListTile(title: const Text('退勤時間'), trailing: Text(value.end.format(context)),
          onTap: () => _pickTime(context, false)),
        const Text('退勤時刻が出勤時刻より前の場合は翌日として扱います。'),
        CheckboxListTile(title: const Text('遅刻を確認'), value: value.checkLate,
          onChanged: (v) => onChanged(value.copyWith(checkLate: v ?? false))),
        CheckboxListTile(title: const Text('早退を確認'), value: value.checkEarly,
          onChanged: (v) => onChanged(value.copyWith(checkEarly: v ?? false))),
      ],
    ]);
  }
}
