import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'individual_payroll_settings_repository.dart';

class IndividualPayrollSettingsPage extends StatefulWidget {
  const IndividualPayrollSettingsPage({super.key});

  @override
  State<IndividualPayrollSettingsPage> createState() =>
      _IndividualPayrollSettingsPageState();
}

class _IndividualPayrollSettingsPageState
    extends State<IndividualPayrollSettingsPage> {
  static const _amountFields = <(String, String)>[
    ('day_daily', '日勤・日額'),
    ('day_overtime', '日勤・残業'),
    ('day_early', '日勤・早出'),
    ('night_daily', '夜勤・日額'),
    ('night_overtime', '夜勤・残業'),
    ('night_early', '夜勤・早出'),
    ('holiday_daily', '休日・日額'),
    ('holiday_overtime', '休日・残業'),
    ('holiday_early', '休日・早出'),
    ('holiday_night_daily', '休日夜勤・日額'),
    ('holiday_night_overtime', '休日夜勤・残業'),
    ('holiday_night_early', '休日夜勤・早出'),
    ('allowance_1', '手当1'),
    ('allowance_2', '手当2'),
    ('allowance_3', '手当3'),
    ('family_monthly', '家族手当・月額'),
    ('transport_monthly', '交通費・月額'),
    ('income_tax_monthly', '所得税・月額'),
    ('resident_tax_monthly', '住民税・月額'),
    ('social_insurance_monthly', '社会保険・月額'),
    ('other_deduction_monthly', 'その他控除・月額'),
  ];

  final _repository = IndividualPayrollSettingsRepository.maybeCreate();
  final _controllers = <String, TextEditingController>{};
  final _customDeductions = <_CustomDeductionEditors>[];
  IndividualPayrollWorkspace? _workspace;
  String? _workerId;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    for (final field in _amountFields) {
      _controllers[field.$1] = TextEditingController();
    }
    for (var i = 1; i <= 3; i++) {
      _controllers['allowance_name_$i'] = TextEditingController();
    }
    _controllers['paid_leave_granted_days'] = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final item in _customDeductions) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '個別給与設定を利用できません。';
      });
      return;
    }
    try {
      final workspace = await repository.loadWorkspace();
      if (!workspace.canView) {
        if (!mounted) return;
        setState(() {
          _workspace = workspace;
          _loading = false;
          _error = '個別給与設定を閲覧する権限がありません。';
        });
        return;
      }
      final firstWorker =
          workspace.workers.isEmpty ? null : workspace.workers.first.id;
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _workerId = firstWorker;
        _loading = false;
      });
      if (firstWorker != null) await _loadWorker(firstWorker);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadWorker(String workerId) async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _loading = true);
    try {
      final setting = await repository.loadSetting(workerId);
      for (final field in _amountFields) {
        _controllers[field.$1]!.text =
            setting.amount(field.$1).toStringAsFixed(0);
      }
      for (var i = 1; i <= 3; i++) {
        final key = 'allowance_name_$i';
        _controllers[key]!.text = setting.text(key);
      }
      _controllers['paid_leave_granted_days']!.text =
          setting.amount('paid_leave_granted_days').toString();
      for (final item in _customDeductions) {
        item.dispose();
      }
      _customDeductions.clear();
      final custom = setting.values['custom_deductions'];
      if (custom is List) {
        for (final raw in custom) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          _customDeductions.add(
            _CustomDeductionEditors(
              name: row['name']?.toString() ?? '',
              amount: (row['amount_yen'] as num?)?.toInt().toString() ?? '0',
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _workerId = workerId;
        _updatedAt = setting.updatedAt;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final repository = _repository;
    final workerId = _workerId;
    final workspace = _workspace;
    if (repository == null || workerId == null || workspace == null) return;
    if (!workspace.canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('個別給与設定を編集する権限がありません')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('個別給与設定を保存しますか？'),
        content: const Text('この社員の給与計算に使用する設定を更新します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定して保存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final values = <String, dynamic>{};
    for (final field in _amountFields) {
      final parsed = num.tryParse(_controllers[field.$1]!.text.trim());
      if (parsed == null || parsed < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${field.$2}は0以上の数字で入力してください')),
        );
        return;
      }
      values[field.$1] = parsed;
    }
    for (var i = 1; i <= 3; i++) {
      final key = 'allowance_name_$i';
      values[key] = _controllers[key]!.text.trim();
    }
    final paidLeaveGrantedDays = num.tryParse(
      _controllers['paid_leave_granted_days']!.text.trim(),
    );
    if (paidLeaveGrantedDays == null || paidLeaveGrantedDays < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('有給付与日数は0以上の数字で入力してください')),
      );
      return;
    }
    values['paid_leave_granted_days'] = paidLeaveGrantedDays;

    final customDeductions = <Map<String, dynamic>>[];
    final seenNames = <String>{};
    for (final item in _customDeductions) {
      final name = item.name.text.trim();
      final amount = int.tryParse(item.amount.text.trim());
      if (name.isEmpty && (amount == null || amount == 0)) continue;
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('追加控除の名称を入力してください')),
        );
        return;
      }
      if (amount == null || amount < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name は0以上の金額で入力してください')),
        );
        return;
      }
      if (!seenNames.add(name)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('追加控除「$name」が重複しています')),
        );
        return;
      }
      customDeductions.add({'name': name, 'amount_yen': amount});
    }
    values['custom_deductions'] = customDeductions;

    setState(() => _saving = true);
    try {
      await repository.saveSetting(workerId: workerId, values: values);
      await _loadWorker(workerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('個別給与設定を保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '個別給与設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _workerId,
                        decoration: const InputDecoration(
                          labelText: '社員',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final worker in workspace!.workers)
                            DropdownMenuItem(
                              value: worker.id,
                              child: Text(worker.name),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _loadWorker(value);
                        },
                      ),
                      if (_updatedAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '最終更新日：${_dateTime(_updatedAt!)}',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _sectionTitle('勤務単価'),
                      for (final field in _amountFields.take(12))
                        _amountField(field.$1, field.$2),
                      const SizedBox(height: 12),
                      _sectionTitle('手当'),
                      for (var i = 1; i <= 3; i++) ...[
                        TextFormField(
                          controller: _controllers[
                              'allowance_name_$i'],
                          enabled: workspace.canEdit,
                          maxLength: 100,
                          decoration: InputDecoration(
                            labelText: '手当$i 名称',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        _amountField(
                          'allowance_$i',
                          '手当$i 金額',
                        ),
                      ],
                      _amountField('family_monthly', '家族手当・月額'),
                      _amountField('transport_monthly', '交通費・月額'),
                      const SizedBox(height: 12),
                      _sectionTitle('有給'),
                      _amountField(
                        'paid_leave_granted_days',
                        '有給付与日数',
                        suffixText: '日',
                      ),
                      const Text(
                        '承認済みの有給申請から使用日数と残日数を自動計算します。',
                      ),
                      const SizedBox(height: 12),
                      _sectionTitle('控除'),
                      _amountField('income_tax_monthly', '所得税・月額'),
                      _amountField('resident_tax_monthly', '住民税・月額'),
                      _amountField(
                          'social_insurance_monthly', '社会保険・月額'),
                      _amountField(
                          'other_deduction_monthly', 'その他控除・月額'),
                      const SizedBox(height: 4),
                      for (var i = 0; i < _customDeductions.length; i++)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _customDeductions[i].name,
                                    enabled: workspace.canEdit,
                                    maxLength: 100,
                                    decoration: InputDecoration(
                                      labelText: '追加控除${i + 1} 名称',
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _customDeductions[i].amount,
                                    enabled: workspace.canEdit,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '金額',
                                      suffixText: '円',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                if (workspace.canEdit)
                                  IconButton(
                                    tooltip: '削除',
                                    onPressed: () {
                                      setState(() {
                                        final removed = _customDeductions.removeAt(i);
                                        removed.dispose();
                                      });
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (workspace.canEdit)
                        OutlinedButton.icon(
                          onPressed: () => setState(
                            () => _customDeductions.add(
                              _CustomDeductionEditors(name: '', amount: '0'),
                            ),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('控除項目を追加'),
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        '名称は自由に変更できます。追加した控除は給与明細の控除欄へ自動反映します。',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed:
                            workspace.canEdit && !_saving ? _save : null,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? '保存中…' : '個別給与設定を保存'),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _sectionTitle(String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  Widget _amountField(
    String key,
    String label, {
    String suffixText = '円',
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: _controllers[key],
          enabled: _workspace?.canEdit == true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffixText,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  String _dateTime(DateTime value) =>
      '${value.year}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}


class _CustomDeductionEditors {
  _CustomDeductionEditors({required String name, required String amount})
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount);

  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}
