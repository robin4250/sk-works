import 'package:flutter/material.dart';

import '../../international/language_controller.dart';

enum PayrollItemSection { earning, deduction }

enum PayrollItemUnit { hour, day, month }

/// An editing value only. The storage adapter belongs to the payroll contract.
/// This type intentionally has no JSON conversion or amount calculation.
@immutable
class PayrollUnitItemDraft {
  const PayrollUnitItemDraft({
    required this.id,
    required this.section,
    required this.unit,
    this.name = '',
    this.rate = '',
    this.showInDailyReport = false,
    this.source = 'manual_hours',
    this.quantity = '',
  });

  final String id;
  final PayrollItemSection section;
  final PayrollItemUnit unit;
  final String name;
  final String rate;
  final bool showInDailyReport;
  final String source;
  final String quantity;
}

/// Read-only current company name. It never becomes an individual payable row.
@immutable
class PayrollRegisteredAllowanceName {
  const PayrollRegisteredAllowanceName({required this.key, required this.name,
    required this.section, required this.unit, this.legacySlot, this.itemId});
  final String key, name;
  final String? itemId;
  final int? legacySlot;
  final PayrollItemSection section;
  final PayrollItemUnit unit;
}

/// Routes a host footer to the mounted editor; never owns payroll data or saves.
class PayrollUnitEditorController extends ChangeNotifier {
  _PayrollUnitItemEditorState? _editor;
  bool _disposed = false;
  bool _scheduled = false;
  bool get canAdd => _editor?.mounted == true && _editor!._editable && _editor!.widget.allowAdding;
  bool get canRegister => _editor?.mounted == true && _editor!._editable && _editor!.widget.onRegister != null;
  bool get saving => _editor?._saving ?? false;
  void add() { if (canAdd) _editor!._add(); }
  Future<void> register() async { if (canRegister) await _editor!._register(); }
  bool validate() => _editor?.mounted == true ? _editor!._validate() : true;
  /// Capture validated values before the host saves other fields. The returned
  /// operation cannot read later keystrokes or run after its editor is removed.
  Future<bool> Function()? prepareRegistration() {
    final editor = _editor;
    if (!canRegister || editor == null || !editor._validate()) return null;
    final values = List<PayrollUnitItemDraft>.unmodifiable(
        editor._rows.map((row) => row.snapshot()));
    return () => editor._registerValues(values, prepared: true);
  }
  void invalidate() { _editor = null; _changed(); }
  void _attach(_PayrollUnitItemEditorState editor) {
    if (identical(_editor, editor)) return;
    _editor = editor; _changed();
  }
  void _detach(_PayrollUnitItemEditorState editor) {
    if (identical(_editor, editor)) invalidate();
  }
  void _changed() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    // Child lifecycle/build updates must not mark the parent footer dirty in build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }
  @override
  void dispose() { _disposed = true; _editor = null; super.dispose(); }
}

/// Unit-aware editor used by the saved payroll conditions page.
class PayrollUnitItemEditor extends StatefulWidget {
  const PayrollUnitItemEditor({
    super.key,
    required this.initialItems,
    required this.canEdit,
    this.onRegister,
    this.enableQuantitySources = false,
    this.showDailyReportOption = true,
    this.embedded = false,
    this.section,
    this.unit,
    this.onValidationSelection,
    this.controller,
    this.showFooter = true,
    this.onDraftChanged,
    this.allowAdding = true,
    this.quantityExplanation,
    this.registeredNames = const [],
    this.registeredNameHints = const {},
  });

  final List<PayrollUnitItemDraft> initialItems;
  final bool canEdit;
  final bool embedded;
  final PayrollUnitEditorController? controller;
  final bool showFooter;
  final bool allowAdding;
  final String? Function(PayrollUnitItemDraft)? quantityExplanation;
  final List<PayrollRegisteredAllowanceName> registeredNames;
  final Map<String, String> registeredNameHints;
  final ValueChanged<List<PayrollUnitItemDraft>>? onDraftChanged;
  final PayrollItemSection? section;
  final PayrollItemUnit? unit;
  final void Function(PayrollItemSection, PayrollItemUnit)? onValidationSelection;
  final bool enableQuantitySources;
  final bool showDailyReportOption;
  final Future<void> Function(List<PayrollUnitItemDraft> items)? onRegister;

  @override
  State<PayrollUnitItemEditor> createState() => _PayrollUnitItemEditorState();
}

class _PayrollUnitItemEditorState extends State<PayrollUnitItemEditor> {
  late final List<_RowDraft> _rows;
  final _scroll = ScrollController();
  final _retired = <_RowDraft>[];
  var _section = PayrollItemSection.earning;
  var _unit = PayrollItemUnit.hour;
  var _nextId = 0;
  var _saving = false;
  String? _error;

  bool get _editable => widget.canEdit && !_saving;

