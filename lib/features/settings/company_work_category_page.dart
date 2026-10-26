import 'package:flutter/material.dart';
import 'company_work_category_policy.dart';
import 'company_work_category_repository.dart';

class CompanyWorkCategoryPage extends StatefulWidget {
  const CompanyWorkCategoryPage({super.key, required this.companyId});
  final String companyId;
  @override State<CompanyWorkCategoryPage> createState() => _CompanyWorkCategoryPageState();
}
class _CompanyWorkCategoryPageState extends State<CompanyWorkCategoryPage> {
  CompanyWorkCategorySnapshot? _snapshot;
  CompanyWorkCategoryRepository? _repository;
  CompanyWorkCategoryPolicy _value = CompanyWorkCategoryPolicy.editingSeed;
  final _holidays = TextEditingController(), _working = TextEditingController();
  bool _busy = true;
  String? _error, _result;
  @override void initState() { super.initState(); _repository = CompanyWorkCategoryRepository.maybeCreate(); _load(); }
  @override void dispose() { _holidays.dispose(); _working.dispose(); super.dispose(); }
  Future<void> _load() async {
    setState(() { _busy = true; _error = null; _result = null; });
    try {
      if (_repository == null) throw StateError('ログイン状態を確認してください。');
      final snapshot = await _repository!.load(widget.companyId);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot; _value = snapshot.policy ?? CompanyWorkCategoryPolicy.editingSeed;
        _holidays.text = (_value.holidayDates.toList()..sort()).join(', ');
        _working.text = (_value.workingDates.toList()..sort()).join(', ');
      });
    } on Object catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  CompanyWorkCategoryPolicy _copy({int? start, int? end, Set<int>? days, bool? national}) => CompanyWorkCategoryPolicy(
    nightStartMinute: start ?? _value.nightStartMinute, nightEndMinute: end ?? _value.nightEndMinute,
    holidayWeekdays: days ?? _value.holidayWeekdays, holidayDates: _value.holidayDates,
    workingDates: _value.workingDates, includeJapaneseHolidays: national ?? _value.includeJapaneseHolidays);
  Future<void> _time(bool start) async {
    final minute = start ? _value.nightStartMinute : _value.nightEndMinute;
    final value = await showTimePicker(context: context, initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60));
    if (!mounted || value == null || _busy) return;
    setState(() { _value = start ? _copy(start: value.hour * 60 + value.minute) : _copy(end: value.hour * 60 + value.minute); _result = null; });
  }
  String _timeText(int minute) => '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  Set<String> _dates(String input) {
    final values = input.split(RegExp(r'[,、\s]+')).where((v) => v.isNotEmpty).toList();
    if (values.toSet().length != values.length || values.any((v) => !CompanyWorkCategoryPolicy.validDateKey(v))) {
      throw const FormatException('日付は重複させず、2026-10-26 の形式で入力してください。');
    }
    return values.toSet();
  }
  Future<void> _save() async {
    final before = _snapshot;
    if (_busy || before == null || !before.canManage) return;
    setState(() { _busy = true; _error = null; _result = null; });
    try {
      final value = CompanyWorkCategoryPolicy.parse(CompanyWorkCategoryPolicy(
        nightStartMinute: _value.nightStartMinute, nightEndMinute: _value.nightEndMinute,
        holidayWeekdays: _value.holidayWeekdays, holidayDates: _dates(_holidays.text),
        workingDates: _dates(_working.text), includeJapaneseHolidays: _value.includeJapaneseHolidays).toJson());
      final saved = await _repository!.save(before, value);
      if (mounted) setState(() { _snapshot = saved; _value = saved.policy!; _result = '勤務区分の設定を保存しました。新しく入力する日報の候補に使います。'; });
    } on Object catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) {
    final editable = !_busy && (_snapshot?.canManage ?? false);
    return Scaffold(appBar: AppBar(title: const Text('勤務区分の自動入力')), body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_snapshot == null) ...[
          if (_error != null) Text(_error!),
          OutlinedButton(onPressed: _busy ? null : _load, child: const Text('再読込')),
        ] else ...[
          Text(_snapshot!.policy == null ? '未設定です。下の候補は、保存するまで日報に適用されません。' : '登録済みの会社設定です。日報では候補を必要に応じて修正できます。'),
          const SizedBox(height: 16),
          Text('① 夜勤として入力する出勤時刻', style: Theme.of(context).textTheme.titleMedium),
          Row(children: [Expanded(child: OutlinedButton(onPressed: editable ? () => _time(true) : null,
            child: Text('開始 ${_timeText(_value.nightStartMinute)}'))), const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: editable ? () => _time(false) : null,
              child: Text('終了 ${_timeText(_value.nightEndMinute)}')))]),
          const Text('日本時間の出勤時刻で判定します。開始を含み、終了は含みません。'),
          const SizedBox(height: 20),
          Text('② 会社の休日', style: Theme.of(context).textTheme.titleMedium),
          Wrap(spacing: 6, children: [for (var day = 1; day <= 7; day++) FilterChip(
            label: Text(const ['月', '火', '水', '木', '金', '土', '日'][day - 1]), selected: _value.holidayWeekdays.contains(day),
            onSelected: editable ? (selected) => setState(() { final days = {..._value.holidayWeekdays}; selected ? days.add(day) : days.remove(day); _value = _copy(days: days); _result = null; }) : null)]),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('日本の祝日も休日にする'),
            value: _value.includeJapaneseHolidays, onChanged: editable ? (v) => setState(() { _value = _copy(national: v); _result = null; }) : null),
          TextField(controller: _holidays, enabled: editable, maxLines: 2,
            onChanged: (_) => setState(() => _result = null),
            decoration: const InputDecoration(labelText: '追加の休日', hintText: '2026-12-29, 2026-12-30')),
          const SizedBox(height: 12),
          TextField(controller: _working, enabled: editable, maxLines: 2,
            onChanged: (_) => setState(() => _result = null),
            decoration: const InputDecoration(labelText: '通常勤務日として扱う例外日', hintText: '2026-11-01')),
          const SizedBox(height: 12),
          const ExpansionTile(title: Text('判定について'), children: [Padding(padding: EdgeInsets.all(12),
            child: Text('休日は保存された勤務日で判定します。例外日は曜日・祝日より優先します。同じ日を追加休日と例外日の両方には登録できません。既存の日報・サイン・確定給与・請求書をこの設定で変更しません。'))]),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_result != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_result!)),
          FilledButton.icon(onPressed: editable ? _save : null, icon: const Icon(Icons.save_outlined), label: const Text('設定を保存')),
          if (!(_snapshot?.canManage ?? false)) const Text('管理者のみ変更できます。'),
        ],
      ])));
  }
}
