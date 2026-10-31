import 'payroll_tax_adjustment_history.dart';
import 'payroll_insurance_settings_entry.dart';
import 'payroll_tax_conditions_page.dart';
import 'payroll_fixed_deductions.dart';
import '../settings/company_payroll_rates_page.dart';
import '../../international/language_controller.dart';
import 'dart:convert';
import 'dart:async';
import '../shared/company_allowance_label_repository.dart';
import '../shared/company_allowance_current_price_repository.dart';

import '../../domain/payroll_rate_settings_hydration.dart';
import '../../data/supabase_backend.dart';
import 'package:flutter/material.dart';

import '../../widgets/rate_formula_editor_card.dart';
import '../notifications/notification_bell.dart';
import 'individual_payroll_settings_repository.dart';
import 'payroll_confirmation_repository.dart';
import 'payroll_confirmation_settings_page.dart';
import 'paid_leave_pay.dart';
import 'payroll_draft_keep_alive.dart';
import 'payroll_keyboard_access.dart';
import 'resident_tax_section.dart';
import 'resident_tax_capability.dart';
import 'company_common_allowance_entry_page.dart';
import 'payroll_unit_conditions_page.dart';
import 'payroll_unit_item_editor.dart';
import 'individual_allowance_rows.dart';

class IndividualPayrollSettingsPage extends StatefulWidget {
  const IndividualPayrollSettingsPage({super.key, this.repository,
    this.registeredAllowanceSource});

  @visibleForTesting
  final IndividualPayrollSettingsRepository? repository;
  @visibleForTesting
  final CompanyAllowanceLabelSource? registeredAllowanceSource;

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