  @override
  void initState() {
    super.initState();
    assert(
      widget.initialItems.map((item) => item.id).toSet().length ==
          widget.initialItems.length,
    );
    _section = widget.section ?? _section;
    _unit = widget.unit ?? _unit;
    _rows = widget.initialItems.map(_RowDraft.new).toList();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant PayrollUnitItemEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) oldWidget.controller?._detach(this);
    widget.controller?._attach(this);
    if (oldWidget.canEdit != widget.canEdit || oldWidget.allowAdding != widget.allowAdding) widget.controller?._changed();
    _section = widget.section ?? _section;
    _unit = widget.unit ?? _unit;
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    for (final row in [..._rows, ..._retired]) {
      row.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _notifyDraft() => widget.onDraftChanged?.call(
      List.unmodifiable(_rows.map((row) => row.snapshot())));

  void _add() {
    if (!_editable || !widget.allowAdding) return;
    String id;
    do {
      id = 'new-unit-item-${_nextId++}';
    } while (_rows.any((row) => row.value.id == id));
    final row = _RowDraft(
      PayrollUnitItemDraft(id: id, section: _section, unit: _unit),
    );
    setState(() => _rows.add(row));
    _notifyDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_rows.contains(row)) return;
      final rowContext = row.key.currentContext;
      if (widget.embedded && rowContext != null) {
        Scrollable.ensureVisible(rowContext, alignment: .15);
      } else if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
      row.focus.requestFocus();
    });
  }

  bool _validate() {
    final seen = <String>{};
    for (final row in _rows) {
      final name = row.name.text.trim();
      final rate = int.tryParse(row.rate.text.trim());
      String? error;
      if (name.isEmpty) {
        error = '項目名を入力してください';
      } else if (name.length > 100) {
        error = '項目名は100文字以内で入力してください';
      } else if (rate == null || rate < 0 || rate > 2147483647) {
        error = '単価は0以上の整数で入力してください';
      } else if (!seen.add(
        '${row.value.section.name}/${row.value.unit.name}/$name',
      )) {
        error = '同じ単位の項目名が重複しています';
      }
      if (widget.enableQuantitySources &&
          row.value.unit == PayrollItemUnit.hour &&
          row.source == 'manual_hours' &&
          (!RegExp(r'^\d+(?:\.\d{1,4})?$').hasMatch(row.quantity.text.trim()) ||
              (num.tryParse(row.quantity.text.trim()) ?? 999999100) > 99999999)) {
        error = '対象月の時間数を入力してください';
      }
      if (error != null) {
        setState(() {
          _section = row.value.section;
          _unit = row.value.unit;
          _error = error;
        });
        widget.onValidationSelection?.call(row.value.section, row.value.unit);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final context = row.key.currentContext;
          if (context != null) Scrollable.ensureVisible(context);
          row.focus.requestFocus();
        });
        return false;
      }
    }
    return true;
  }

  Future<void> _register() async {
    if (!_editable || widget.onRegister == null || !_validate()) return;
    await _registerValues(List.unmodifiable(_rows.map((row) => row.snapshot())));
  }

  Future<bool> _registerValues(List<PayrollUnitItemDraft> values, {bool prepared = false}) async {
    if (!mounted || _saving || widget.onRegister == null || (!prepared && !_editable)) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.controller?._changed();
    try {
      await widget.onRegister!(values);
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = '登録できませんでした。入力内容を保持しています');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.controller?._changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    String tr(String text) => SkoLanguageController.tr(text);
    final visible = _rows
        .where(
          (row) => row.value.section == _section && row.value.unit == _unit,
        )
        .toList();
    return Column(
      mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (widget.section == null || widget.unit == null) Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (widget.section == null) Row(
                children: [
                  for (final section in PayrollItemSection.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _tab(
                          section == PayrollItemSection.earning ? '支給' : '控除',
                          section == _section,
                          () => setState(() => _section = section),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.unit == null) Row(
                children: [
                  for (final unit in PayrollItemUnit.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _tab(
                          _unitLabel(unit),
                          unit == _unit,
                          () => setState(() => _unit = unit),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              tr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Flexible(
          fit: widget.embedded ? FlexFit.loose : FlexFit.tight,
          child: ListView(
            shrinkWrap: widget.embedded,
            physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              for (final item in widget.registeredNames.where((item) =>
                  item.section == _section && item.unit == _unit))
                Card(key: ValueKey('company-registered-${item.key}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(title: Text(item.name),
                    subtitle: Text(tr('会社共通で登録した手当')),
                    trailing: const Icon(Icons.business_outlined))),
              if (visible.isEmpty && !widget.registeredNames.any((item) =>
                  item.section == _section && item.unit == _unit))
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('項目はありません'), textAlign: TextAlign.center),
                ),
              for (final row in visible)
                Card(
                  key: row.key,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: .12)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(children: [
                          CircleAvatar(radius: 17,
                            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
                            child: Icon(_unit == PayrollItemUnit.hour ? Icons.schedule :
                              _unit == PayrollItemUnit.day ? Icons.today_outlined : Icons.calendar_month_outlined,
                              color: Theme.of(context).colorScheme.primary, size: 22)),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${tr(_unitLabel(_unit))} ${tr(_section == PayrollItemSection.earning ? '支給' : '控除')}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87))),
                        ]),
                        if (widget.quantityExplanation?.call(row.snapshot()) != null)
                          Padding(padding: const EdgeInsets.only(top: 8),
                            child: Text(tr(widget.quantityExplanation!(row.snapshot())!))),
                        const SizedBox(height: 12),
                        TextField(
                          key: ValueKey('${row.value.id}-name'),
                          controller: row.name,
                          onChanged: (_) => _notifyDraft(),
                          focusNode: row.focus,
                          enabled: _editable,
                          decoration: InputDecoration(labelText: tr('項目名'),
                            helperText: widget.registeredNameHints[row.value.id] == null
                                ? null : '会社の登録名：${widget.registeredNameHints[row.value.id]}'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          key: ValueKey('${row.value.id}-rate'),
                          controller: row.rate,
                          onChanged: (_) => _notifyDraft(),
                          enabled: _editable,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr(_rateLabel(_unit)),
                          ),
                        ),
                        if (widget.enableQuantitySources &&
                            row.value.unit == PayrollItemUnit.hour) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: row.source,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: tr('時間数の取得方法'),
                            ),
                            items: [
                              for (final entry in (const {
                                'manual_hours': '対象月の時間数を入力',
                                'overtime_hours': '登録済み残業時間',
                                'early_hours': '登録済み早出時間',
                                'night_hours': '登録済み夜間時間',
                              }).entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(
                                    tr(entry.value),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _editable
                                ? (value) => setState(() => row.source = value!)
                                : null,
                          ),
                          if (row.source == 'manual_hours')
                            TextField(
                              key: ValueKey('${row.value.id}-quantity'),
                              controller: row.quantity,
                              enabled: _editable,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: tr('対象月の時間数'),
                                suffixText: tr('時間'),
                              ),
                            ),
                        ],
                        if (widget.showDailyReportOption)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(tr('日報に表示')),
                            value: row.showInDailyReport,
                            onChanged: _editable
                                ? (value) => setState(
                                    () => row.showInDailyReport = value!,
                                  )
                                : null,
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _editable
                                ? () => setState(() {
                                    _rows.remove(row);
                                    // Keep controllers alive through removal of focused fields.
                                    _retired.add(row);
                                    _notifyDraft();
                                  })
                                : null,
                            icon: const Icon(Icons.delete_outline),
                            label: Text(tr('削除')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.showFooter) SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _editable && widget.allowAdding ? _add : null,
                    icon: const Icon(Icons.add),
                    label: Text(tr('追加')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _editable && widget.onRegister != null
                        ? _register
                        : null,
                    child: Text(tr(_saving ? '登録中' : '登録')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onPressed) =>
      TextButton(
        style: TextButton.styleFrom(
          backgroundColor: selected ? Colors.blue.shade700 : null,
          foregroundColor: selected ? Colors.white : null,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        ),
        onPressed: _saving ? null : onPressed,
        child: Text(
          SkoLanguageController.tr(label),
          textAlign: TextAlign.center,
        ),
      );

  static String _unitLabel(PayrollItemUnit unit) => switch (unit) {
    PayrollItemUnit.hour => '時間単位',
    PayrollItemUnit.day => '日単位',
    PayrollItemUnit.month => '月単位',
  };

  static String _rateLabel(PayrollItemUnit unit) => switch (unit) {
    PayrollItemUnit.hour => '単価（円／時間）',
    PayrollItemUnit.day => '単価（円／日）',
    PayrollItemUnit.month => '単価（円／月）',
  };
}

class _RowDraft {
  _RowDraft(this.value)
    : name = TextEditingController(text: value.name),
      rate = TextEditingController(text: value.rate),
      showInDailyReport = value.showInDailyReport,
      source = value.source,
      quantity = TextEditingController(text: value.quantity);
  final PayrollUnitItemDraft value;
  final TextEditingController name;
  final TextEditingController rate;
  final key = GlobalKey();
  final focus = FocusNode();
  bool showInDailyReport;
  String source;
  final TextEditingController quantity;

  PayrollUnitItemDraft snapshot() => PayrollUnitItemDraft(
    id: value.id,
    section: value.section,
    unit: value.unit,
    name: name.text.trim(),
    rate: rate.text.trim(),
    showInDailyReport: showInDailyReport,
    source: source,
    quantity: quantity.text.trim(),
  );

  void dispose() {
    name.dispose();
    rate.dispose();
    quantity.dispose();
    focus.dispose();
  }
}
