import 'package:flutter/material.dart';

import '../../domain/rate_formula_settings.dart';
import '../notifications/notification_bell.dart';
import 'admin_site_financial_repository.dart';

class AdminSiteFinancialPage extends StatefulWidget {
  const AdminSiteFinancialPage({super.key});

  @override
  State<AdminSiteFinancialPage> createState() =>
      _AdminSiteFinancialPageState();
}

class _AdminSiteFinancialPageState extends State<AdminSiteFinancialPage> {
  final _repository = AdminSiteFinancialRepository.maybeCreate();

  List<AdminSiteFinancialRecord> _items = const [];
  bool _loading = true;
  bool _canManage = false;
  String? _error;
  bool _showCompleted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '管理者用現場データを利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final values = await Future.wait([
        repository.loadAll(),
        repository.canManage(),
      ]);
      final items = values[0] as List<AdminSiteFinancialRecord>;
      final canManage = values[1] as bool;
      if (!mounted) return;
      setState(() {
        _items = items;
        _canManage = canManage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where((item) {
      final completed = item.status == 'completed';
      return _showCompleted ? completed : !completed;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '管理者用現場データ',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('登録中'),
                    icon: Icon(Icons.work_outline),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('完了'),
                    icon: Icon(Icons.task_alt),
                  ),
                ],
                selected: {_showCompleted},
                onSelectionChanged: (value) =>
                    setState(() => _showCompleted = value.first),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : visible.isEmpty
                          ? const Center(child: Text('該当する現場はありません'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 6, 12, 24),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = visible[index];
                                  return Card(
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        child: Icon(
                                          Icons.admin_panel_settings_outlined,
                                        ),
                                      ),
                                      title: Text(
                                        item.siteName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '請求方式 ${item.billingMethodLabel}',
                                      ),
                                      trailing: Icon(
                                        _canManage
                                            ? Icons.chevron_right
                                            : Icons.lock_outline,
                                      ),
                                      onTap:
                                          _canManage ? () => _edit(item) : null,
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(AdminSiteFinancialRecord record) async {
    final billing = TextEditingController(
      text: (record.billingFormulas.hourlyBase &&
              record.billingHourlyBaseYen > 0
          ? record.billingHourlyBaseYen
          : record.billingUnitPriceYen)
          .toString(),
    );
    final billingOverrides = _overrideControllers(
      record.billingRateOverrides,
      fallback: {
        'overtime': record.billingOvertimeHourRateYen,
        'early': record.billingEarlyHourRateYen,
      },
    );
    final billingFormula = _formulaControllers(record.billingFormulas);
    final monthly = TextEditingController(
      text: record.billingMonthlyRateYen.toString(),
    );
    final squareMeterUnitPrice = TextEditingController(
      text: record.billingSquareMeterUnitPriceYen.toString(),
    );
    final squareMeterQuantity = TextEditingController(
      text: _numberText(record.billingSquareMeterQuantity),
    );
    final contractAmount = TextEditingController(
      text: record.billingContractAmountYen.toString(),
    );
    final welfare = TextEditingController(
      text: record.welfareRate.toString(),
    );
    final allowance1Name = TextEditingController(
      text: record.billingAllowance1Name,
    );
    final allowance1Amount = TextEditingController(
      text: record.billingAllowance1AmountYen.toString(),
    );
    final allowance2Name = TextEditingController(
      text: record.billingAllowance2Name,
    );
    final allowance2Amount = TextEditingController(
      text: record.billingAllowance2AmountYen.toString(),
    );
    final allowance3Name = TextEditingController(
      text: record.billingAllowance3Name,
    );
    final allowance3Amount = TextEditingController(
      text: record.billingAllowance3AmountYen.toString(),
    );

    final saved = await showDialog<AdminSiteFinancialRecord>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(record.siteName),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '請求書用',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                _MoneyField(controller: billing, label: '1日単価'),
                const SizedBox(height: 8),
                _RateFormulaEditor(
                  title: '請求書用 自動計算',
                  baseController: billing,
                  overrideControllers: billingOverrides,
                  formulaControllers: billingFormula,
                ),
                const SizedBox(height: 10),
                _MoneyField(controller: monthly, label: '月単価'),
                const SizedBox(height: 10),
                _MoneyField(
                  controller: squareMeterUnitPrice,
                  label: '平米単価',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: squareMeterQuantity,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '平米数',
                  ),
                ),
                const SizedBox(height: 10),
                _MoneyField(
                  controller: contractAmount,
                  label: '請負金額',
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '1日単価・月単価・平米・請負のどれか1方式を設定します。日給/時給どちらでも同じ倍率体系で残業・早出・夜勤・休日系を自動計算し、式の数字も変更保存できます。平米は単価と平米数の両方が必要です。',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: welfare,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '法定福利費率（%）',
                  ),
                ),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '請求書用 手当',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: allowance1Name,
                  decoration: const InputDecoration(labelText: '手当1 名称'),
                ),
                const SizedBox(height: 8),
                _MoneyField(controller: allowance1Amount, label: '手当1 単価'),
                const SizedBox(height: 8),
                TextField(
                  controller: allowance2Name,
                  decoration: const InputDecoration(labelText: '手当2 名称'),
                ),
                const SizedBox(height: 8),
                _MoneyField(controller: allowance2Amount, label: '手当2 単価'),
                const SizedBox(height: 8),
                TextField(
                  controller: allowance3Name,
                  decoration: const InputDecoration(labelText: '手当3 名称'),
                ),
                const SizedBox(height: 8),
                _MoneyField(controller: allowance3Amount, label: '手当3 単価'),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '出勤データに同じ手当名が登録されている回数×この単価を請求書へ追加します。',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final billingFormulaValue =
                  _formulaFromControllers(billingFormula);
              final billingBaseInput = int.tryParse(billing.text) ?? 0;
              final manDay =
                  billingFormulaValue.dailyBase(billingBaseInput);
              final monthlyRate = int.tryParse(monthly.text) ?? 0;
              final squarePrice = int.tryParse(squareMeterUnitPrice.text) ?? 0;
              final squareQty = double.tryParse(squareMeterQuantity.text) ?? 0;
              final contract = int.tryParse(contractAmount.text) ?? 0;

              final squareHalfEntered =
                  (squarePrice > 0 && squareQty <= 0) ||
                  (squarePrice <= 0 && squareQty > 0);
              if (squareHalfEntered) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('平米単価と平米数は両方入力してください'),
                  ),
                );
                return;
              }

              final methodCount =
                  (manDay > 0 ? 1 : 0) +
                  (monthlyRate > 0 ? 1 : 0) +
                  (squarePrice > 0 && squareQty > 0 ? 1 : 0) +
                  (contract > 0 ? 1 : 0);
              if (methodCount > 1) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('請求方式は1日単価・月単価・平米・請負のどれか1つにしてください'),
                  ),
                );
                return;
              }

              Navigator.pop(
                dialogContext,
                AdminSiteFinancialRecord(
                  siteId: record.siteId,
                  siteName: record.siteName,
                  status: record.status,
                  workerDailyRateYen: record.workerDailyRateYen,
                  overtimeHourRateYen: record.overtimeHourRateYen,
                  earlyHourRateYen: record.earlyHourRateYen,
                  nightHourRateYen: record.nightHourRateYen,
                  billingUnitPriceYen: manDay,
                  billingOvertimeHourRateYen:
                      int.tryParse(billingOverrides['overtime']!.text) ?? 0,
                  billingEarlyHourRateYen:
                      int.tryParse(billingOverrides['early']!.text) ?? 0,
                  billingMonthlyRateYen: monthlyRate,
                  billingSquareMeterUnitPriceYen: squarePrice,
                  billingSquareMeterQuantity: squareQty,
                  billingContractAmountYen: contract,
                  welfareRate: double.tryParse(welfare.text) ?? 0,
                  billingAllowance1Name: allowance1Name.text,
                  billingAllowance1AmountYen:
                      int.tryParse(allowance1Amount.text) ?? 0,
                  billingAllowance2Name: allowance2Name.text,
                  billingAllowance2AmountYen:
                      int.tryParse(allowance2Amount.text) ?? 0,
                  billingAllowance3Name: allowance3Name.text,
                  billingAllowance3AmountYen:
                      int.tryParse(allowance3Amount.text) ?? 0,
                  workerFormulas: record.workerFormulas,
                  billingFormulas: billingFormulaValue,
                  workerHourlyBaseYen: record.workerHourlyBaseYen,
                  billingHourlyBaseYen:
                      billingFormulaValue.hourlyBase ? billingBaseInput : 0,
                  workerRateOverrides: record.workerRateOverrides,
                  billingRateOverrides:
                      _overridesFromControllers(billingOverrides),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    for (final controller in [
      billing,
      ...billingOverrides.values,
      ...billingFormula.values,
      monthly,
      squareMeterUnitPrice,
      squareMeterQuantity,
      contractAmount,
      welfare,
      allowance1Name,
      allowance1Amount,
      allowance2Name,
      allowance2Amount,
      allowance3Name,
      allowance3Amount,
    ]) {
      controller.dispose();
    }

    if (saved == null) return;

    try {
      await _repository?.save(saved);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者用現場データを保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    }
  }

  static Map<String, TextEditingController> _overrideControllers(
    Map<String, int> values, {
    required Map<String, int> fallback,
  }) =>
      {
        for (final key in const [
          'overtime',
          'early',
          'night',
          'night_overtime',
          'holiday',
          'holiday_overtime',
          'holiday_night',
          'holiday_night_overtime',
        ])
          key: TextEditingController(
            text: (values[key] ?? fallback[key] ?? 0).toString(),
          ),
      };

  static Map<String, TextEditingController> _formulaControllers(
    RateFormulaSettings value,
  ) =>
      {
        'hourly_base': TextEditingController(text: value.hourlyBase ? '1' : '0'),
        'hours': TextEditingController(text: _numberText(value.hoursPerDay)),
        'overtime': TextEditingController(
          text: _numberText(value.overtimeMultiplier),
        ),
        'early': TextEditingController(
          text: _numberText(value.earlyMultiplier),
        ),
        'night': TextEditingController(
          text: _numberText(value.nightMultiplier),
        ),
        'night_overtime': TextEditingController(
          text: _numberText(value.nightOvertimeMultiplier),
        ),
        'holiday': TextEditingController(
          text: _numberText(value.holidayMultiplier),
        ),
        'holiday_overtime': TextEditingController(
          text: _numberText(value.holidayOvertimeMultiplier),
        ),
        'holiday_night': TextEditingController(
          text: _numberText(value.holidayNightMultiplier),
        ),
        'holiday_night_overtime': TextEditingController(
          text: _numberText(value.holidayNightOvertimeMultiplier),
        ),
      };

  static RateFormulaSettings _formulaFromControllers(
    Map<String, TextEditingController> values,
  ) =>
      RateFormulaSettings(
        hourlyBase: values['hourly_base']?.text == '1',
        hoursPerDay: double.tryParse(values['hours']!.text) ?? 8,
        overtimeMultiplier:
            double.tryParse(values['overtime']!.text) ?? 1.25,
        earlyMultiplier: double.tryParse(values['early']!.text) ?? 1.25,
        nightMultiplier: double.tryParse(values['night']!.text) ?? 1.5,
        nightOvertimeMultiplier:
            double.tryParse(values['night_overtime']!.text) ?? 1.25,
        holidayMultiplier:
            double.tryParse(values['holiday']!.text) ?? 1.35,
        holidayOvertimeMultiplier:
            double.tryParse(values['holiday_overtime']!.text) ?? 1.25,
        holidayNightMultiplier:
            double.tryParse(values['holiday_night']!.text) ?? 1.6,
        holidayNightOvertimeMultiplier:
            double.tryParse(values['holiday_night_overtime']!.text) ?? 1.25,
      );

  static Map<String, int> _overridesFromControllers(
    Map<String, TextEditingController> values,
  ) =>
      {
        for (final entry in values.entries)
          entry.key: int.tryParse(entry.value.text.trim()) ?? 0,
      };

  static String _yen(int value) => '¥$value';

  static String _numberText(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _RateFormulaEditor extends StatefulWidget {
  const _RateFormulaEditor({
    required this.title,
    required this.baseController,
    required this.overrideControllers,
    required this.formulaControllers,
  });

  final String title;
  final TextEditingController baseController;
  final Map<String, TextEditingController> overrideControllers;
  final Map<String, TextEditingController> formulaControllers;

  @override
  State<_RateFormulaEditor> createState() => _RateFormulaEditorState();
}

class _RateFormulaEditorState extends State<_RateFormulaEditor> {
  late bool _hourlyBase;

  @override
  void initState() {
    super.initState();
    _hourlyBase = widget.formulaControllers['hourly_base']?.text == '1';
    for (final controller in [
      widget.baseController,
      ...widget.overrideControllers.values,
      ...widget.formulaControllers.values,
    ]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      widget.baseController,
      ...widget.overrideControllers.values,
      ...widget.formulaControllers.values,
    ]) {
      controller.removeListener(_refresh);
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  RateFormulaSettings get _formula =>
      _AdminSiteFinancialPageState._formulaFromControllers(
        widget.formulaControllers,
      );

  int get _base => int.tryParse(widget.baseController.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final formula = _formula;
    final items = <(String, String, int, String)>[
      (
        'overtime',
        '残業',
        formula.overtime(_base, hourlyBase: _hourlyBase),
        formula.overtimeFormula(_base, hourlyBase: _hourlyBase),
      ),
      (
        'early',
        '早出',
        formula.early(_base, hourlyBase: _hourlyBase),
        formula.earlyFormula(_base, hourlyBase: _hourlyBase),
      ),
      (
        'night',
        '夜勤',
        formula.night(_base, hourlyBase: _hourlyBase),
        formula.nightFormula(_base, hourlyBase: _hourlyBase),
      ),
      (
        'night_overtime',
        '夜勤残業',
        formula.nightOvertime(_base, hourlyBase: _hourlyBase),
        formula.nightOvertimeFormula(_base, hourlyBase: _hourlyBase),
      ),
      (
        'holiday',
        '休日出勤',
        formula.holiday(_base, hourlyBase: _hourlyBase),
        formula.holidayFormula(_base, hourlyBase: _hourlyBase),
      ),
      (
        'holiday_overtime',
        '休日残業',
        formula.holidayOvertime(_base, hourlyBase: _hourlyBase),
        formula.holidayOvertimeFormula(_base, hourlyBase: _hourlyBase),
      ),
      (
        'holiday_night',
        '休日夜勤',
        formula.holidayNight(_base, hourlyBase: _hourlyBase),
        formula.holidayNightFormula(_base, hourlyBase: _hourlyBase),
      ),
      (
        'holiday_night_overtime',
        '休日夜勤残業',
        formula.holidayNightOvertime(_base, hourlyBase: _hourlyBase),
        formula.holidayNightOvertimeFormula(
          _base,
          hourlyBase: _hourlyBase,
        ),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('日給')),
                ButtonSegment(value: true, label: Text('時給')),
              ],
              selected: {_hourlyBase},
              onSelectionChanged: (value) {
                final hourly = value.first;
                widget.formulaControllers['hourly_base']!.text =
                    hourly ? '1' : '0';
                setState(() => _hourlyBase = hourly);
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _factor(widget.formulaControllers['hours']!, '1日時間'),
                _factor(widget.formulaControllers['overtime']!, '残業倍率'),
                _factor(widget.formulaControllers['early']!, '早出倍率'),
                _factor(widget.formulaControllers['night']!, '夜勤倍率'),
                _factor(
                  widget.formulaControllers['night_overtime']!,
                  '夜勤残業倍率',
                ),
                _factor(widget.formulaControllers['holiday']!, '休日倍率'),
                _factor(
                  widget.formulaControllers['holiday_overtime']!,
                  '休日残業倍率',
                ),
                _factor(
                  widget.formulaControllers['holiday_night']!,
                  '休日夜勤倍率',
                ),
                _factor(
                  widget.formulaControllers['holiday_night_overtime']!,
                  '休日夜勤残業倍率',
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in items)
              _rateRow(
                keyName: item.$1,
                label: item.$2,
                calculated: item.$3,
                formula: item.$4,
              ),
          ],
        ),
      ),
    );
  }

  Widget _factor(TextEditingController controller, String label) =>
      SizedBox(
        width: 135,
        child: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _rateRow({
    required String keyName,
    required String label,
    required int calculated,
    required String formula,
  }) {
    final controller = widget.overrideControllers[keyName]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '$label 直接入力',
              suffixText: '円',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '自動 ¥$calculated　式: $formula　'
            '（0なら自動 / 1円以上なら直接入力優先）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
