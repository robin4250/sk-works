import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'payroll_unit_conditions_repository.dart';
import 'payroll_unit_item_editor.dart';
import 'payroll_company_common_card.dart';
import 'company_common_application_status.dart';
import 'individual_allowance_rows.dart';

class PayrollUnitConditionsPage extends StatefulWidget {
  const PayrollUnitConditionsPage({
    super.key,
    required this.repository,
    required this.companyId,
    required this.workerId,
    this.embedded = false,
    this.section,
    this.unit,
    this.onValidationSelection,
    this.editorController,
    this.externalFooter = false,
    this.individualAllowanceItems,
    this.canEditIndividualAllowances = false,
    this.onIndividualAllowanceDraftChanged,
    this.onSaveIndividualAllowances,
    this.individualAllowancesNeedSave,
    this.onReloadIndividualAllowances,
    this.individualAllowanceScopeCurrent,
    this.onIndividualSaveUncertain,
    this.individualSaveUncertain = false,
    this.registeredAllowanceNames = const [],
    this.registeredAllowanceNamesUnavailable = false,
  });
  final PayrollUnitConditionsRepository repository;
  final String companyId;
  final String workerId;
  final bool embedded;
  final PayrollUnitEditorController? editorController;
  final bool externalFooter;
  final List<PayrollUnitItemDraft>? individualAllowanceItems;
  final bool canEditIndividualAllowances;
  final ValueChanged<List<PayrollUnitItemDraft>>? onIndividualAllowanceDraftChanged;
  final Future<bool> Function(List<PayrollUnitItemDraft>)? onSaveIndividualAllowances;
  final bool Function(List<PayrollUnitItemDraft>)? individualAllowancesNeedSave;
  final Future<void> Function()? onReloadIndividualAllowances;
  final bool Function()? individualAllowanceScopeCurrent;
  final ValueChanged<bool>? onIndividualSaveUncertain;
  final bool individualSaveUncertain;
  final List<PayrollRegisteredAllowanceName> registeredAllowanceNames;
  final bool registeredAllowanceNamesUnavailable;
  final PayrollItemSection? section;
  final PayrollItemUnit? unit;
  final void Function(PayrollItemSection, PayrollItemUnit)? onValidationSelection;
  @override
  State<PayrollUnitConditionsPage> createState() =>
      _PayrollUnitConditionsPageState();
}

