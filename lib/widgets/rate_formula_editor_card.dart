
import 'package:flutter/material.dart';

import '../domain/rate_formula_settings.dart';

class RateFormulaDraft {
  const RateFormulaDraft({
    required this.baseRateYen,
    required this.formula,
    required this.overrides,
  });

  final int baseRateYen;
  final RateFormulaSettings formula;
  final Map<String, int> overrides;

  int effective(String key) {
    final direct = overrides[key] ?? 0;
    if (direct > 0) return direct;
    return switch (key) {
      'overtime' => formula.overtime(baseRateYen),
      'early' => formula.early(baseRateYen),
      'night' => formula.night(baseRateYen),
      'night_overtime' => formula.nightOvertime(baseRateYen),
      'holiday' => formula.holiday(baseRateYen),
      'holiday_overtime' => formula.holidayOvertime(baseRateYen),
      'holiday_night' => formula.holidayNight(baseRateYen),
      'holiday_night_overtime' =>
        formula.holidayNightOvertime(baseRateYen),
      _ => 0,
    };
  }
}

class RateFormulaEditorCard extends StatefulWidget {
  const RateFormulaEditorCard({
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
  final ValueChanged<RateFormulaDraft> onChanged;

  @override
  State<RateFormulaEditorCard> createState() => _RateFormulaEditorCardState();
}

class _RateFormulaEditorCardState extends State<RateFormulaEditorCard> {
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

  late bool _hourlyBase;
  late final TextEditingController _base;
  late final Map<String, TextEditingController> _formula;
  late final Map<String, TextEditingController> _overrides;

  @override
  void initState() {
    super.initState();
    final formula = RateFormulaSettings.fromMap(widget.initialFormula);
    _hourlyBase = formula.hourlyBase;
    final rawFormula = widget.initialFormula is Map
        ? Map<String, dynamic>.from(widget.initialFormula as Map)
        : const <String, dynamic>{};
    final hourly = (rawFormula['hourly_rate_yen'] as num?)?.toInt() ?? 0;
    _base = TextEditingController(
      text: (_hourlyBase && hourly > 0 ? hourly : widget.initialBaseRateYen)
          .toString(),
    );
    _formula = {
      'hours': TextEditingController(text: _num(formula.hoursPerDay)),
      'overtime':
          TextEditingController(text: _num(formula.overtimeMultiplier)),
      'early': TextEditingController(text: _num(formula.earlyMultiplier)),
      'night': TextEditingController(text: _num(formula.nightMultiplier)),
      'night_overtime':
          TextEditingController(text: _num(formula.nightOvertimeMultiplier)),
      'holiday':
          TextEditingController(text: _num(formula.holidayMultiplier)),
      'holiday_overtime':
          TextEditingController(text: _num(formula.holidayOvertimeMultiplier)),
      'holiday_night':
          TextEditingController(text: _num(formula.holidayNightMultiplier)),
      'holiday_night_overtime': TextEditingController(
        text: _num(formula.holidayNightOvertimeMultiplier),
      ),
    };
    final rawOverrides = widget.initialOverrides is Map
        ? Map<String, dynamic>.from(widget.initialOverrides as Map)
        : const <String, dynamic>{};
    _overrides = {
      for (final row in rows)
        row.$1: TextEditingController(
          text: ((rawOverrides[row.$1] as num?)?.toInt() ?? 0).toString(),
        ),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _base.dispose();
    for (final c in [..._formula.values, ..._overrides.values]) {
      c.dispose();
    }
    super.dispose();
  }

  RateFormulaSettings get currentFormula => RateFormulaSettings(
        hourlyBase: _hourlyBase,
        hoursPerDay: _double('hours', 8),
        overtimeMultiplier: _double('overtime', 1.25),
        earlyMultiplier: _double('early', 1.25),
        nightMultiplier: _double('night', 1.5),
        nightOvertimeMultiplier: _double('night_overtime', 1.25),
        holidayMultiplier: _double('holiday', 1.35),
        holidayOvertimeMultiplier: _double('holiday_overtime', 1.25),
        holidayNightMultiplier: _double('holiday_night', 1.6),
        holidayNightOvertimeMultiplier:
            _double('holiday_night_overtime', 1.25),
      );

  double _double(String key, double fallback) =>
      double.tryParse(_formula[key]?.text.trim() ?? '') ?? fallback;

  RateFormulaDraft get draft => RateFormulaDraft(
        baseRateYen: int.tryParse(_base.text.trim()) ?? 0,
        formula: currentFormula,
        overrides: {
          for (final row in rows)
            row.$1: int.tryParse(_overrides[row.$1]!.text.trim()) ?? 0,
        },
      );

  void _emit() {
    if (!mounted) return;
    widget.onChanged(draft);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = draft;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('日給')),
                ButtonSegment(value: true, label: Text('時給')),
              ],
              selected: {_hourlyBase},
              onSelectionChanged: widget.enabled
                  ? (values) {
                      _hourlyBase = values.first;
                      _emit();
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _base,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              onChanged: (_) => _emit(),
              decoration: InputDecoration(
                labelText: _hourlyBase ? '基準時給' : '1日単価',
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
              subtitle: const Text('式の数字は保存できます。0円の単価は自動計算を使用します。'),
              children: [
                _factor('hours', '1日時間'),
                _factor('overtime', '残業倍率'),
                _factor('early', '早出倍率'),
                _factor('night', '夜勤倍率'),
                _factor('night_overtime', '夜勤残業倍率'),
                _factor('holiday', '休日出勤倍率'),
                _factor('holiday_overtime', '休日残業倍率'),
                _factor('holiday_night', '休日夜勤倍率'),
                _factor('holiday_night_overtime', '休日夜勤残業倍率'),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in rows) _rateRow(row.$1, row.$2, value),
          ],
        ),
      ),
    );
  }

  Widget _factor(String key, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: _formula[key],
          enabled: widget.enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _emit(),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _rateRow(String key, String label, RateFormulaDraft value) {
    final auto = switch (key) {
      'overtime' => value.formula.overtime(value.baseRateYen),
      'early' => value.formula.early(value.baseRateYen),
      'night' => value.formula.night(value.baseRateYen),
      'night_overtime' => value.formula.nightOvertime(value.baseRateYen),
      'holiday' => value.formula.holiday(value.baseRateYen),
      'holiday_overtime' => value.formula.holidayOvertime(value.baseRateYen),
      'holiday_night' => value.formula.holidayNight(value.baseRateYen),
      'holiday_night_overtime' =>
        value.formula.holidayNightOvertime(value.baseRateYen),
      _ => 0,
    };
    final formula = switch (key) {
      'overtime' => value.formula.overtimeFormula(value.baseRateYen),
      'early' => value.formula.earlyFormula(value.baseRateYen),
      'night' => value.formula.nightFormula(value.baseRateYen),
      'night_overtime' =>
        value.formula.nightOvertimeFormula(value.baseRateYen),
      'holiday' => value.formula.holidayFormula(value.baseRateYen),
      'holiday_overtime' =>
        value.formula.holidayOvertimeFormula(value.baseRateYen),
      'holiday_night' =>
        value.formula.holidayNightFormula(value.baseRateYen),
      'holiday_night_overtime' =>
        value.formula.holidayNightOvertimeFormula(value.baseRateYen),
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _overrides[key],
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        onChanged: (_) => _emit(),
        decoration: InputDecoration(
          labelText: label + ' 直接入力',
          suffixText: '円',
          helperText: '自動 ¥' + auto.toString() + '　式: ' + formula +
              '（0なら自動 / 1円以上なら直接入力優先）',
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  static String _num(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}
