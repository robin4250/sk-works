import 'package:flutter/material.dart';

import '../daily_reports/daily_report_allowance_name_field.dart';
import '../daily_reports/daily_report_company_allowance_selection.dart';
import '../shared/company_allowance_label_repository.dart';
import 'attendance_management_company_allowances.dart';
import 'attendance_management_repository.dart';

class AttendanceManagementCompanyAllowanceField extends StatefulWidget {
  const AttendanceManagementCompanyAllowanceField({super.key,
    required this.repository, required this.workerIds, required this.controller,
    required this.selections, required this.onChanged, required this.enabled, required this.onReady,
  });
  final AttendanceManagementRepository repository;
  final List<String> workerIds;
  final TextEditingController controller;
  final DailyReportCompanyAllowanceSelections? selections;
  final ValueChanged<DailyReportCompanyAllowanceSelections> onChanged;
  final bool enabled;
  final ValueChanged<bool> onReady;

  @override
  State<AttendanceManagementCompanyAllowanceField> createState() => _AllowanceFieldState();
}

class _AllowanceFieldState extends State<AttendanceManagementCompanyAllowanceField> {
  AttendanceManagementAllowanceOptions? _options;
  bool _loading = true, _unavailable = false;
  int _generation = 0;
  String _key(List<String> ids) => (ids.toSet().toList()..sort()).join('|');

  @override
  void initState() { super.initState(); _load(); }

  @override
  void didUpdateWidget(covariant AttendanceManagementCompanyAllowanceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository || _key(oldWidget.workerIds) != _key(widget.workerIds)) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    widget.onReady(false);
    final ids = List<String>.of(widget.workerIds);
    final key = _key(ids);
    setState(() { _options = null; _loading = ids.isNotEmpty; _unavailable = false; });
    if (ids.isEmpty) return;
    try {
      final options = await widget.repository.loadCompanyAllowanceOptions(ids);
      if (mounted && generation == _generation && key == _key(widget.workerIds)) {
        setState(() { _options = options; _loading = false; });
        widget.onReady(true);
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() { _unavailable = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.workerIds.isEmpty) return const Text('従業員を選ぶと、登録済みの共通手当を表示します。');
    final options = _options;
    final monthly = options?.labels.items.where((item) => item.unit == 'month').toList() ?? const <CompanyAllowanceLabel>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DailyReportAllowanceNameField(
        controller: widget.controller, enabled: widget.enabled && options != null,
        registeredItems: options?.labels.items ?? const [], selections: widget.selections,
        eligibleKeys: options?.sharedEligibleKeys, loading: _loading, unavailable: _unavailable,
        onSelectionsChanged: options == null ? null : widget.onChanged,
      ),
      if (_unavailable) Align(alignment: Alignment.centerLeft,
        child: TextButton(onPressed: widget.enabled ? _load : null, child: const Text('共通手当を再読み込み'))),
      if (widget.workerIds.length > 1)
        const Text('全員に適用できる共通手当だけ選択できます。選択を変更した場合、対象の勤務をその選択内容に置き換えます。'),
      if (monthly.isNotEmpty) ExpansionTile(title: const Text('月単位の共通手当'),
        subtitle: const Text('個別給与設定で適用するため、勤務日ごとには選択しません。'),
        children: [for (final item in monthly) ListTile(title: Text(item.name))]),
    ]);
  }
}
