import '../../international/language_controller.dart';
import 'dart:convert';

import '../../domain/payroll_rate_settings_hydration.dart';
import 'package:flutter/material.dart';

import '../../widgets/rate_formula_editor_card.dart';
import '../notifications/notification_bell.dart';
import 'individual_payroll_settings_repository.dart';
import 'payroll_confirmation_repository.dart';
import 'payroll_confirmation_settings_page.dart';
import 'paid_leave_pay.dart';
import 'payroll_draft_keep_alive.dart';
import 'resident_tax_section.dart';
import 'resident_tax_capability.dart';

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
  int _loadGeneration = 0;
  bool _loading = true;
  bool _saving = false;
  bool _paidLeaveWagesAvailable = false;
  ResidentTaxCapability _residentTaxCapability = ResidentTaxCapability.unknown;
  String? _error;
  DateTime? _updatedAt;
  Map<String, dynamic> _settingValues = const {};
  RateFormulaDraft? _rateDraft;
  String? _initialRateSignature;

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
    _controllers['paid_leave_daily_yen'] = TextEditingController();
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
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() { _loading = true; _error = null; });
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
      final paidLeaveWagesAvailable = await repository.supportsPaidLeaveWages();
      final residentTaxCapability = await repository.residentTaxCapability();
      if (!mounted || generation != _loadGeneration) return;
      PayrollConfirmationSettings? companyPolicy;
      try {
        companyPolicy = await _confirmationRepository?.loadSettings();
      } catch (_) {
        // Keep existing individual salary permissions independent of company settings.
      }
      if (!mounted || generation != _loadGeneration) return;
      if (!workspace.canView) {
        if (!mounted || generation != _loadGeneration) return;
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
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _workspace = workspace;
        _companyPolicy = companyPolicy;
        _paidLeaveWagesAvailable = paidLeaveWagesAvailable;
        _residentTaxCapability = residentTaxCapability;
        _workerId = firstWorker;
        _loading = false;
      });
      if (firstWorker != null) await _loadWorker(firstWorker);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _retryResidentTaxCapability() async {
    final generation = _loadGeneration;
    final workerId = _workerId;
    final capability = await _repository?.residentTaxCapability();
    if (!mounted || generation != _loadGeneration || workerId != _workerId) {
      return;
    }
    setState(() { _residentTaxCapability = capability ?? ResidentTaxCapability.unknown; });
  }

  String _rateSignature(RateFormulaDraft draft) => jsonEncode({
    'base': draft.baseRateYen,
    'pay_type': draft.payType,
    'formula': draft.formula.toMap(
      hourlyRateYen: draft.formula.hourlyBase ? draft.baseRateYen : 0,
    ),
    'overrides': draft.overrides,
  });

  Future<void> _loadWorker(String workerId) async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final repository = _repository;
    if (repository == null) return;
    setState(() => _loading = true);
    try {
      final setting = await repository.loadSetting(workerId);
      if (!mounted || generation != _loadGeneration) return;
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
      final storedFormula = setting.values['rate_formula'];
      final leaveOverride = storedFormula is Map ? storedFormula['paid_leave_daily_yen'] : null;
      _controllers['paid_leave_daily_yen']!.text = leaveOverride?.toString() ?? '';
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
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _workerId = workerId;
        _updatedAt = setting.updatedAt;
        _settingValues = hydratePayrollRateSettings(setting.values);
        _rateDraft = null;
        _initialRateSignature = null;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
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
          .showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('個別給与設定を編集する権限がありません'))));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(SkoLanguageController.tr('個別給与設定を保存しますか？')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(SkoLanguageController.tr('この社員の給与計算に使用する設定を更新します。')),
          if (_residentTaxCapability == ResidentTaxCapability.timeline)
            const Text('住民税は「住民税だけ保存」で保存してください。'),
          if (_residentTaxCapability == ResidentTaxCapability.unknown)
            const Text('住民税は確認できないため、この保存では変更しません。'),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(SkoLanguageController.tr('キャンセル')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(SkoLanguageController.tr('確定して保存')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final values = <String, dynamic>{};
    final rateDraft = _rateDraft;
    if (rateDraft == null || rateDraft.baseRateYen < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('勤務単価の基準額を確認してください'))));
      return;
    }
    final formula = rateDraft.formula;
    if (rateDraft.payType == 'monthly' && rateDraft.monthlySalaryYen <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('月給の場合は月固定給を入力してください'))));
      return;
    }
    if (rateDraft.payType == 'monthly' && rateDraft.baseRateYen <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('月給の場合は計算用1日基本ベースを入力してください'))),
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
      ..['rate_formula'] = {
        if (_settingValues['rate_formula'] is Map)
          ...Map<String, dynamic>.from(_settingValues['rate_formula'] as Map),
        ...formula.toMap(
          hourlyRateYen: formula.hourlyBase ? rateDraft.baseRateYen : 0,
        ),
      }
      ..['rate_overrides'] = rateDraft.overrides;

    preserveUnchangedPayrollRates(
      values,
      _settingValues,
      unchanged: _initialRateSignature == _rateSignature(rateDraft),
    );

    for (final field in _amountFields.skip(12)) {
      // Preserve the legacy fixed value; schedules save through their own RPC.
      if (field.$1 == 'resident_tax_monthly' &&
          !residentTaxUsesGeneralSave(_residentTaxCapability)) {
        continue;
      }
      final parsed = num.tryParse(_controllers[field.$1]!.text.trim());
      if (parsed == null || parsed < 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(SkoLanguageController.trParams('{field}は0以上の数字で入力してください', {'field': SkoLanguageController.tr(field.$2)}))));
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
      ).showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('有給付与日数は0以上の数字で入力してください'))));
      return;
    }
    values['paid_leave_granted_days'] = paidLeaveGrantedDays;
    if (_paidLeaveWagesAvailable && rateDraft.payType == 'hourly') {
      final text = _controllers['paid_leave_daily_yen']!.text.trim();
      final amount = text.isEmpty ? null : int.tryParse(text);
      if (text.isNotEmpty && (amount == null || amount < 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(SkoLanguageController.tr('有給1日分の金額は0以上の整数で入力してください'))),
        );
        return;
      }
      final storedFormula = values['rate_formula'] as Map<String, dynamic>;
      if (amount == null) {
        storedFormula.remove('paid_leave_daily_yen');
      } else {
        storedFormula['paid_leave_daily_yen'] = amount;
      }
    }

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
          .showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('個別給与設定を保存しました'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(SkoLanguageController.trParams('保存できませんでした: {error}', {'error': error}))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('個別給与設定'),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(SkoLanguageController.tr(_error!), textAlign: TextAlign.center),
                      SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          final workerId = _workerId;
                          if (_workspace != null && _workspace!.canView && workerId != null) {
                            _loadWorker(workerId);
                          } else { _load(); }
                        },
                        icon: Icon(Icons.refresh),
                        label: Text(SkoLanguageController.tr('再読み込み')),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _workerId,
                    decoration: InputDecoration(
                      labelText: SkoLanguageController.tr('社員'),
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
                    SizedBox(height: 6),
                    Text(
                      SkoLanguageController.trParams('最終更新日：{date}', {'date': _dateTime(_updatedAt!)}),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  SizedBox(height: 16),
                  Text(SkoLanguageController.tr('給与単価：選択した社員の個別設定／給料日・締め日：会社設定')),
                  SizedBox(height: 8),
                  PayrollDraftKeepAlive(
                    key: ValueKey('payroll-rate-${_workerId ?? ''}'),
                    child: RateFormulaEditorCard(
                      title: SkoLanguageController.tr('勤務単価 自動計算'),
                      initialBaseRateYen:
                          _rateDraft?.baseRateYen ??
                          (_settingValues['pay_type']?.toString() == 'monthly'
                              ? (_settingValues['calculation_daily_base_yen']
                                        as num?)
                                    ?.toInt()
                              : (_settingValues['day_daily'] as num?)?.toInt()) ??
                          0,
                      initialFormula: _rateDraft?.formula.toMap(
                        hourlyRateYen: _rateDraft!.formula.hourlyBase
                            ? _rateDraft!.baseRateYen
                            : 0,
                      ) ?? _settingValues['rate_formula'],
                      initialPayType:
                          _rateDraft?.payType ??
                          _settingValues['pay_type']?.toString() ?? 'daily',
                      initialMonthlySalaryYen:
                          _rateDraft?.monthlySalaryYen ??
                          (_settingValues['monthly_salary_yen'] as num?)
                              ?.toInt() ??
                          0,
                      initialOverrides: _rateDraft?.overrides ??
                          _settingValues['rate_overrides'],
                      enabled: workspace.canEdit,
                      onChanged: (value) {
                        _initialRateSignature ??= _rateSignature(value);
                        setState(() => _rateDraft = value);
                      },
                    ),
                  ),
                  SizedBox(height: 12),
                  _moneySection(
                    title: '支給',
                    icon: Icons.add_circle_outline,
                    children: [
                      _sectionTitle(SkoLanguageController.tr('手当')),
                      for (var i = 1; i <= 3; i++) ...[
                        TextFormField(
                          controller: _controllers['allowance_name_$i'],
                          enabled: workspace.canEdit,
                          maxLength: 100,
                          decoration: InputDecoration(
                            labelText: SkoLanguageController.trParams('手当{number} 名称', {'number': i}),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        _amountField('allowance_$i', SkoLanguageController.trParams('手当{number} 金額', {'number': i})),
                      ],
                      _amountField('family_monthly', SkoLanguageController.tr('家族手当・月額（既存設定）')),
                      Text(SkoLanguageController.tr('この金額と追加支給の「家族手当」は別項目として合算されます。不要な既存分は0円に変更できます。')),
                      _amountField('transport_monthly', SkoLanguageController.tr('交通費・月額')),
                      SizedBox(height: 12),
                      _sectionTitle(SkoLanguageController.tr('追加支給')),
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
                          icon: Icon(Icons.add),
                          label: Text(SkoLanguageController.tr('支給項目を追加')),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _sectionTitle(SkoLanguageController.tr('会社共通の給料日')),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _companyPolicy == null
                          ? SkoLanguageController.tr('会社データで設定します')
                          : SkoLanguageController.trParams(
                              '{month}{day}払い・末締め', {
                                'month': SkoLanguageController.tr(
                                  _companyPolicy!.paymentMonthOffset == 2 ? '翌々月'
                                    : _companyPolicy!.paymentMonthOffset == 1 ? '翌月' : '当月'),
                                'day': _companyPolicy!.paymentDay == 31
                                  ? SkoLanguageController.tr('末日')
                                  : SkoLanguageController.trParams('{day}日', {'day': _companyPolicy!.paymentDay}),
                              }),
                    ),
                    subtitle: Text(SkoLanguageController.tr('全社員共通。会社データの設定を使用します。')),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PayrollConfirmationSettingsPage(),
                        ),
                      );
                      final policy = await _confirmationRepository
                          ?.loadSettings();
                      if (mounted) {
                        setState(() => _companyPolicy = policy);
                      }
                    },
                  ),
                  SizedBox(height: 12),
                  _sectionTitle(SkoLanguageController.tr('有給')),
                  _amountField(
                    'paid_leave_granted_days',
                    SkoLanguageController.tr('有給付与日数'),
                    suffixText: SkoLanguageController.tr('日'),
                  ),
                  Text(SkoLanguageController.tr('承認済みの有給申請から使用日数と残日数を自動計算します。')),
                  if (!_paidLeaveWagesAvailable)
                    Text(SkoLanguageController.tr('有給額の自動計算はサーバー準備待ちです。現在の給与条件の警告を確認してください。'))
                  else ...[
                    if (_rateDraft?.payType == 'hourly' ||
                        (_rateDraft == null && _settingValues['pay_type'] == 'hourly'))
                      _amountField('paid_leave_daily_yen',
                        SkoLanguageController.tr('有給1日分（空欄は時給×8時間）')),
                    Text(SkoLanguageController.trParams('有給1日分：{amount}円',
                      {'amount': _currentPaidLeavePay().dailyAmountYen})),
                    Text(SkoLanguageController.tr('日給は登録日給。時給は初期値が時給×8時間で変更可能。月給は設定した1日分の内訳額で、月給に重ねて加算せず有給取得で月給を減額しません。')),
                  ],
                  SizedBox(height: 12),
                  _moneySection(
                    title: '控除',
                    icon: Icons.remove_circle_outline,
                    children: [
                      _sectionTitle(SkoLanguageController.tr('税・社会保険の月額設定')),
                      _amountField('income_tax_monthly', SkoLanguageController.tr('所得税・月額')),
                      _amountField('social_insurance_monthly', SkoLanguageController.tr('社会保険・月額')),
                      SizedBox(height: 12),
                      _sectionTitle(SkoLanguageController.tr('住民税')),
                      if (_residentTaxCapability == ResidentTaxCapability.legacy)
                        _amountField('resident_tax_monthly', SkoLanguageController.tr('住民税・月額'))
                      else if (_residentTaxCapability == ResidentTaxCapability.unknown) ...[
                        const Text('住民税の設定方式を確認できません。住民税は変更せず、他の給与設定を保存できます。'),
                        TextButton(onPressed: _saving ? null : _retryResidentTaxCapability, child: const Text('再確認')),
                      ] else if (_workerId != null) ResidentTaxSection(
                        key: ValueKey('resident-tax-$_workerId'),
                        workerId: _workerId!,
                        companyId: _settingValues['company_id'] is String ? _settingValues['company_id'] as String : workspace.companyId,
                        canEdit: workspace.canEdit && !_saving,
                        legacyAmount: num.tryParse(_controllers['resident_tax_monthly']!.text) ?? 0,
                      ),
                      SizedBox(height: 12),
                      _sectionTitle(SkoLanguageController.tr('その他の控除')),
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
                          icon: Icon(Icons.add),
                          label: Text(SkoLanguageController.tr('控除項目を追加')),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: workspace.canEdit && !_saving ? _save : null,
                    icon: Icon(Icons.save_outlined),
                    label: Text(_saving ? SkoLanguageController.tr('保存中…') : SkoLanguageController.tr('個別給与設定を保存')),
                  ),
                ],
              ),
      ),
    );
  }

  PaidLeavePay _currentPaidLeavePay() {
    final values = Map<String, dynamic>.from(_settingValues);
    final draft = _rateDraft;
    if (draft != null) {
      values['pay_type'] = draft.payType;
      values['day_daily'] = draft.formula.dailyBase(draft.baseRateYen);
      values['hourly_rate_yen'] = draft.baseRateYen;
      values['calculation_daily_base_yen'] = draft.baseRateYen;
    }
    final text = _controllers['paid_leave_daily_yen']!.text.trim();
    values['rate_formula'] = {
      if (values['rate_formula'] is Map)
        ...Map<String, dynamic>.from(values['rate_formula'] as Map),
      if (draft != null && draft.payType == 'hourly')
        'hourly_rate_yen': draft.baseRateYen,
      'paid_leave_daily_yen': text.isEmpty ? null : int.tryParse(text),
    };
    return PaidLeavePay.fromSettings(values);
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
          SnackBar(content: Text(SkoLanguageController.trParams('{section}項目{number}の名称を入力してください', {'section': SkoLanguageController.tr(sectionName), 'number': index + 1}))),
        );
        return null;
      }
      if (!seen.add(name)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(SkoLanguageController.trParams('「{name}」は重複しています', {'name': name}))));
        return null;
      }
      final amount = int.tryParse(amountText);
      if (amount == null || amount < 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(SkoLanguageController.trParams('「{name}」の金額は0以上の数字で入力してください', {'name': name}))));
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
                labelText: SkoLanguageController.trParams('{section}{number} 名称', {'section': SkoLanguageController.tr(sectionName), 'number': index + 1}),
                border: OutlineInputBorder(),
              ),
            ),
            TextFormField(
              controller: item.amount,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: SkoLanguageController.trParams('{section}{number} 金額', {'section': SkoLanguageController.tr(sectionName), 'number': index + 1}),
                suffixText: SkoLanguageController.tr('円'),
                border: OutlineInputBorder(),
              ),
            ),
            if (enabled)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _removeCustomMoney(items, index),
                  icon: Icon(Icons.delete_outline),
                  label: Text(SkoLanguageController.trParams('この{section}を削除', {'section': SkoLanguageController.tr(sectionName)})),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _moneySection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(SkoLanguageController.tr(title),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        const Divider(height: 24),
        ...children,
      ],
    ),
  );

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      SkoLanguageController.tr(value),
      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
    ),
  );

  Widget _amountField(String key, String label, {String suffixText = '円'}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: _controllers[key],
          enabled: _workspace?.canEdit == true,
          keyboardType: TextInputType.number,
          onChanged: key == 'paid_leave_daily_yen' ? (_) => setState(() {}) : null,
          decoration: InputDecoration(
            labelText: SkoLanguageController.tr(label),
            suffixText: SkoLanguageController.tr(suffixText),
            border: OutlineInputBorder(),
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