  late final IndividualPayrollSettingsRepository? _repository;
  late final CompanyAllowanceLabelSource? _registeredAllowanceSource;
  CompanyAllowanceLabelSnapshot? _registeredAllowanceNames;
  bool _registeredAllowanceReadFailed = false;
  final _confirmationRepository = PayrollConfirmationRepository.maybeCreate();
  PayrollConfirmationSettings? _companyPolicy;
  final _controllers = <String, TextEditingController>{};
  final _customEarnings = <_CustomMoneyDraft>[];
  final _customDeductions = <_CustomMoneyDraft>[];
  IndividualPayrollWorkspace? _workspace;
  String? _workerId;
  String? _allowanceActorAtLoad;
  bool _allowanceUsesLiveSession = false;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _saving = false;
  bool _allowanceSaveUncertain = false;
  bool _showDeductions = false;
  final _insuranceEntry = PayrollInsuranceEntryController();
  bool _positionTransferEnabled = false;
  final _positionTransferItems = <_CustomMoneyDraft>[];
  PayrollItemUnit _earningUnit = PayrollItemUnit.month;
  PayrollItemUnit _deductionUnit = PayrollItemUnit.month;
  final _unitPanelKey = GlobalKey();
  final _unitFooter = PayrollUnitEditorController();
  bool get _busy => _saving || _unitFooter.saving || _allowanceSaveUncertain;
  final _scrollController = ScrollController();
  final _addedItemKey = GlobalKey();
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
    _repository = widget.repository ?? IndividualPayrollSettingsRepository.maybeCreate();
    _registeredAllowanceSource = widget.registeredAllowanceSource ??
        CompanyAllowanceCurrentPriceRepository.maybeCreate();
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
    _insuranceEntry.dispose();
    for (final item in _positionTransferItems) { item.dispose(); }
    _unitFooter.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final item in [..._customEarnings, ..._customDeductions]) {
      item.dispose();
    }
    _scrollController.dispose();
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
    _unitFooter.invalidate();
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _registeredAllowanceNames = null;
      _registeredAllowanceReadFailed = false;
    });
    final usesLiveSession = SupabaseBackend.isInitialized;
    final actor = usesLiveSession ? SupabaseBackend.client.auth.currentUser?.id : null;
    try {
      final setting = await repository.loadSetting(workerId);
      final expectedCompany = _workspace?.companyId;
      if (expectedCompany != null && setting.values['company_id'] is String &&
          setting.values['company_id'] != expectedCompany) {
        throw StateError('給与設定の会社が一致しません');
      }
      if (usesLiveSession && (actor == null || SupabaseBackend.client.auth.currentUser?.id != actor)) {
        throw StateError('ログイン状態が変わりました');
      }
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
      final transfer = storedFormula is Map ? storedFormula['position_transfer'] : null;
      _positionTransferEnabled = transfer is Map && transfer['enabled'] == true;
      for (final item in _positionTransferItems) { item.dispose(); }
      _positionTransferItems.clear();
      if (transfer is Map && transfer['items'] is List) {
        for (final entry in transfer['items'] as List) {
          if (entry is Map && entry['name'] is String && entry['amount_yen'] is int && (entry['amount_yen'] as int) >= 0) {
            _positionTransferItems.add(_CustomMoneyDraft(name: entry['name'] as String, amountYen: entry['amount_yen'] as int));
          }
        }
      }
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
            defaults: const ['勤続手当', '役職手当', '家族手当', '交通費', '働き方手当'],
          ),
        );
      // Stage legacy monthly amounts in the flexible list. The old columns
      // are cleared in the same existing upsert as the new list, only on save.
      // Reopening a saved list cannot add the legacy amounts a second time.
      _includeLegacyMonthlyEarning('family_monthly', '家族手当');
      _includeLegacyMonthlyEarning('transport_monthly', '交通費');
      _customDeductions
        ..clear()
        ..addAll(
          _customMoneyDrafts(
            setting.values['custom_deductions'],
            defaults: const ['SKO会費'],
          ),
        );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _workerId = workerId;
        _allowanceUsesLiveSession = usesLiveSession;
        _allowanceActorAtLoad = actor;
        _updatedAt = setting.updatedAt;
        _settingValues = hydratePayrollRateSettings(setting.values);
        _rateDraft = null;
        _initialRateSignature = null;
        _loading = false;
        _error = null;
        _allowanceSaveUncertain = false;
      });
      final company = _workspace?.companyId ?? setting.values['company_id'];
      if (company is String && company.isNotEmpty) {
        unawaited(_loadRegisteredAllowanceNames(company, workerId, generation));
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save({bool registerUnitDrafts = true}) async {
    final repository = _repository;
    final workerId = _workerId;
    final workspace = _workspace;
    if (repository == null || workerId == null || workspace == null) return;
    if (!workspace.canEdit) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('個別給与設定を編集する権限がありません'))));
      return;
    }

    if (!_allowanceScopeCurrent()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
        Text('ログイン状態が変わりました。画面を開き直してください。')));
      return;
    }
    if (_allowanceSaveUncertain) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
        Text('手当の保存結果を確認するまで、保存し直せません。')));
      return;
    }
    if (!_unitFooter.validate()) return;
    try {
      splitIndividualAllowanceRows(individualAllowanceRows(_individualAllowanceValues));
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    final preparedUnits = registerUnitDrafts ? _unitFooter.prepareRegistration() : null;
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
    if (!_allowanceScopeCurrent() || _workerId != workerId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
        Text('本人または対象が変わりました。保存していません。')));
      return;
    }

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

    if (rateDraft.payType == 'daily') {
      final items = _serializeCustomMoney(_positionTransferItems, sectionName: '振替');
      if (items == null) return;
      (values['rate_formula'] as Map<String, dynamic>)['position_transfer'] = {
        'enabled': _positionTransferEnabled,
        'items': items,
      };
    }

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
    var settingsWriteStarted = false;
    try {
      settingsWriteStarted = true;
      await repository.saveSetting(workerId: workerId, values: values);
      if (!_allowanceScopeCurrent() || _workerId != workerId) {
        setState(() => _allowanceSaveUncertain = true);
        throw StateError('保存後に本人または対象が変わりました');
      }
      // The original worker settings are now acknowledged. A prepared unit
      // operation uses the values captured before confirmation, not later input.
      _settingValues = {..._settingValues, ...values};
      if (preparedUnits != null && !await preparedUnits()) {
        if (mounted) setState(() => _allowanceSaveUncertain = true);
        return;
      }
      if (!_allowanceScopeCurrent() || _workerId != workerId) {
        setState(() => _allowanceSaveUncertain = true);
        return;
      }
      await _loadWorker(workerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('個別給与設定を保存しました'))));
    } catch (error) {
      if (!mounted) return;
      if (settingsWriteStarted) setState(() => _allowanceSaveUncertain = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(SkoLanguageController.trParams('保存できませんでした: {error}', {'error': error}))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _unitFooter, builder: (context, _) => _buildSettings(context));

  Widget _buildSettings(BuildContext context) {
    SkoLanguageController.watch(context);
    final workspace = _workspace;
    final companyId = _settingValues['company_id'] is String
        ? _settingValues['company_id'] as String
        : workspace?.companyId;
    final monthly = (_showDeductions ? _deductionUnit : _earningUnit) == PayrollItemUnit.month;
    return PayrollKeyboardDismissArea(child: Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('個別給与設定'),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [IconButton(tooltip: '使い方', icon: const Icon(Icons.help_outline),
          onPressed: () => showDialog<void>(context: context, builder: (context) =>
            AlertDialog(title: const Text('手当の登録'),
              content: Text(SkoLanguageController.tr('時間・日・月の単位ごとに、追加ボタンから手当を登録します。登録済みの手当も同じ一覧で編集・削除できます。会社共通手当は現在登録されている名前と単価を共通の見出しから確認します。権限不足や取得失敗などで単価を照合できないときは「単価未確認」と表示し、0円とは扱いません。ここでの現在単価は過去の給与への適用額とは別です。「共通設定」で編集します。「個別手当」はこの社員だけの設定です。同名でも保存元を分けて保持し、共通を個別へコピーしません。会社共通の定義や確定済み明細は、この社員の手当編集では削除しません。保存結果を確認できない場合は入力を保持し、再送せず保存済みの状態を確認します。')),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]))),
          const SkoNotificationBell()],
        bottom: _updatedAt == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      SkoLanguageController.trParams('最終更新日：{date}', {
                        'date': _dateTime(_updatedAt!),
                      }),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
      ),
      bottomNavigationBar:
          _loading || _error != null || workspace?.canView != true
          ? null
          : PayrollKeyboardFooter(child: SafeArea(
              key: const ValueKey('individual-payroll-fixed-footer'),
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            workspace?.canEdit == true && !_busy && _workerId != null &&
                                (monthly || _unitFooter.canAdd)
                            ? monthly ? () => _addCustomMoney(
                                _showDeductions
                                    ? _customDeductions
                                    : _customEarnings,
                              ) : _unitFooter.add
                            : null,
                        icon: const Icon(Icons.add),
                        label: Text(SkoLanguageController.tr('追加')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            workspace?.canEdit == true && !_busy && _workerId != null &&
                                (monthly || _unitFooter.canRegister)
                            ? monthly ? _save : _unitFooter.register
                            : null,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _saving || _unitFooter.saving
                              ? SkoLanguageController.tr('保存中…')
                              : SkoLanguageController.tr('登録'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )),
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
                      Text(
                        SkoLanguageController.tr(_error!),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          final workerId = _workerId;
                          if (_workspace != null &&
                              _workspace!.canView &&
                              workerId != null) {
                            _loadWorker(workerId);
                          } else {
                            _load();
                          }
                        },
                        icon: Icon(Icons.refresh),
                        label: Text(SkoLanguageController.tr('再読み込み')),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  if (_allowanceSaveUncertain) Card(child: Padding(
                    padding: const EdgeInsets.all(12), child: Column(children: [
                      const Text('手当の保存結果を確認するまで、保存し直せません。入力を保持しています。'),
                      TextButton(onPressed: _saving ? null : _confirmAllowanceStateReload,
                        child: const Text('保存済みの状態を確認')),
                    ]))),
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
                    onChanged: _busy ? null : (value) {
                      if (value != null) _loadWorker(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  PayrollDraftKeepAlive(
                    // Rebuild from saved rates even when a fast reload skips a loading frame.
                    key: ValueKey('payroll-rate-${_workerId ?? ''}-$_loadGeneration'),
                    child: RateFormulaEditorCard(
                      compact: true,
                      title: SkoLanguageController.tr('勤務単価 自動計算'),
                      initialBaseRateYen:
                          _rateDraft?.baseRateYen ??
                          (_settingValues['pay_type']?.toString() == 'monthly'
                              ? (_settingValues['calculation_daily_base_yen']
                                        as num?)
                                    ?.toInt()
                              : (_settingValues['day_daily'] as num?)
                                    ?.toInt()) ??
                          0,
                      initialFormula:
                          _rateDraft?.formula.toMap(
                            hourlyRateYen: _rateDraft!.formula.hourlyBase
                                ? _rateDraft!.baseRateYen
                                : 0,
                          ) ??
                          _settingValues['rate_formula'],
                      initialPayType:
                          _rateDraft?.payType ??
                          _settingValues['pay_type']?.toString() ??
                          'daily',
                      initialMonthlySalaryYen:
                          _rateDraft?.monthlySalaryYen ??
                          (_settingValues['monthly_salary_yen'] as num?)
                              ?.toInt() ??
                          0,
                      initialOverrides:
                          _rateDraft?.overrides ??
                          _settingValues['rate_overrides'],
                      enabled: workspace.canEdit,
                      onChanged: (value) {
                        _initialRateSignature ??= _rateSignature(value);
                        setState(() => _rateDraft = value);
                      },
                    ),
                  ),
                  SizedBox(height: 12),
                  PayrollInsuranceSettingsEntry(
                    key: const ValueKey('insurance-settings-global-entry'),
                    controller: _insuranceEntry, enabled: !_busy,
                  ),
                  Align(alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const ValueKey('payroll-tax-adjustment-history-open'),
                      icon: const Icon(Icons.history), label: const Text('保険料・税の変更履歴'),
                      onPressed: _busy || _workerId == null || companyId == null || companyId.isEmpty ? null : () {
                        final selectedWorker = _workerId!;
                        final selectedCompany = companyId;
                        final generation = _loadGeneration;
                        final name = workspace.workers.firstWhere((worker) => worker.id == selectedWorker,
                          orElse: () => const IndividualPayrollWorker(id: '', name: '選択したメンバー')).name;
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                          PayrollTaxAdjustmentHistoryPage(companyId: selectedCompany,
                            workerId: selectedWorker, workerName: name,
                            scopeIsCurrent: () => mounted && _workspace?.canView == true &&
                              _loadGeneration == generation && _workerId == selectedWorker &&
                              (_settingValues['company_id'] is String ? _settingValues['company_id'] : _workspace?.companyId) == selectedCompany)));
                      },
                    )),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(SkoLanguageController.tr('支給')),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(SkoLanguageController.tr('控除')),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                    selected: {_showDeductions},
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                      ),
                    ),
                    onSelectionChanged: _busy ? null : (values) =>
                        setState(() => _showDeductions = values.first),
                  ),
                  const SizedBox(height: 12),
                  PayrollDraftKeepAlive(
                    key: ValueKey('payroll-earnings-$_workerId'),
                    child: Offstage(
                      offstage: _showDeductions,
                      child: _moneySection(
                        title: '支給',
                        icon: Icons.add_circle_outline,
                        children: [
                          SizedBox(height: 12),
                          _sectionTitle(SkoLanguageController.tr('追加支給')),
                          for (var i = 0; i < _customEarnings.length; i++)
                            _customMoneyField(
                              _customEarnings,
                              i,
                              workspace.canEdit,
                              sectionName: '支給',
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  PayrollDraftKeepAlive(
                    key: ValueKey('payroll-deductions-$_workerId'),
                    child: Offstage(
                      offstage: !_showDeductions,
                      child: _moneySection(
                        title: '控除',
                        icon: Icons.remove_circle_outline,
                        leadingChildren: [
                          if (_workerId != null)
                            PayrollFixedDeductions(
                              key: ValueKey('fixed-deductions-$_workerId'),
                              entryController: _insuranceEntry,
                              showAmounts: _deductionUnit == PayrollItemUnit.month,
                              companyId: companyId ?? '',
                              workerId: _workerId!,
                              canEdit: workspace.canEdit && !_saving,
                              refreshRevision: _loadGeneration,
                              legacySocialAmount: num.tryParse(
                                _controllers['social_insurance_monthly']!.text,
                              ) ?? 0,
                              readStatement: _repository!.loadMonthlyDeductionStatement,
                              openConditions: companyId == null || companyId.isEmpty
                                  ? null : (month) async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(builder: (_) =>
                                          PayrollTaxConditionsPage(
                                            companyId: companyId,
                                            workerId: _workerId!,
                                            month: DateTime.parse(month),
                                          )),
                                      );
                                    },
                              openRates: companyId == null || companyId.isEmpty
                                  ? null : () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(builder: (_) =>
                                          CompanyPayrollRatesPage(companyId: companyId)),
                                      );
                                    },
                              residentTaxBuilder: (month, onEditingChanged) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                          if (_residentTaxCapability ==
                              ResidentTaxCapability.legacy)
                            _amountField(
                              'resident_tax_monthly',
                              SkoLanguageController.tr('住民税・月額'),
                            )
                          else if (_residentTaxCapability ==
                              ResidentTaxCapability.unknown) ...[
                            const Text(
                              '住民税の設定方式を確認できません。住民税は変更せず、他の給与設定を保存できます。',
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : _retryResidentTaxCapability,
                              child: const Text('再確認'),
                            ),
                          ] else if (_workerId != null)
                            ResidentTaxSection(
                              key: ValueKey('resident-tax-$_workerId'),
                              month: month,
                              onEditingChanged: onEditingChanged,
                              workerId: _workerId!,
                              companyId: _settingValues['company_id'] is String
                                  ? _settingValues['company_id'] as String
                                  : workspace.companyId,
                              canEdit: workspace.canEdit && !_saving,
                              legacyAmount:
                                  num.tryParse(
                                    _controllers['resident_tax_monthly']!.text,
                                  ) ??
                                  0,
                            ),
                                ],
                              ),
                            ),
                        ],
                        children: [
                          const SizedBox(height: 12),
                          _sectionTitle(SkoLanguageController.tr('その他の控除')),
                          for (var i = 0; i < _customDeductions.length; i++)
                            _customMoneyField(
                              _customDeductions,
                              i,
                              workspace.canEdit,
                              sectionName: '控除',
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle(SkoLanguageController.tr('会社共通の給料日')),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _companyPolicy == null
                          ? SkoLanguageController.tr('会社データで設定します')
                          : SkoLanguageController.trParams(
                              '{month}{day}払い・末締め',
                              {
                                'month': SkoLanguageController.tr(
                                  _companyPolicy!.paymentMonthOffset == 2
                                      ? '翌々月'
                                      : _companyPolicy!.paymentMonthOffset == 1
                                      ? '翌月'
                                      : '当月',
                                ),
                                'day': _companyPolicy!.paymentDay == 31
                                    ? SkoLanguageController.tr('末日')
                                    : SkoLanguageController.trParams('{day}日', {
                                        'day': _companyPolicy!.paymentDay,
                                      }),
                              },
                            ),
                    ),
                    subtitle: Text(
                      SkoLanguageController.tr('全社員共通。会社データの設定を使用します。'),
                    ),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PayrollConfirmationSettingsPage(),
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
                  Text(
                    SkoLanguageController.tr('承認済みの有給申請から使用日数と残日数を自動計算します。'),
                  ),
                  if (!_paidLeaveWagesAvailable)
                    Text(
                      SkoLanguageController.tr(
                        '有給額の自動計算はサーバー準備待ちです。現在の給与条件の警告を確認してください。',
                      ),
                    )
                  else ...[
                    if (_rateDraft?.payType == 'hourly' ||
                        (_rateDraft == null &&
                            _settingValues['pay_type'] == 'hourly'))
                      _amountField(
                        'paid_leave_daily_yen',
                        SkoLanguageController.tr('有給1日分（空欄は時給×8時間）'),
                      ),
                    Text(
                      SkoLanguageController.trParams('有給1日分：{amount}円', {
                        'amount': _currentPaidLeavePay().dailyAmountYen,
                      }),
                    ),
                    Text(
                      SkoLanguageController.tr(
                        '日給は登録日給。時給は初期値が時給×8時間で変更可能。月給は設定した1日分の内訳額で、月給に重ねて加算せず有給取得で月給を減額しません。',
                      ),
                    ),
                  ],
                  if (!_showDeductions && _earningUnit == PayrollItemUnit.day &&
                      (_rateDraft?.payType ?? _settingValues['pay_type'] ?? 'daily') == 'daily') ...[
                    const SizedBox(height: 12),
                    Card(child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SwitchListTile(
                          key: const ValueKey('position-transfer-enabled'),
                          title: const Text('役職手当振替'),
                          subtitle: const Text('役職手当と勤務手当を表示上の基本給へ振り替えます。'),
                          value: _positionTransferEnabled,
                          onChanged: workspace.canEdit && !_busy
                              ? (value) => setState(() => _positionTransferEnabled = value) : null,
                        ),
                        for (var i = 0; i < _positionTransferItems.length; i++)
                          Row(key: ValueKey('position-transfer-row-$i'), children: [
                            Expanded(child: TextField(controller: _positionTransferItems[i].name,
                              enabled: workspace.canEdit && !_busy && _positionTransferEnabled,
                              decoration: const InputDecoration(labelText: '項目名'))),
                            Expanded(child: TextField(controller: _positionTransferItems[i].amount,
                              enabled: workspace.canEdit && !_busy && _positionTransferEnabled,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: '月額', suffixText: '円'))),
                            IconButton(tooltip: '振替項目を削除',
                              onPressed: workspace.canEdit && !_busy && _positionTransferEnabled
                                ? () => _removeCustomMoney(_positionTransferItems, i) : null,
                              icon: const Icon(Icons.delete_outline)),
                          ]),
                        OutlinedButton.icon(key: const ValueKey('position-transfer-add'),
                          onPressed: workspace.canEdit && !_busy && _positionTransferEnabled
                            ? () => setState(() => _positionTransferItems.add(_CustomMoneyDraft())) : null,
                          icon: const Icon(Icons.add), label: const Text('項目を追加')),
                        const Text('支給に登録した項目と金額が一致する場合に振り替えます。'),
                        const Text('表示用日給は500円単位に四捨五入します。支給額・残業代は変わりません。'),
                      ]),
                    )),
                  ],
                  SizedBox(height: 12),
                ],
                ),
              ),
      ),
    ));
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _addedItemKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: 0.2,
        );
      }
    });
  }

  void _removeCustomMoney(List<_CustomMoneyDraft> items, int index) {
    final removed = items.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _includeLegacyMonthlyEarning(String key, String name) {
    final amount = int.parse(_controllers[key]!.text);
    if (amount > 0) {
      final index = _customEarnings.indexWhere(
        (item) => item.name.text.trim() == name,
      );
      if (index < 0) {
        _customEarnings.add(_CustomMoneyDraft(name: name, amountYen: amount));
      } else {
        final item = _customEarnings[index];
        item.amount.text = (int.parse(item.amount.text) + amount).toString();
      }
    }
    _controllers[key]!.text = '0';
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
      key:
          index == items.length - 1 &&
              identical(
                items,
                _showDeductions ? _customDeductions : _customEarnings,
              )
          ? _addedItemKey
          : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Align(alignment: Alignment.centerLeft,
              child: Text(SkoLanguageController.tr('個別手当（この社員だけ）'),
                style: Theme.of(context).textTheme.labelSmall)),
            TextFormField(
              controller: item.name,
              enabled: enabled,
              maxLength: 100,
              decoration: InputDecoration(
                labelText:
                    SkoLanguageController.trParams('{section}{number} 名称', {
                      'section': SkoLanguageController.tr(sectionName),
                      'number': index + 1,
                    }),
                border: OutlineInputBorder(),
              ),
            ),
            TextFormField(
              controller: item.amount,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    SkoLanguageController.trParams('{section}{number} 金額', {
                      'section': SkoLanguageController.tr(sectionName),
                      'number': index + 1,
                    }),
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
                  label: Text(
                    SkoLanguageController.trParams('この{section}を削除', {
                      'section': SkoLanguageController.tr(sectionName),
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAllowanceStateReload() async {
    final worker = _workerId;
    if (worker == null) return;
    final accepted = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(title: const Text('保存済みの状態を確認'),
        content: const Text('保存し直さず、保存済みの設定を読み直します。表示中の未保存入力は置き換わります。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('入力を保持')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存済みの状態を確認'))]));
    if (mounted && worker == _workerId && accepted == true) await _loadWorker(worker);
  }

  Future<void> _loadRegisteredAllowanceNames(String company, String worker, int generation) async {
    final source = _registeredAllowanceSource;
    if (source == null) return;
    try {
      final value = await source.read(company);
      if (!mounted || generation != _loadGeneration || _workerId != worker ||
          !_allowanceScopeCurrent() || value.companyId != company ||
          (_workspace?.companyId ?? _settingValues['company_id']) != company) {
        return;
      }
      setState(() { _registeredAllowanceNames = value; _registeredAllowanceReadFailed = false; });
    } catch (_) {
      if (mounted && generation == _loadGeneration && _workerId == worker) {
        setState(() { _registeredAllowanceNames = null; _registeredAllowanceReadFailed = true; });
      }
    }
  }

  List<PayrollRegisteredAllowanceName> get _registeredNameRows {
    if (!_allowanceScopeCurrent()) return const [];
    final type = _settingValues['pay_type']?.toString() ?? 'daily';
    return [for (final item in _registeredAllowanceNames?.items ?? <CompanyAllowanceLabel>[])
      if (item.payrollType == 'all' || item.payrollType == type)
        PayrollRegisteredAllowanceName(
          key: '${item.origin}/${item.id ?? item.legacySlot}', itemId: item.id,
          name: item.name, legacySlot: item.legacySlot,
          currentRateYen: item.currentRateYen, displayUnit: item.displayUnit,
          section: PayrollItemSection.values.byName(item.section),
          unit: PayrollItemUnit.values.byName(item.unit)),
    ];
  }

  Map<String, dynamic> get _individualAllowanceValues => {
    for (var slot = 1; slot <= 3; slot++) ...{
      'allowance_name_$slot': _controllers['allowance_name_$slot']!.text,
      'allowance_$slot': _controllers['allowance_$slot']!.text,
    },
  };

  void _rememberAllowanceDraft(List<PayrollUnitItemDraft> items) {
    // Preserve incomplete input too. Validation happens before either save.
    final rows = {for (final item in items)
      if (individualAllowanceSlot(item.id) != null)
        individualAllowanceSlot(item.id)!: item};
    for (var slot = 1; slot <= 3; slot++) {
      _controllers['allowance_name_$slot']!.text = rows[slot]?.name ?? '';
      _controllers['allowance_$slot']!.text = rows[slot]?.rate ?? '0';
    }
  }

  bool _allowanceScopeCurrent() => !_allowanceUsesLiveSession ||
      (_allowanceActorAtLoad != null &&
       SupabaseBackend.client.auth.currentUser?.id == _allowanceActorAtLoad);

  bool _individualAllowanceValuesChanged(Map<String, dynamic> values) =>
      values.entries.any((entry) {
        final previous = _settingValues[entry.key];
        return entry.key.startsWith('allowance_name_')
            ? (previous?.toString() ?? '') != entry.value
            : (previous as num? ?? 0) != entry.value;
      });

  Future<bool> _saveAllowanceRows(List<PayrollUnitItemDraft> items) async {
    final worker = _workerId;
    final company = _workspace?.companyId ?? _settingValues['company_id'];
    final generation = _loadGeneration;
    if (worker == null || company is! String || _repository == null ||
        _workspace?.canEdit != true || _allowanceSaveUncertain || !_allowanceScopeCurrent()) {
      throw StateError('手当の保存対象を確認できません');
    }
    final values = splitIndividualAllowanceRows(items).workerValues;
    final changed = _individualAllowanceValuesChanged(values);
    if (!changed) return false;
    await _repository.saveSetting(workerId: worker, values: values);
    if (!mounted || generation != _loadGeneration || _workerId != worker || !_allowanceScopeCurrent() ||
        (_workspace?.companyId ?? _settingValues['company_id']) != company) {
      throw StateError('手当の保存後に対象が変わりました');
    }
    setState(() => _settingValues = {..._settingValues, ...values});
    return true;
  }

  Future<void> _reloadAllowanceRows() async {
    final worker = _workerId;
    final generation = _loadGeneration;
    if (worker == null || _repository == null) throw StateError('社員を確認できません');
    final saved = await _repository.loadSetting(worker);
    final expectedCompany = _workspace?.companyId ?? _settingValues['company_id'];
    if (saved.values['company_id'] is String && saved.values['company_id'] != expectedCompany) {
      throw StateError('給与設定の会社が一致しません');
    }
    if (!mounted || generation != _loadGeneration || worker != _workerId || !_allowanceScopeCurrent()) {
      throw StateError('社員が変わりました');
    }
    for (var slot = 1; slot <= 3; slot++) {
      _controllers['allowance_name_$slot']!.text = saved.text('allowance_name_$slot');
      _controllers['allowance_$slot']!.text = saved.amount('allowance_$slot').toStringAsFixed(0);
    }
    _settingValues = {..._settingValues, ...{
      for (var slot = 1; slot <= 3; slot++) ...{
        'allowance_name_$slot': saved.text('allowance_name_$slot'),
        'allowance_$slot': saved.amount('allowance_$slot'),
      },
    }};
    setState(() {});
  }

  Widget _inlineUnitSettings(String title) {
    final worker = _workerId;
    final company = _workspace?.companyId ?? _settingValues['company_id'];
    Widget fallback() => title == '支給' && _earningUnit == PayrollItemUnit.day
        ? PayrollUnitItemEditor(
            key: ValueKey('individual-allowance-fallback-$worker-$_loadGeneration'),
            embedded: true, showFooter: false, allowAdding: false,
            showDailyReportOption: false,
            quantityExplanation: (_) => '退勤で選択した日数に応じて支給します',
            controller: _unitFooter, section: PayrollItemSection.earning,
            unit: PayrollItemUnit.day,
            initialItems: individualAllowanceRows(_individualAllowanceValues),
            canEdit: _workspace?.canEdit == true && !_saving,
            onDraftChanged: _rememberAllowanceDraft,
            onRegister: (_) => _save(registerUnitDrafts: false),
          ) : const SizedBox.shrink();
    if (worker == null || company is! String || _repository == null) {
      return fallback();
    }
    try {
      return PayrollUnitConditionsPage(
        key: _unitPanelKey,
        embedded: true,
        editorController: _unitFooter,
        // The host owns actions for every unit, including loading failures.
        externalFooter: true,
        repository: _repository.unitConditions,
        companyId: company, workerId: worker,
        section: title == '支給' ? PayrollItemSection.earning : PayrollItemSection.deduction,
        unit: title == '支給' ? _earningUnit : _deductionUnit,
        canEditIndividualAllowances: _workspace?.canEdit == true && !_saving,
        individualSaveUncertain: _allowanceSaveUncertain,
        registeredAllowanceNames: _registeredNameRows,
        registeredAllowanceNamesLoaded: _registeredAllowanceNames != null && _allowanceScopeCurrent(),
        onOpenCompanyCommonSettings: () async {
          if (!_allowanceScopeCurrent()) return;
          final generation = _loadGeneration;
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CompanyCommonAllowanceEntryPage(companyId: company)));
          if (!mounted || generation != _loadGeneration || _workerId != worker ||
              !_allowanceScopeCurrent() || (_workspace?.companyId ?? _settingValues['company_id']) != company) {
            return;
          }
          // Refresh names only. Do not replace unsaved worker/unit drafts.
          await _loadRegisteredAllowanceNames(company, worker, generation);
        },
        registeredAllowanceNamesUnavailable: _registeredAllowanceReadFailed,
        individualAllowanceItems: individualAllowanceRows(_individualAllowanceValues),
        onIndividualAllowanceDraftChanged: _rememberAllowanceDraft,
        onSaveIndividualAllowances: _saveAllowanceRows,
        individualAllowancesNeedSave: (items) =>
            _individualAllowanceValuesChanged(splitIndividualAllowanceRows(items).workerValues),
        onReloadIndividualAllowances: _reloadAllowanceRows,
        individualAllowanceScopeCurrent: _allowanceScopeCurrent,
        onIndividualSaveUncertain: (value) {
          if (mounted && _allowanceSaveUncertain != value) {
            setState(() => _allowanceSaveUncertain = value);
          }
        },
        onValidationSelection: (section, unit) => setState(() {
          _showDeductions = section == PayrollItemSection.deduction;
          if (_showDeductions) { _deductionUnit = unit; }
          else { _earningUnit = unit; }
        }),
      );
    } catch (_) {
      // Older servers retain editable registered rows without creating a new
      // unit-condition item or offering an unsupported extra save path.
      return fallback();
    }
  }

  Widget _moneySection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    List<Widget> leadingChildren = const [],
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(
        color: Theme.of(context).colorScheme.primary,
        width: 2,
      ),
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
            Text(
              SkoLanguageController.tr(title),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final unit in PayrollItemUnit.values)
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: (title == '支給' ? _earningUnit : _deductionUnit) == unit
                    ? Colors.blue.shade700 : null,
                  foregroundColor: (title == '支給' ? _earningUnit : _deductionUnit) == unit
                    ? Colors.white : null),
                onPressed: _busy ? null : () => setState(() {
                  if (title == '支給') { _earningUnit = unit; }
                  else { _deductionUnit = unit; }
                }),
                child: Text(SkoLanguageController.tr(switch (unit) {
                  PayrollItemUnit.hour => '時間単位',
                  PayrollItemUnit.day => '日単位',
                  PayrollItemUnit.month => '月単位',
                })),
              ))),
        ]),
        const Divider(height: 20),
        ...leadingChildren,
        Offstage(
          offstage: (title == '支給' ? _earningUnit : _deductionUnit) != PayrollItemUnit.month,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
        if ((title == '控除') == _showDeductions) _inlineUnitSettings(title),

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



