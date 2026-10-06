
import 'package:flutter/material.dart';

import '../domain/rate_formula.dart';

class RateCalculationDraft {
  const RateCalculationDraft({
    required this.baseRateYen,
    required this.formula,
    required this.overrides,
    required this.calculated,
  });

  final int baseRateYen;
  final RateFormulaConfig formula;
  final Map<String, int> overrides;
  final CalculatedRates calculated;

  int effective(String key) {
    final override = overrides[key] ?? 0;
    if (override > 0) return override;
    return switch (key) {
      'overtime' => calculated.overtime,
      'early' => calculated.early,
      'night' => calculated.nightDay,
      'night_overtime' => calculated.nightOvertime,
      'holiday' => calculated.holidayDay,
      'holiday_overtime' => calculated.holidayOvertime,
      'holiday_night' => calculated.holidayNightDay,
      'holiday_night_overtime' => calculated.holidayNightOvertime,
      _ => 0,
    };
  }

  Map<String, Object> formulaJson() => {
        ...formula.toJson(),
        'hourly_rate_yen':
            formula.baseMode == RateBaseMode.hourly ? baseRateYen : 0,
      };
}

class RateCalculationCard extends StatefulWidget {
  const RateCalculationCard({
    super.key,
    required this.title,
    required this.initialBaseRateYen,
    required this.initialFormula,
    required this.initialOverrides,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final int initialBaseRateYen;
  final Object? initialFormula;
  final Object? initialOverrides;
  final bool enabled;
  final ValueChanged<RateCalculationDraft> onChanged;

  @override
  State<RateCalculationCard> createState() => _RateCalculationCardState();
}

class _RateCalculationCardState extends State<RateCalculationCard> {
  static const rows = <(String, String)>[
    ('overtime', '残業'),
    ('early', '早出'),
    ('night', '夜勤'),
    ('night_overtime', '夜勤残業'),
    ('holiday', '休日出勤'),
    ('holiday_overtime', '休日残業'),
    ('holiday_night', '休日夜勤'),
    ('holiday_night_overtime', '休日夜勤残業'),
  ];

  late RateBaseMode mode;
  late final TextEditingController base;
  late final Map<String, TextEditingController> factors;
  late final Map<String, TextEditingController> overrides;

  @override
  void initState() {
    super.initState();
    final formula = RateFormulaConfig.fromJson(widget.initialFormula);
    mode = formula.baseMode;
    final formulaMap = widget.initialFormula is Map
        ? Map<String, dynamic>.from(widget.initialFormula as Map)
        : const <String, dynamic>{};
    final hourly = (formulaMap['hourly_rate_yen'] as num?)?.toInt() ?? 0;
    base = TextEditingController(
      text: (mode == RateBaseMode.hourly && hourly > 0
              ? hourly
              : widget.initialBaseRateYen)
          .toString(),
    );
    factors = {
      'hours_per_day': TextEditingController(text: number(formula.hoursPerDay)),
      'overtime_multiplier':
          TextEditingController(text: number(formula.overtimeMultiplier)),
      'early_multiplier':
          TextEditingController(text: number(formula.earlyMultiplier)),
      'night_multiplier':
          TextEditingController(text: number(formula.nightMultiplier)),
      'night_overtime_multiplier':
          TextEditingController(text: number(formula.nightOvertimeMultiplier)),
      'holiday_multiplier':
          TextEditingController(text: number(formula.holidayMultiplier)),
      'holiday_overtime_multiplier':
          TextEditingController(text: number(formula.holidayOvertimeMultiplier)),
      'holiday_night_multiplier':
          TextEditingController(text: number(formula.holidayNightMultiplier)),
      'holiday_night_overtime_multiplier':
          TextEditingController(text: number(formula.holidayNightOvertimeMultiplier)),
    };
    final overrideMap = widget.initialOverrides is Map
        ? Map<String, dynamic>.from(widget.initialOverrides as Map)
        : const <String, dynamic>{};
    overrides = {
      for (final row in rows)
        row.$1: TextEditingController(
          text: ((overrideMap[row.$1] as num?)?.toInt() ?? 0).toString(),
        ),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => emit());
  }

  @override
  void dispose() {
    base.dispose();
    for (final controller in [...factors.values, ...overrides.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  RateFormulaConfig currentFormula() => RateFormulaConfig(
        baseMode: mode,
        hoursPerDay: factor('hours_per_day', 8).clamp(0.01, 24),
        overtimeMultiplier: factor('overtime_multiplier', 1.25),
        earlyMultiplier: factor('early_multiplier', 1.25),
        nightMultiplier: factor('night_multiplier', 1.5),
        nightOvertimeMultiplier: factor('night_overtime_multiplier', 1.25),
        holidayMultiplier: factor('holiday_multiplier', 1.35),
        holidayOvertimeMultiplier: factor('holiday_overtime_multiplier', 1.25),
        holidayNightMultiplier: factor('holiday_night_multiplier', 1.6),
        holidayNightOvertimeMultiplier:
            factor('holiday_night_overtime_multiplier', 1.25),
      );

  double factor(String key, double fallback) =>
      double.tryParse(factors[key]?.text.trim() ?? '') ?? fallback;

  RateCalculationDraft draft() {
    final baseRate = int.tryParse(base.text.trim()) ?? 0;
    final formula = currentFormula();
    return RateCalculationDraft(
      baseRateYen: baseRate,
      formula: formula,
      overrides: {
        for (final row in rows)
          row.$1: int.tryParse(overrides[row.$1]!.text.trim()) ?? 0,
      },
      calculated: calculateRates(baseRateYen: baseRate, formula: formula),
    );
  }

  void emit() {
    if (!mounted) return;
    widget.onChanged(draft());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = draft();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            SegmentedButton<RateBaseMode>(
              segments: const [
                ButtonSegment(value: RateBaseMode.daily, label: Text('日額')),
                ButtonSegment(value: RateBaseMode.hourly, label: Text('時給')),
              ],
              selected: {mode},
              onSelectionChanged: widget.enabled
                  ? (values) {
                      mode = values.first;
                      emit();
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: base,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              onChanged: (_) => emit(),
              decoration: InputDecoration(
                labelText: mode == RateBaseMode.hourly ? '基準時給' : '1日単価',
                suffixText: '円',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                '計算式を変更',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('数字は保存可能。直接単価を入れた項目は直接入力を優先します。'),
              children: [
                factorField('hours_per_day', '1日あたり時間'),
                factorField('overtime_multiplier', '残業倍率'),
                factorField('early_multiplier', '早出倍率'),
                factorField('night_multiplier', '夜勤倍率'),
                factorField('night_overtime_multiplier', '夜勤残業倍率'),
                factorField('holiday_multiplier', '休日出勤倍率'),
                factorField('holiday_overtime_multiplier', '休日残業倍率'),
                factorField('holiday_night_multiplier', '休日夜勤倍率'),
                factorField(
                  'holiday_night_overtime_multiplier',
                  '休日夜勤残業倍率',
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              rateField(row.$1, row.$2, value),
          ],
        ),
      ),
    );
  }

  Widget factorField(String key, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: factors[key],
          enabled: widget.enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => emit(),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget rateField(
    String key,
    String label,
    RateCalculationDraft value,
  ) {
    final auto = switch (key) {
      'overtime' => value.calculated.overtime,
      'early' => value.calculated.early,
      'night' => value.calculated.nightDay,
      'night_overtime' => value.calculated.nightOvertime,
      'holiday' => value.calculated.holidayDay,
      'holiday_overtime' => value.calculated.holidayOvertime,
      'holiday_night' => value.calculated.holidayNightDay,
      'holiday_night_overtime' => value.calculated.holidayNightOvertime,
      _ => 0,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: overrides[key],
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        onChanged: (_) => emit(),
        decoration: InputDecoration(
          labelText: label + ' 単価（0=自動）',
          suffixText: '円',
          helperText: rateFormulaLabel(
                kind: key,
                baseRateYen: value.baseRateYen,
                formula: value.formula,
              ) +
              ' → 自動 ¥' +
              auto.toString(),
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  static String number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