class _PayrollUnitConditionsPageState extends State<PayrollUnitConditionsPage> {
  late DateTime _month;
  PayrollUnitConditions? _value;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _registrationUncertain = false;
  String? _registrationMessage;
  int _generation = 0;
  bool get _hasUncertainSave => _registrationUncertain || widget.individualSaveUncertain;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  @override
  void didUpdateWidget(covariant PayrollUnitConditionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId || oldWidget.companyId != widget.companyId) {
      _load();
    }
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}-01';
  Future<void> _moveMonth(int offset) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(SkoLanguageController.tr('月を変更しますか？未登録の入力内容は保存されません。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(SkoLanguageController.tr('キャンセル')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(SkoLanguageController.tr('月を変更')),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    _month = DateTime(_month.year, _month.month + offset);
    await _load();
  }

  Future<void> _load() async {
    widget.editorController?.invalidate();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      // An unavailable refresh must not leave a stale unit version behind the
      // worker-only fallback, where an empty submission could otherwise erase it.
      _value = null;
    });
    try {
      if (!await widget.repository.available()) {
        throw StateError('not available');
      }
      await widget.onReloadIndividualAllowances?.call();
      if (!mounted || generation != _generation) return;
      final value = await widget.repository.load(
        widget.companyId,
        widget.workerId,
        _monthKey,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _value = value;
        _loading = false;
        _saving = false;
        _registrationUncertain = false;
        _registrationMessage = null;
      });
      widget.onIndividualSaveUncertain?.call(false);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '単位別設定を取得できません。サーバー準備状況を確認してください。';
      });
    }
  }

  bool get _showCurrentRegisteredNames {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month &&
        _value?.companyCommonFrozen != true && _value?.companyCommonHistoryMissing != true;
  }

  List<PayrollUnitItemDraft> get _visibleIndividualItems => _showCurrentRegisteredNames
      ? widget.individualAllowanceItems ?? const [] : const [];

  // Worker allowance slots are ongoing settings, not month-owned values.
  // Show their continuation in future automatic drafts without feeding them
  // into the month editor: its legacy save callback updates the worker's
  // current settings and cannot schedule a future-only change.
  List<PayrollUnitItemDraft> get _continuingIndividualItems {
    final now = DateTime.now();
    final future = _month.isAfter(DateTime(now.year, now.month));
    if (!future || _value?.canEdit != true ||
        _value?.companyCommonFrozen == true ||
        _value?.companyCommonHistoryMissing == true) {
      return const [];
    }
    return [for (final item in widget.individualAllowanceItems ?? <PayrollUnitItemDraft>[])
      if ((widget.section == null || item.section == widget.section) &&
          (widget.unit == null || item.unit == widget.unit)) item];
  }

  Set<int> get _individualSlots => {for (final row in _visibleIndividualItems)
    if (individualAllowanceSlot(row.id) != null) individualAllowanceSlot(row.id)!};

  Set<String> get _individualCommonIds => !_showCurrentRegisteredNames ? const {} : {
    for (final row in widget.registeredAllowanceNames)
      if (row.legacySlot != null && _individualSlots.contains(row.legacySlot) && row.itemId != null)
        row.itemId!,
  };

  List<Map<String, dynamic>> get _visibleCommonItems => [
    for (final item in _value?.companyCommonItems ?? <Map<String, dynamic>>[])
      if (!_individualCommonIds.contains(item['id'])) item,
  ];

  List<PayrollRegisteredAllowanceName> get _referenceNames {
    if (!_showCurrentRegisteredNames) return const [];
    final active = {for (final item in _value?.companyCommonItems ?? <Map<String, dynamic>>[]) item['id']};
    return [for (final row in widget.registeredAllowanceNames)
      if (!active.contains(row.itemId) &&
          !(row.legacySlot != null && _individualSlots.contains(row.legacySlot))) row];
  }

  Map<String, String> get _registeredNameHints => !_showCurrentRegisteredNames ? const {} : {
    for (final row in widget.registeredAllowanceNames)
      if (row.legacySlot != null && _individualSlots.contains(row.legacySlot))
        '$individualAllowanceSlotPrefix${row.legacySlot}': row.name,
  };

  Future<void> _confirmSavedStateReload() async {
    final accepted = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(title: const Text('保存済みの状態を確認'),
        content: const Text('画面の入力を保存し直さず、保存済みの手当を読み直します。表示中の未保存入力は置き換わります。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('入力を保持')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存済みの状態を確認'))]));
    if (mounted && accepted == true) await _load();
  }

  Future<void> _registerItems(List<PayrollUnitItemDraft> items, {bool onlyChangedUnits = false}) async {
    final generation = _generation;
    final company = widget.companyId, worker = widget.workerId;
    final current = _value;
    if (widget.individualAllowanceScopeCurrent?.call() == false) {
      throw StateError('ログイン状態が変わりました');
    }
    // The editor validates every visible/hidden row first. Partitioning also
    // validates the original worker slots before either storage write starts.
    final split = widget.individualAllowanceItems == null || !_showCurrentRegisteredNames
        ? null : splitIndividualAllowanceRows(items);
    final unitItems = split?.unitItems ?? items;
    if (unitItems.length > 100) throw const FormatException('追加できる手当は100件までです');
    if (current == null && unitItems.isNotEmpty) {
      throw StateError('追加手当の保存先を確認できません');
    }
    final saveUnitConditions = current != null &&
        (onlyChangedUnits ? !samePayrollUnitItems(current.items, unitItems)
            : split == null || current.items.isNotEmpty || unitItems.isNotEmpty);
    final saveIndividual = split != null && widget.onSaveIndividualAllowances != null &&
        (widget.individualAllowancesNeedSave?.call(items) ?? true);
    var individualSaved = false;
    var writeStarted = false;
    setState(() { _saving = true; _registrationMessage = null; });
    try {
      if (saveIndividual) {
        writeStarted = true;
        individualSaved = await widget.onSaveIndividualAllowances!(items);
      }
      if (!mounted || generation != _generation ||
          widget.companyId != company || widget.workerId != worker) {
        return;
      }
      if (widget.individualAllowanceScopeCurrent?.call() == false) {
        throw StateError('ログイン状態が変わりました');
      }
      var saved = current;
      if (saveUnitConditions) {
        writeStarted = true;
        saved = await widget.repository.save(company, worker, current, unitItems);
      }
      if (!mounted || generation != _generation ||
          widget.companyId != company || widget.workerId != worker) {
        return;
      }
      setState(() => _value = saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        split == null ? '単位別設定を保存し、対象月の給与を再計算しました'
            : individualSaved || saveUnitConditions ? '手当を保存しました' : '手当の変更はありません')));
    } catch (_) {
      if (mounted && generation == _generation && split != null) {
        setState(() {
          _registrationUncertain = writeStarted;
          _registrationMessage = individualSaved
              ? '一部の手当は保存済みです。追加項目の保存結果を確認できません。入力を保持し、再送を停止しています。'
              : '手当の保存結果を確認できません。入力を保持し、再送を停止しています。';
        });
        widget.onIndividualSaveUncertain?.call(writeStarted);
      }
      rethrow;
    } finally {
      if (mounted && generation == _generation) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    String tr(String x) => SkoLanguageController.tr(x);
    final value = _value;
    final applicationStatus = value == null ? null : companyCommonApplicationStatus(
      sourceJson: value.companyCommonSourceJson,
      month: value.month,
      frozen: value.companyCommonFrozen,
      historyMissing: value.companyCommonHistoryMissing,
      hasItems: value.companyCommonItems.isNotEmpty,
      blocked: value.companyCommonResolution?.blocked == true,
    );
    final body = _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(_error!)),
                  TextButton(onPressed: _hasUncertainSave ? _confirmSavedStateReload : _load,
                    child: Text(tr(_hasUncertainSave ? '保存済みの状態を確認' : '再読み込み'))),
                  if (_registrationMessage != null) Text(tr(_registrationMessage!)),
                  if (widget.individualAllowanceItems != null)
                    PayrollUnitItemEditor(
                      embedded: true, showFooter: !widget.externalFooter,
                      allowAdding: false, controller: widget.editorController,
                      section: widget.section, unit: widget.unit,
                      initialItems: _visibleIndividualItems,
                      canEdit: _showCurrentRegisteredNames && widget.canEditIndividualAllowances && !_saving && !_hasUncertainSave && widget.onSaveIndividualAllowances != null,
                      onDraftChanged: _showCurrentRegisteredNames ? widget.onIndividualAllowanceDraftChanged : null,
                      onRegister: _registerItems,
                    onRegisterPrepared: (items) => _registerItems(items, onlyChangedUnits: true),
                    ),
                ],
              ),
            )
          : Column(
              mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _saving ? null : () => _moveMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      if (!_value!.canEdit)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(tr('閲覧のみ')),
                        ),
                      Expanded(
                        child: Text(
                          '${_month.year}/${_month.month} ${tr('給与の確認月')}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        onPressed: _saving ? null : () => _moveMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
                if (_continuingIndividualItems.isNotEmpty)
                  Padding(
                    key: const ValueKey('continuing-individual-allowances'),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('継続中の手当'),
                      const Text('登録済みの名称・単価は翌月以降も継続します。毎月の再登録は不要です。変更は今月の設定で行います。'),
                      for (final item in _continuingIndividualItems)
                          Card(child: ListTile(
                            key: ValueKey('continuing-${item.id}'),
                            title: Text(item.name),
                            subtitle: Text('日単位・${item.section == PayrollItemSection.earning ? '支給' : '控除'}　${item.rate}円'),
                          )),
                    ]),
                  ),
                if (_value!.companyCommonHistoryMissing)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(tr('社内共通手当の適用月が未登録のため、給与計算を保留しています。社内共通手当の適用月を確認してください。')),
                  ),
                if (applicationStatus != null && widget.individualAllowanceItems != null)
                  Padding(padding: const EdgeInsets.all(12), child: Text(tr(
                    '会社共通手当は給与への適用前です。登録済みの個別手当はこの一覧で保持しています。'))),
                if (applicationStatus != null && widget.individualAllowanceItems == null)
                  Card(child: ListTile(
                    key: const ValueKey('company-common-application-status'),
                    title: Text(tr('社内共通手当')),
                    subtitle: Text(tr(applicationStatus == CompanyCommonApplicationStatus.notRegistered
                        ? 'この給与形態の適用開始月は未登録です。社内共通手当で対象を確認して反映してください。'
                        : 'この対象月は社内共通手当の適用開始前です。')),
                  )),
                if (_visibleCommonItems.isNotEmpty || _value!.companyCommonResolution?.blocked == true)
                  PayrollCompanyCommonCard(
                    key: ValueKey('${widget.companyId}/${widget.workerId}/${_value!.month}/${_value!.companyCommonSourceJson}'),
                    items: _visibleCommonItems,
                    frozen: _value!.companyCommonFrozen,
                    resolution: _value!.companyCommonResolution,
                    canEdit: _value!.canEdit && !_saving,
                    section: widget.section, unit: widget.unit,
                    onReload: _load,
                    onSave: (hours) async {
                      final generation = _generation;
                      final company = widget.companyId;
                      final worker = widget.workerId;
                      final current = _value!;
                      setState(() => _saving = true);
                      try {
                        final saved = await widget.repository.saveCommonHours(company, worker, current, hours);
                        if (!mounted || !context.mounted || generation != _generation || widget.companyId != company || widget.workerId != worker) return;
                        setState(() => _value = saved);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('共通手当の時間数を保存し、対象月の給与を再計算しました'))));
                      } finally {
                        if (mounted && generation == _generation) setState(() => _saving = false);
                      }
                    },
                  ),
                if (widget.registeredAllowanceNamesUnavailable && _showCurrentRegisteredNames)
                  const Padding(padding: EdgeInsets.all(12), child: Text(
                    '会社共通の登録名を確認できません。登録済みの個別設定は保持しています。')),
                if (_registrationMessage != null || _hasUncertainSave)
                  Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                    Text(tr(_registrationMessage ?? '保存結果を確認できません。入力を保持し、再送を停止しています。')),
                    if (_hasUncertainSave && widget.onIndividualSaveUncertain == null)
                      TextButton(onPressed: _saving ? null : _confirmSavedStateReload,
                      child: Text(tr('保存済みの状態を確認'))),
                  ])),
                Flexible(
                  fit: widget.embedded ? FlexFit.loose : FlexFit.tight,
                  child: PayrollUnitItemEditor(
                    embedded: widget.embedded,
                    controller: widget.editorController,
                    showFooter: !widget.externalFooter &&
                        (widget.individualAllowanceItems == null || _value!.items.any((item) =>
                          item.section == widget.section && item.unit == widget.unit)),
                    section: widget.section,
                    unit: widget.unit,
                    onValidationSelection: widget.onValidationSelection,
                    key: ValueKey(
                      '${widget.companyId}/${widget.workerId}/${_value!.month}/${_value!.version}',
                    ),
                    initialItems: [..._visibleIndividualItems, ..._value!.items],
                    onDraftChanged: _showCurrentRegisteredNames ? widget.onIndividualAllowanceDraftChanged : null,
                    registeredNames: _referenceNames,
                    registeredNameHints: _registeredNameHints,
                    quantityExplanation: widget.individualAllowanceItems == null ? null : (item) =>
                        item.unit == PayrollItemUnit.day && item.section == PayrollItemSection.earning
                            ? individualAllowanceSlot(item.id) != null || item.source == 'selected_allowance_days'
                                ? '退勤で選択した日数に応じて支給します'
                                : '出勤日数に応じて支給します'
                            : null,
                    canEdit: _value!.canEdit && !_saving && !_hasUncertainSave &&
                        (widget.individualAllowanceItems == null || widget.canEditIndividualAllowances),
                    enableQuantitySources: true,
                    showDailyReportOption: false,
                    onRegister: _registerItems,
                    onRegisterPrepared: (items) => _registerItems(items, onlyChangedUnits: true),
                  ),
                ),
              ],
            );
    if (widget.embedded) {
      final hasRegisteredNames = _referenceNames.any((item) =>
          item.section == widget.section && item.unit == widget.unit);
      final hasMonthlyItems = _value?.items.any((item) =>
          item.section == widget.section && item.unit == PayrollItemUnit.month) ?? false;
      return Offstage(
        offstage: widget.unit == PayrollItemUnit.month && !_loading &&
            _error == null && applicationStatus == null && _value?.companyCommonHistoryMissing != true && _value?.companyCommonResolution?.blocked != true && !hasMonthlyItems && !hasRegisteredNames && !(_value?.companyCommonItems.any((item) => item['unit'] == 'month' && item['section'] == widget.section?.name) ?? false),
        child: body,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('単位別の支給・控除')),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(tr('単位別の支給・控除')),
                content: SingleChildScrollView(
                  child: Text(
                    tr(
                      '支給・控除ごとに時間・日・月の単価を登録します。時間数は対象月に明示入力するか、登録済みの残業・早出・夜間時間を選びます。日単位は実出勤日数で、同じ日の複数現場は1日です。月単位は月1回で日割りしません。名称・単価は変更するまで翌月以降も継続し、毎月の再登録は不要です。追加した単位別条件は選択した月から有効です。元からある個別手当は今月の設定で編集し、翌月以降は継続中の手当として確認します。月別の時間数は翌月へ複製しません。元の保存先は保持し、同じ手当を重複計上しません。未入力の時間数は計算保留になります。確定済み給与は変更しません。社内共通手当は会社の設定を自動参照します。共通の時間単位手当は対象月の時間数を入力して保存すると給与を再計算します。会社で適用開始月を設定する前は共通項目を給与に加えません。適用対象の会社で適用月の履歴が未登録の場合は給与計算を保留します。会社の編集値と、適用月を登録した給与用の条件は別に管理されます。個別設定の社内共通手当に適用開始月の未登録や開始前の表示がある場合は、その対象月にはまだ加算・控除していません。社内共通手当で給与形態と適用月を確認します。',
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('閉じる')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}


