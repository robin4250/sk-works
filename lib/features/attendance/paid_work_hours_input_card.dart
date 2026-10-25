import 'package:flutter/material.dart';

import 'paid_work_hours_repository.dart';

/// Embedded only after the parent has loaded an authoritative server scope.
/// This card never computes hours from clock differences or changes pay rates.
class PaidWorkHoursInputCard extends StatefulWidget {
  const PaidWorkHoursInputCard({super.key, required this.snapshot,
    required this.onSave, required this.onSaved, this.onReload});
  final PaidWorkHoursSnapshot snapshot;
  final Future<PaidWorkHoursSnapshot> Function(String hours) onSave;
  final ValueChanged<PaidWorkHoursSnapshot> onSaved;
  final VoidCallback? onReload;

  @override
  State<PaidWorkHoursInputCard> createState() => _PaidWorkHoursInputCardState();
}

class _PaidWorkHoursInputCardState extends State<PaidWorkHoursInputCard> {
  late final TextEditingController _hours;
  bool _saving = false;
  String? _message;

  String _initial(PaidWorkHoursSnapshot value) =>
      value.inputScopeCurrent && value.hours != null ? value.hours.toString() : '';

  @override
  void initState() {
    super.initState();
    _hours = TextEditingController(text: _initial(widget.snapshot));
  }

  @override
  void didUpdateWidget(covariant PaidWorkHoursInputCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.snapshot;
    final after = widget.snapshot;
    if (before.reportId != after.reportId || before.workerId != after.workerId ||
        before.revision != after.revision || before.scopeFingerprint != after.scopeFingerprint) {
      _hours.text = _initial(after);
      _message = null;
    }
  }

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !widget.snapshot.editable || widget.snapshot.sourceBlocked) return;
    final before = widget.snapshot;
    final text = _hours.text.trim();
    final value = double.tryParse(text);
    if (!RegExp(r'^(?:0|[1-9]\d?)(?:\.\d{1,4})?$').hasMatch(text) ||
        value == null || !value.isFinite || value > 24) {
      setState(() => _message = '0〜24時間の数値を入力してください。空欄は0時間になりません。');
      return;
    }
    setState(() { _saving = true; _message = null; });
    try {
      final saved = await widget.onSave(text);
      if (!mounted) return;
      final current = widget.snapshot;
      if (current.actorId != before.actorId || current.companyId != before.companyId ||
          current.workerId != before.workerId || current.reportId != before.reportId ||
          current.scopeFingerprint != before.scopeFingerprint || current.revision != before.revision) {
        return;
      }
      widget.onSaved(saved);
      if (mounted) setState(() => _message = saved.contractVersion == 2
          ? '実勤務時間を保存しました。日報の内容・報告者サインは変更していません。'
          : '保存しました。変更した場合は、報告者・現場責任者の署名を取り直してください。');
    } catch (_) {
      if (mounted) {
        setState(() => _message = '保存状態を確認できませんでした。再読込してから確認してください。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.snapshot;
    if (!value.hoursRequired) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('時間手当の実勤務時間', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${value.workDate.year}年${value.workDate.month}月${value.workDate.day}日・1日合計'),
          const SizedBox(height: 12),
          if (value.sourceBlocked)
            Text(value.contractVersion == 2
                ? '本人の退勤後に、休憩を除く実勤務時間を確認してください。'
                : '当日の最後の退勤に対応した日報で入力します。勤務記録を確認してください。')
          else if (!value.editable)
            Text(value.contractVersion == 2
                ? value.supervisorFinalized
                    ? '現場責任者の最終確認まで保存されています。変更する場合は承認付き訂正が必要です。'
                    : value.hours != null && value.inputScopeCurrent
                        ? '実勤務時間は保存済みです。現場責任者の最終確認を待ちます。'
                        : '対象メンバー本人の実勤務時間の確認を待っています。'
                : '署名済みです。変更する場合は、日報の訂正と再署名が必要です。'),
          if (!value.inputScopeCurrent)
            Text('勤務記録が変わりました。実勤務時間を確認し直してください。', style: TextStyle(color: color.error)),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('paid-work-hours-input'),
            controller: _hours,
            enabled: value.editable && !value.sourceBlocked && !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '休憩を除く実勤務時間', hintText: '例：7.5', suffixText: '時間',
              border: OutlineInputBorder(), isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: value.editable && !value.sourceBlocked && !_saving ? _save : null,
              child: Text(_saving ? '保存中…' : value.contractVersion == 2 ? '実勤務時間を確認して保存' : '実勤務時間を保存')),
            if (widget.onReload != null) TextButton(onPressed: _saving ? null : widget.onReload, child: const Text('再読込')),
          ]),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!)),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('？ 実勤務時間について', style: TextStyle(fontSize: 13)),
            children: [Padding(padding: EdgeInsets.only(bottom: 8), child: Text(
              '途中の現場を含め、その日全体の実勤務時間を1回入力します。休憩を除いてください。'
              '出退勤の経過時間から自動計算しません。'
              '会社で設定した時間手当の単価に、両者が署名した実勤務時間を掛けて給与へ反映します。'
              '空欄と0時間は別の状態です。',
            ))],
          ),
        ]),
      ),
    );
  }
}
