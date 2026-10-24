import 'package:flutter/material.dart';
import '../../international/language_controller.dart';
import 'payroll_unit_item_editor.dart';
import 'company_common_calculation_resolution.dart';

/// Current company registration names, independent of a worker's payroll history.
/// This deliberately does not infer a current price or effective payroll amount.
class PayrollCompanyRegisteredNamesCard extends StatelessWidget {
  const PayrollCompanyRegisteredNamesCard({super.key, required this.items,
    this.loaded = true, this.unavailable = false, this.unit, this.onOpenSettings});
  final List<PayrollRegisteredAllowanceName> items;
  final bool loaded, unavailable;
  final PayrollItemUnit? unit;
  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    String tr(String value) => SkoLanguageController.tr(value);
    return Card(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: Text(tr('現在の会社共通手当')),
        trailing: onOpenSettings == null ? null : TextButton.icon(
          key: const ValueKey('open-company-common-settings'),
          onPressed: onOpenSettings, icon: const Icon(Icons.settings_outlined),
          label: Text(tr('共通設定'))),
        subtitle: Text(tr(unavailable
            ? '会社共通の登録名を確認できません。'
            : !loaded ? '会社共通の登録名を確認しています。'
            : items.isEmpty ? 'この区分の会社共通手当は未登録です。'
            : '会社に登録された共通の項目です。給与への適用状況は別に確認できます。'))),
      if (loaded && !unavailable && unit == PayrollItemUnit.hour)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(tr('退勤の実勤務時間との連動は準備中です。登録名の表示だけでは給与へ反映されません。'))),
      for (final item in loaded && !unavailable ? items : <PayrollRegisteredAllowanceName>[])
        ListTile(key: ValueKey('current-company-registered-${item.key}'),
          dense: true, leading: const Icon(Icons.business_outlined),
          title: Text(item.name)),
    ]));
  }
}

/// Common rates remain owned by the company; this form edits monthly hours only.
class PayrollCompanyCommonCard extends StatefulWidget {
  const PayrollCompanyCommonCard({
    super.key, required this.items, required this.canEdit,
    required this.onSave, required this.onReload, this.section, this.unit, this.frozen = false,
    this.resolution,
    this.title,
    this.message,
  });
  final List<Map<String, dynamic>> items;
  final bool canEdit;
  final bool frozen;
  final CompanyCommonCalculationResolution? resolution;
  final String? title;
  final String? message;
  final PayrollItemSection? section;
  final PayrollItemUnit? unit;
  final Future<void> Function(Map<String, String>) onSave;
  final VoidCallback onReload;
  @override
  State<PayrollCompanyCommonCard> createState() => _PayrollCompanyCommonCardState();
}

class _PayrollCompanyCommonCardState extends State<PayrollCompanyCommonCard> {
  final _hours = <String, TextEditingController>{};
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final item in widget.items.where((x) => x['unit'] == 'hour')) {
      _hours[item['id'] as String] = TextEditingController(text: item['quantity']?.toString() ?? '');
    }
  }
  @override
  void dispose() {
    for (final controller in _hours.values) { controller.dispose(); }
    super.dispose();
  }
  Future<void> _save(List<Map<String, dynamic>> items) async {
    if (_saving || !widget.canEdit) return;
    final values = <String, String>{};
    for (final item in items.where((x) => x['unit'] == 'hour')) {
      final id = item['id'] as String;
      final text = _hours[id]!.text.trim();
      if (!RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(text) || num.parse(text) > 99999999) {
        setState(() => _error = '時間数を0以上の数値で入力してください');
        return;
      }
      values[id] = text;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(values);
    } catch (_) {
      if (mounted) setState(() => _error = '保存できませんでした。設定を再読み込みして確認してください。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    String tr(String value) => SkoLanguageController.tr(value);
    String quantityUnit(Map<String, dynamic> item) {
      if (item['source_origin'] == 'company_legacy' &&
          item['source_unit'] is String && (item['source_unit'] as String).isNotEmpty) {
        final source = item['source_unit'] as String;
        return switch (source) {
          'day' => tr('日'), 'hour' => tr('時間'), 'month' => tr('月'), _ => source,
        };
      }
      return tr(item['unit'] == 'day' ? '日' : '月');
    }
    final items = widget.items.where((x) =>
      (widget.section == null || x['section'] == widget.section!.name) &&
      (widget.unit == null || x['unit'] == widget.unit!.name)).toList();
    if (items.isEmpty && widget.resolution?.blocked != true) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: Text(tr(widget.title ?? '社内共通手当')),
        subtitle: Text(tr(widget.resolution?.blocked == true
            ? '共通手当の設定を確認してください'
            : widget.frozen ? '保存済み給与の共通手当' : 'この月の給与計算に使う条件')),
        children: [ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.message != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(tr(widget.message!))),
          if (items.any((item) => item['source_origin'] == 'company_legacy'))
            Padding(padding: const EdgeInsets.all(12),
              child: Text(tr('日報で選んだ日数を反映しています。同じ日は1回、未選択の日は0回です。'))),
          if (widget.resolution?.blocked == true) ...[
            Padding(padding: const EdgeInsets.all(12),
              child: Text(tr('共通手当の計算を保留しています。設定を確認して再計算してください。'),
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ExpansionTile(
              key: const ValueKey('common-resolution-reasons'),
              title: Text(tr('確認が必要な理由')),
              children: [for (final reason in widget.resolution!.reasons)
                ListTile(dense: true,
                  title: Text(CompanyCommonCalculationResolution.reasonLabel(reason, translate: tr))),
              ],
            ),
          ],
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(children: [
                Expanded(child: Text('${item['name']}  ¥${item['rate_yen']}')),
                if (item['unit'] == 'hour')
                  SizedBox(width: 120, child: TextField(
                    key: ValueKey('common-hour-${item['id']}'),
                    controller: _hours[item['id']],
                    enabled: widget.canEdit && !_saving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('対象月の時間数')),
                  ))
                else
                  Text('${item['quantity'] ?? '—'} × ${quantityUnit(item)}'),
              ]),
            ),
          if (_error != null) ...[
            Text(tr(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            TextButton(onPressed: _saving ? null : widget.onReload, child: Text(tr('再読み込み'))),
          ],
          if (widget.canEdit && items.any((x) => x['unit'] == 'hour'))
            TextButton(
              key: const ValueKey('common-hours-save'),
              onPressed: _saving ? null : () => _save(items),
              child: Text(tr(_saving ? '保存中' : '時間数を保存して再計算')),
            ),
        ])),
        )],
      ),
    );
  }
}
