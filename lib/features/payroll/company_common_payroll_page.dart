import 'package:flutter/material.dart';

import 'payroll_unit_item_editor.dart';

enum CompanyPayrollType { daily, hourly, monthly }

/// Editing surface only. The payroll owner supplies the authoritative snapshot
/// and save callback after its server contract and individual reflection exist.
class CompanyCommonPayrollPage extends StatefulWidget {
  const CompanyCommonPayrollPage({
    super.key,
    this.initialItems = const {},
    this.canEdit = false,
    this.onRegister,
  });

  final Map<CompanyPayrollType, List<PayrollUnitItemDraft>> initialItems;
  final bool canEdit;
  final Future<void> Function(
    CompanyPayrollType type,
    List<PayrollUnitItemDraft> items,
  )?
  onRegister;

  @override
  State<CompanyCommonPayrollPage> createState() =>
      _CompanyCommonPayrollPageState();
}

class _CompanyCommonPayrollPageState extends State<CompanyCommonPayrollPage> {
  var _type = CompanyPayrollType.daily;
  var _section = PayrollItemSection.earning;
  var _unit = PayrollItemUnit.month;
  var _saving = false;

  static const _labels = {
    CompanyPayrollType.daily: '日給',
    CompanyPayrollType.hourly: '時給',
    CompanyPayrollType.monthly: '月給',
  };

  Widget _choice(String label, bool selected, VoidCallback onPressed) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: OutlinedButton(
            onPressed: _saving ? null : onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              backgroundColor: selected
                  ? Theme.of(context).colorScheme.primary
                  : null,
              foregroundColor: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : null,
            ),
            child: FittedBox(child: Text(label)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('社内共通手当'),
      actions: [
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: '使い方',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('社内共通手当'),
              content: const Text(
                '日給・時給・月給ごとに共通支給と共通控除を分けます。給与形態と、手当の時間・日・月単位は別の設定です。保存と個別給料設定への反映は、給与側の接続が有効な場合だけ利用できます。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 12, 9, 4),
            child: Row(
              children: [
                for (final type in CompanyPayrollType.values)
                  _choice(
                    _labels[type]!,
                    _type == type,
                    () => setState(() => _type = type),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: [
                for (final section in PayrollItemSection.values)
                  _choice(
                    section == PayrollItemSection.earning ? '支給' : '控除',
                    _section == section,
                    () => setState(() => _section = section),
                  ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _section == PayrollItemSection.earning ? '共通支給' : '共通控除',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (widget.onRegister == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('保存・個別給料設定への反映は接続準備中です。現在の給与設定は変更されません。'),
            ),
          Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                for (final unit in PayrollItemUnit.values)
                  _choice(
                    switch (unit) {
                      PayrollItemUnit.hour => '時間単位',
                      PayrollItemUnit.day => '日単位',
                      PayrollItemUnit.month => '月単位',
                    },
                    _unit == unit,
                    () => setState(() => _unit = unit),
                  ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _type.index,
              children: [
                for (final type in CompanyPayrollType.values)
                  PayrollUnitItemEditor(
                    key: ValueKey('company-common-${type.name}'),
                    initialItems: widget.initialItems[type] ?? const [],
                    canEdit: widget.canEdit && widget.onRegister != null,
                    section: _section,
                    unit: _unit,
                    showDailyReportOption: false,
                    onValidationSelection: (section, unit) => setState(() {
                      _section = section;
                      _unit = unit;
                    }),
                    onRegister: widget.onRegister == null
                        ? null
                        : (items) async {
                            setState(() => _saving = true);
                            try {
                              await widget.onRegister!(type, items);
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
