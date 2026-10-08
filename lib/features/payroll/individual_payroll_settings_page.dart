import 'package:flutter/material.dart';

import '../../widgets/rate_formula_editor_card.dart';
import '../notifications/notification_bell.dart';
import 'individual_payroll_settings_repository.dart';
import 'payroll_confirmation_repository.dart';
import 'payroll_confirmation_settings_page.dart';

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
  ];

  final _repository = IndividualPayrollSettingsRepository.maybeCreate();
  final _confirmationRepository = PayrollConfirmationRepository.maybeCreate();
  PayrollConfirmationSettings? _companyPolicy;
  final _controllers = <String, TextEditingController>{};
  final _customEarnings = <_CustomMoneyDraft>[];
  final _customDeductions = <_CustomMoneyDraft>[];
  IndividualPayrollWorkspace? _workspace;
  String? _workerId;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  DateTime? _updatedAt;
  Map<String, dynamic> _settingValues = const {};
  RateFormulaDraft? _rateDraft;

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
    for (final item in [..._customEarnings, ..._customDeductions]) {
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
      PayrollConfirmationSettings? companyPolicy;
      try {
        companyPolicy = await _confirmationRepository?.loadSettings();
      } catch (_) {
        // Keep existing individual salary permissions independent of company settings.
      }
      if (!workspace.canView) {
        if (!mounted) return;
        setState(() {
          _workspace = workspace;
          _loading = false;
          _error = '個別給与設定を閲覧する権限がありません。';
        });
        return;
      }
      final firstWorker = workspace.workers.isEmpty
          ? null
          : workspace.workers.first.id;
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _companyPolicy = companyPolicy;
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
        _controllers[field.$1]!.text = setting
            .amount(field.$1)
            .toStringAsFixed(0);
      }
      for (var i = 1; i <= 3; i++) {
        final key = 'allowance_name_$i';
        _controllers[key]!.text = setting.text(key);
      }
      _controllers['paid_leave_granted_days']!.text = setting
          .amount('paid_leave_granted_days')
          .toString();
      for (final item in [..._customEarnings, ..._customDeductions]) {
        item.dispose();
      }
      _customEarnings
        ..clear()
        ..addAll(
          _customMoneyDrafts(
            setting.values['custom_earnings'],
            defaults: const ['勤続手当', '役職手当', '家族手当', '働き方手当'],
          ),
        );
      _customDeductions
        ..clear()
        ..addAll(
          _customMoneyDrafts(
            setting.values['custom_deductions'],
            defaults: const ['介護保険料', '厚生年金保険', '雇用保険料', 'SKO会費'],
          ),
        );
      if (!mounted) return;
      setState(() {
        _workerId = workerId;
        _updatedAt = setting.updatedAt;
        _settingValues = Map<String, dynamic>.from(setting.values);
        _rateDraft = null;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('個別給与設定を編集する権限がありません')));
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
    final rateDraft = _rateDraft;
    if (rateDraft == null || rateDraft.baseRateYen < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('勤務単価の基準額を確認してください')));
      return;
    }
    final formula = rateDraft.formula;
    if (rateDraft.payType == 'monthly' && rateDraft.monthlySalaryYen <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('月給の場合は月固定給を入力してください')));
      return;
    }
    if (rateDraft.payType == 'monthly' && rateDraft.baseRateYen <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('月給の場合は計算用1日基本ベースを入力してください')),
      );
      return;
    }
    final hours = formula.hoursPerDay <= 0 ? 8 : formula.hoursPerDay;
    final dailyBase = formula.dailyBase(rateDraft.baseRateYen);
    final nightEarly =
        (rateDraft.effective('night') / hours * formula.earlyMultiplier)
            .round();
    final holidayEarly =
        (rateDraft.effective('holiday') / hours * formula.earlyMultiplier)
            .round();
    final holidayNightEarly =
        (rateDraft.effective('holiday_night') / hours * formula.earlyMultiplier)
            .round();

    values
      ..['pay_type'] = rateDraft.payType
      ..['monthly_salary_yen'] = rateDraft.payType == 'monthly'
          ? rateDraft.monthlySalaryYen
          : 0
      ..['calculation_daily_base_yen'] = rateDraft.payType == 'monthly'
          ? dailyBase
          : 0
      ..['day_daily'] = dailyBase
      ..['day_overtime'] = rateDraft.effective('overtime')
      ..['day_early'] = rateDraft.effective('early')
      ..['night_daily'] = rateDraft.effective('night')
      ..['night_overtime'] = rateDraft.effective('night_overtime')
      ..['night_early'] = nightEarly
      ..['holiday_daily'] = rateDraft.effective('holiday')
      ..['holiday_overtime'] = rateDraft.effective('holiday_overtime')
      ..['holiday_early'] = holidayEarly
      ..['holiday_night_daily'] = rateDraft.effective('holiday_night')
      ..['holiday_night_overtime'] = rateDraft.effective(
        'holiday_night_overtime',
      )
      ..['holiday_night_early'] = holidayNightEarly
      ..['hourly_rate_yen'] = formula.hourlyBase
          ? rateDraft.baseRateYen
          : (dailyBase / hours).round()
      ..['rate_formula'] = formula.toMap(
        hourlyRateYen: formula.hourlyBase ? rateDraft.baseRateYen : 0,
      )
      ..['rate_overrides'] = rateDraft.overrides;

    for (final field in _amountFields.skip(12)) {
      final parsed = num.tryParse(_controllers[field.$1]!.text.trim());
      if (parsed == null || parsed < 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${field.$2}は0以上の数字で入力してください')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('有給付与日数は0以上の数字で入力してください')));
      return;
    }
    values['paid_leave_granted_days'] = paidLeaveGrantedDays;

    final customEarnings = _serializeCustomMoney(
      _customEarnings,
      sectionName: '支給',
    );
    if (customEarnings == null) return;
    final customDeductions = _serializeCustomMoney(
      _customDeductions,
      sectionName: '控除',
    );
    if (customDeductions == null) return;
    values['custom_earnings'] = customEarnings;
    values['custom_deductions'] = customDeductions;

    setState(() => _saving = true);
    try {
      await repository.saveSetting(workerId: workerId, values: values);
      await _loadWorker(workerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('個別給与設定を保存しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存できませんでした: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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
                  RateFormulaEditorCard(
                    key: ValueKey('payroll-rate-${_workerId ?? ''}'),
                    title: '勤務単価 自動計算',
                    initialBaseRateYen:
                        (_settingValues['pay_type']?.toString() == 'monthly'
                            ? (_settingValues['calculation_daily_base_yen']
                                      as num?)
                                  ?.toInt()
                            : (_settingValues['day_daily'] as num?)?.toInt()) ??
                        0,
                    initialFormula: _settingValues['rate_formula'],
                    initialPayType:
                        _settingValues['pay_type']?.toString() ?? 'daily',
                    initialMonthlySalaryYen:
                        (_settingValues['monthly_salary_yen'] as num?)
                            ?.toInt() ??
                        0,
                    initialOverrides: _settingValues['rate_overrides'],
                    enabled: workspace.canEdit,
                    onChanged: (value) => _rateDraft = value,
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('手当'),
                  for (var i = 1; i <= 3; i++) ...[
                    TextFormField(
                      controller: _controllers['allowance_name_$i'],
                      enabled: workspace.canEdit,
                      maxLength: 100,
                      decoration: InputDecoration(
                        labelText: '手当$i 名称',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    _amountField('allowance_$i', '手当$i 金額'),
                  ],
                  _amountField('transport_monthly', '交通費・月額'),
                  const SizedBox(height: 12),
                  _sectionTitle('追加支給'),
                  for (var i = 0; i < _customEarnings.length; i++)
                    _customMoneyField(
                      _customEarnings,
                      i,
                      workspace.canEdit,
                      sectionName: '支給',
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: workspace.canEdit
                          ? () => _addCustomMoney(_customEarnings)
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('支給項目を追加'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('会社共通の給料日'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _companyPolicy == null
                          ? '会社データで設定します'
                          : '${_companyPolicy!.paymentMonthOffset == 2
                                ? '翌々月'
                                : _companyPolicy!.paymentMonthOffset == 1
                                ? '翌月'
                                : '当月'}${_companyPolicy!.paymentDay == 31 ? '末日' : '${_companyPolicy!.paymentDay}日'}払い・末締め',
                    ),
                    subtitle: const Text('全社員共通。会社データの設定を使用します。'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PayrollConfirmationSettingsPage(),
                        ),
                      );
                      final policy = await _confirmationRepository
                          ?.loadSettings();
                      if (mounted) {
                        setState(() => _companyPolicy = policy);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('有給'),
                  _amountField(
                    'paid_leave_granted_days',
                    '有給付与日数',
                    suffixText: '日',
                  ),
                  const Text('承認済みの有給申請から使用日数と残日数を自動計算します。'),
                  const SizedBox(height: 12),
                  _sectionTitle('控除'),
                  _amountField('income_tax_monthly', '所得税・月額'),
                  _amountField('resident_tax_monthly', '住民税・月額'),
                  _amountField('social_insurance_monthly', '社会保険・月額'),
                  const SizedBox(height: 4),
                  for (var i = 0; i < _customDeductions.length; i++)
                    _customMoneyField(
                      _customDeductions,
                      i,
                      workspace.canEdit,
                      sectionName: '控除',
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: workspace.canEdit
                          ? () => _addCustomMoney(_customDeductions)
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('控除項目を追加'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: workspace.canEdit && !_saving ? _save : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? '保存中…' : '個別給与設定を保存'),
                  ),
                ],
              ),
      ),
    );
  }

  void _addCustomMoney(List<_CustomMoneyDraft> items) {
    setState(() => items.add(_CustomMoneyDraft()));
  }

  void _removeCustomMoney(List<_CustomMoneyDraft> items, int index) {
    final removed = items.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  List<_CustomMoneyDraft> _customMoneyDrafts(
    Object? raw, {
    required List<String> defaults,
  }) {
    final result = <_CustomMoneyDraft>[];
    final seen = <String>{};

    // A stored list is authoritative, including an empty list. Re-adding
    // defaults here made deleted rows come back immediately after save/reload.
    if (raw is List) {
      for (final value in raw) {
        if (value is! Map) continue;
        final name = value['name']?.toString().trim() ?? '';
        final amount = (value['amount_yen'] as num?)?.toInt() ?? 0;
        if (name.isEmpty || seen.contains(name)) continue;
        seen.add(name);
        result.add(_CustomMoneyDraft(name: name, amountYen: amount));
      }
      return result;
    }

    // Defaults are only for a worker with no stored flexible-list value yet.
    for (final name in defaults) {
      if (seen.add(name)) {
        result.add(_CustomMoneyDraft(name: name));
      }
    }
    return result;
  }

  List<Map<String, Object>>? _serializeCustomMoney(
    List<_CustomMoneyDraft> items, {
    required String sectionName,
  }) {
    final result = <Map<String, Object>>[];
    final seen = <String>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final name = item.name.text.trim();
      final amountText = item.amount.text.trim();
      if (name.isEmpty && amountText.isEmpty) continue;
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$sectionName項目${index + 1}の名称を入力してください')),
        );
        return null;
      }
      if (!seen.add(name)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('「$name」は重複しています')));
        return null;
      }
      final amount = int.tryParse(amountText);
      if (amount == null || amount < 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('「$name」の金額は0以上の数字で入力してください')));
        return null;
      }
      result.add({'name': name, 'amount_yen': amount});
    }
    return result;
  }

  Widget _customMoneyField(
    List<_CustomMoneyDraft> items,
    int index,
    bool enabled, {
    required String sectionName,
  }) {
    final item = items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextFormField(
              controller: item.name,
              enabled: enabled,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: '$sectionName${index + 1} 名称',
                border: const OutlineInputBorder(),
              ),
            ),
            TextFormField(
              controller: item.amount,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '$sectionName${index + 1} 金額',
                suffixText: '円',
                border: const OutlineInputBorder(),
              ),
            ),
            if (enabled)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _removeCustomMoney(items, index),
                  icon: const Icon(Icons.delete_outline),
                  label: Text('この$sectionNameを削除'),
                ),
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
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
    ),
  );

  Widget _amountField(String key, String label, {String suffixText = '円'}) =>
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

class _CustomMoneyDraft {
  _CustomMoneyDraft({String name = '', int amountYen = 0})
    : name = TextEditingController(text: name),
      amount = TextEditingController(text: amountYen.toString());

  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}
