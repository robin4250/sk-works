import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'company_common_allowance_repository.dart';
import 'company_common_allowance_pending_store.dart';
import 'company_common_payroll_publication_panel.dart';

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
    this.companyId,
    this.repository,
    this.pendingStore,
    this.header,
    this.editorRevisions = const {},
    this.connectionMessage,
    this.legacyBuilder,
    this.embedded = false,
  });

  final Map<CompanyPayrollType, List<PayrollUnitItemDraft>> initialItems;
  final bool canEdit;
  final String? companyId;
  final bool embedded;
  final CompanyCommonAllowanceRepository? repository;
  final CompanyCommonAllowancePendingStore? pendingStore;
  final Widget? header;
  final Map<CompanyPayrollType, int> editorRevisions;
  final String? connectionMessage;
  final Widget? Function(CompanyPayrollType, PayrollItemUnit, PayrollItemSection)? legacyBuilder;
  final Future<void> Function(
    CompanyPayrollType type,
    List<PayrollUnitItemDraft> items,
  )?
  onRegister;

  @override
  State<CompanyCommonPayrollPage> createState() =>
      _CompanyCommonPayrollPageState();
}

class _ConnectedCompanyCommonPayrollPage extends StatefulWidget {
  const _ConnectedCompanyCommonPayrollPage({required this.companyId, this.repository, this.pendingStore, this.header, this.embedded = false});
  final String companyId;
  final CompanyCommonAllowanceRepository? repository;
  final CompanyCommonAllowancePendingStore? pendingStore;
  final Widget? header;
  final bool embedded;
  @override State<_ConnectedCompanyCommonPayrollPage> createState() => _ConnectedCompanyCommonPayrollPageState();
}

class _ConnectedCompanyCommonPayrollPageState extends State<_ConnectedCompanyCommonPayrollPage> with WidgetsBindingObserver {
  late final CompanyCommonAllowanceRepository? _repository;
  late final CompanyCommonAllowancePendingStore _store;
  String? _actor;
  CompanyCommonAllowanceState? _state;
  CompanyCommonAllowancePending? _pending;
  final _items = <CompanyPayrollType, List<PayrollUnitItemDraft>>{};
  final _revisions = <CompanyPayrollType, int>{};
  final _legacyNames = <int, TextEditingController>{};
  final _legacyAmounts = <int, TextEditingController>{};
  final _legacyUnits = <int, TextEditingController>{};
  bool _confirming = false;
  bool _publishing = false;
  String _publicationType = 'hourly';
  bool _loading = true, _busy = false, _active = true, _revoked = false, _conflict = false;
  bool _authorized = true;
  int _generation = 0;
  String? _error;
  BuildContext? _dialogContext;
  void _closeDialog() {
    final dialog = _dialogContext;
    _dialogContext = null;
    if (dialog != null) WidgetsBinding.instance.addPostFrameCallback((_) { if (dialog.mounted && ModalRoute.of(dialog)?.isCurrent == true) Navigator.of(dialog).pop(); });
  }
  @override void initState() {
    super.initState();
    _repository = widget.repository ?? SupabaseCompanyCommonAllowanceRepository.maybeCreate();
    _actor = _repository?.actorId;
    _actorSubscription = _repository?.actorChanges.listen((value) { if (value != _actor) _revoke(); }, onError: (_) => _revoke());
    _store = widget.pendingStore ?? FileCompanyCommonAllowancePendingStore(currentActor: () => _repository?.actorId);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    // In production the global identity boundary also disposes old routes.
    // A periodic local identity check covers injected or independently changed scopes.
    _identityTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && _repository?.actorId != _actor) _revoke(); });
    if (_active) unawaited(_load());
  }
  Timer? _identityTimer;
  StreamSubscription<String?>? _actorSubscription;
  bool _valid(int generation) => mounted && !_revoked && _active && generation == _generation && _actor != null && _repository?.actorId == _actor;
  void _revoke() {
    if (!mounted || _revoked) return;
    _closeDialog();
    _generation++;
    for (final controller in [..._legacyNames.values, ..._legacyAmounts.values, ..._legacyUnits.values]) { controller.clear(); }
    setState(() { _revoked = true; _state = null; _pending = null; _items.clear(); _error = 'ログイン情報または会社が変更されました。画面を開き直してください。'; });
  }
  @override void didUpdateWidget(covariant _ConnectedCompanyCommonPayrollPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.companyId != oldWidget.companyId || widget.repository != oldWidget.repository || widget.pendingStore != oldWidget.pendingStore) _revoke();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.inactive) {
      _closeDialog();
      _generation++; setState(() { _active = false; _authorized = false; });
    } else if (state == AppLifecycleState.resumed && !_revoked) {
      setState(() => _active = true);
      if (_state == null) { unawaited(_load()); } else { unawaited(_verifyResume()); }
    }
  }
  Future<void> _verifyResume() async {
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final pending = await _store.read(_actor!, widget.companyId);
      final fresh = await _repository!.read(widget.companyId);
      if (!_valid(generation)) return;
      setState(() {
        _pending = pending;
        _authorized = true;
        _conflict = fresh.version != _state!.version || !fresh.canEdit && _state!.canEdit;
        if (_conflict) _error = '設定が更新されたか権限が変更されました。入力内容を保持しています。保存せず再読み込みしてください。';
      });
    } on PostgrestException catch (error) {
      if (_valid(generation) && error.code == '42501') { _revoke(); }
      else if (_valid(generation)) { setState(() { _authorized = false; _conflict = true; _error = '権限を再確認できません。入力内容を保持しています。'; }); }
    } catch (_) {
      if (_valid(generation)) setState(() { _authorized = false; _conflict = true; _error = '権限を再確認できません。入力内容を保持しています。'; });
    } finally { if (mounted && generation == _generation) setState(() => _busy = false); }
  }
  List<PayrollUnitItemDraft> _drafts(CompanyCommonAllowanceState state, CompanyPayrollType type) => [
    for (final item in state.items.where((x) => x['payroll_type'] == type.name)) PayrollUnitItemDraft(id: item['id'] as String, section: PayrollItemSection.values.byName(item['section'] as String), unit: PayrollItemUnit.values.byName(item['unit'] as String), name: item['name'] as String, rate: '${item['amount_yen']}'),
  ];
  void _accept(CompanyCommonAllowanceState value, {CompanyPayrollType? only}) {
    if (only != null) _publicationType = only.name;
    _state = value;
    for (final slot in value.legacyRefs) {
      final number = slot['slot'] as int;
      (_legacyNames[number] ??= TextEditingController()).text = slot['name'] as String? ?? '';
      (_legacyAmounts[number] ??= TextEditingController()).text = '${slot['amount_yen']}';
      (_legacyUnits[number] ??= TextEditingController()).text = slot['source_unit'] as String;
    }
    for (final type in CompanyPayrollType.values) {
      if (only != null && type != only) continue;
      _items[type] = _drafts(value, type);
      _revisions[type] = (_revisions[type] ?? 0) + 1;
    }
  }
  Future<void> _load() async {
    final repository = _repository;
    final actor = _actor;
    if (repository == null || actor == null || widget.companyId.isEmpty) { setState(() { _loading = false; _error = '会社共通手当を利用できません。'; }); return; }
    final generation = ++_generation;
    setState(() { _loading = true; _error = null; });
    try {
      final pending = await _store.read(actor, widget.companyId);
      final value = await repository.read(widget.companyId);
      if (!_valid(generation)) return;
      setState(() { _pending = pending; _accept(value); _loading = false; _conflict = false; _authorized = true; });
    } catch (_) {
      if (_valid(generation)) setState(() { _loading = false; _error = '会社共通手当を読み込めません。入力・保存は開始していません。'; });
    }
  }
  Future<void> _save(CompanyPayrollType type, List<PayrollUnitItemDraft> values) async {
    final generation = _generation;
    if (!_valid(generation) || _busy || _publishing || _confirming || _pending != null || _conflict || _state?.canEdit != true) throw StateError('現在は保存できません');
    final legacy = [for (final slot in _state!.legacyRefs) {
      'slot': slot['slot'], 'id': slot['id'], 'generation': slot['generation'],
      'name': _legacyNames[slot['slot']]!.text == (slot['name'] ?? '') ? slot['name'] : (_legacyNames[slot['slot']]!.text.trim().isEmpty ? null : _legacyNames[slot['slot']]!.text.trim()),
      'source_unit': _legacyUnits[slot['slot']]!.text == slot['source_unit'] ? slot['source_unit'] : _legacyUnits[slot['slot']]!.text.trim(), 'amount_yen': int.parse(_legacyAmounts[slot['slot']]!.text.trim()),
    }];
    final adoption = _state!.expectedSource['legacy_adopted'] != true;
    if (adoption) {
      setState(() => _confirming = true);
      final confirmed = await showDialog<bool>(context: context, builder: (context) {
        _dialogContext = context;
        return AlertDialog(title: const Text('既存手当を引き継いで保存'), content: const Text('元からある3枠を、各給与形態の日単位・支給の先頭で共通利用します。同じ項目IDで管理し、3形態へ複製しません。表示した既存値と今回の編集内容を確認して保存します。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して保存'))]);
      });
      _dialogContext = null;
      if (mounted) setState(() => _confirming = false);
      if (confirmed != true || !_valid(generation)) throw StateError('保存を中止しました');
    }
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final requestId = '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
    final pending = CompanyCommonAllowancePending(actorId: _actor!, companyId: widget.companyId, payrollType: type.name, expectedVersion: _state!.version, expectedSource: _state!.expectedSource, legacySlots: legacy, confirmAdoption: adoption, requestId: requestId, items: [
      for (final item in values) {'id': item.id.startsWith('new-unit-item-') ? null : item.id, 'client_key': item.id, 'section': item.section.name, 'unit': item.unit.name, 'name': item.name.trim(), 'amount_yen': int.parse(item.rate)},
    ]);
    setState(() { _busy = true; _error = null; _pending = pending; });
    var journalWritten = false;
    try {
      await _store.write(pending);
      journalWritten = true;
      if (!_valid(generation)) throw StateError('保存前に本人確認が変わりました');
      setState(() => _pending = pending);
      final saved = await _repository!.save(pending);
      if (!_valid(generation)) return;
      await _store.clear(pending);
      if (!_valid(generation)) return;
      setState(() { _pending = null; _conflict = false; _error = null; _accept(saved, only: type); });
      await _showComplete();
    } on PostgrestException catch (error) {
      if (journalWritten && ['42501', '40001', '22023', 'PGRST202'].contains(error.code) && _valid(generation)) {
        await _store.clear(pending);
        if (_valid(generation)) setState(() { _pending = null; _conflict = true; _error = error.code == '22023' && error.message == 'past allowance display unit requires dated compatibility' ? '過去の出勤表の単位を保護するため、この単位変更はまだ保存できません。入力内容は保持しています。' : '保存は受け付けられませんでした。入力を保持しています。再読み込みして確認してください。'; });
      }
      rethrow;
    } catch (_) {
      if (_valid(generation)) setState(() { _pending = journalWritten ? pending : null; _error = journalWritten ? '保存結果を確認できません。再送せず「保存状態を確認」を押してください。' : '保存準備に失敗しました。入力を保持しています。'; });
      rethrow;
    } finally { if (mounted && generation == _generation) setState(() => _busy = false); }
  }
  Future<void> _showComplete() async {
    await showDialog<void>(context: context, builder: (context) { _dialogContext = context; return AlertDialog(icon: const Icon(Icons.check_circle_outline), title: const Text('保存完了'), content: const Text('会社共通手当を保存しました。選択中の給与形態・時間／日／月の区分を保持しています。'), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる'))]); });
    _dialogContext = null;
  }
  Future<void> _reconcile() async {
    final pending = _pending;
    final generation = _generation;
    if (pending == null || _busy || !_valid(generation)) return;
    setState(() { _busy = true; _error = null; });
    try {
      final saved = await _repository!.reconcile(pending);
      if (!_valid(generation)) return;
      if (saved == null) { setState(() => _error = '保存履歴がまだ確認できません。再送は行いません。時間をおいて確認してください。'); return; }
      await _store.clear(pending);
      if (!_valid(generation)) return;
      setState(() { _pending = null; _conflict = false; _error = null; _accept(saved, only: CompanyPayrollType.values.byName(pending.payrollType)); });
      await _showComplete();
    } catch (_) {
      if (_valid(generation)) setState(() => _error = '保存結果を照合できません。再送せず入力・確認記録を保持しています。');
    } finally { if (mounted && generation == _generation) setState(() => _busy = false); }
  }
  Future<void> _discardAndReload() async {
    if (_pending != null || _busy || _revoked) return;
    final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('入力を破棄して再読み込み'), content: const Text('各給与形態の未保存入力を破棄して、保存済みの設定を読み直します。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('破棄して再読み込み'))]));
    if (discard == true && mounted && !_revoked && _active) await _load();
  }
  @override void dispose() { _generation++; _identityTimer?.cancel(); _actorSubscription?.cancel(); for (final c in [..._legacyNames.values, ..._legacyAmounts.values, ..._legacyUnits.values]) { c.dispose(); } WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override Widget build(BuildContext context) {
    Widget surface(Widget body) => widget.embedded ? body : Scaffold(appBar: AppBar(title: const Text('社内共通手当')), body: body);
    if (_revoked) return surface(Center(child: Text(_error!)));
    if (_state == null) return surface(Center(child: _loading ? const CircularProgressIndicator() : Column(mainAxisSize: MainAxisSize.min, children: [Text(_error ?? '設定を確認できません'), TextButton(onPressed: _active ? _load : null, child: const Text('再読み込み'))])));
    final page = CompanyCommonPayrollPage(embedded: widget.embedded, initialItems: _items, editorRevisions: _revisions, canEdit: _state!.canEdit && _active && !_busy && !_publishing && _pending == null && !_conflict,
      onRegister: _state!.canEdit ? _save : null, connectionMessage: '閲覧専用です。会社共通手当の登録・変更は管理者が行います。',
      legacyBuilder: (_, __, ___) => Column(children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('元からある手当（各給与形態で共通）')),
        for (final slot in _state!.legacyRefs) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Text('既存手当 ${slot['slot']}'),
          TextField(key: ValueKey('legacy-${slot['slot']}-name'), controller: _legacyNames[slot['slot']], enabled: _state!.canEdit && !_busy && !_publishing && !_confirming && _pending == null && !_conflict, maxLength: 80, decoration: const InputDecoration(labelText: '項目名')),
          TextField(key: ValueKey('legacy-${slot['slot']}-amount'), controller: _legacyAmounts[slot['slot']], enabled: _state!.canEdit && !_busy && !_publishing && !_confirming && _pending == null && !_conflict, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '日単位の金額（円）')),
          TextField(key: ValueKey('legacy-${slot['slot']}-unit'), controller: _legacyUnits[slot['slot']], enabled: _state!.canEdit && !_busy && !_publishing && !_confirming && _pending == null && !_conflict, maxLength: 12, decoration: const InputDecoration(labelText: '表示単位', helperText: '元の単位を保持。日単位・支給の分類は変わりません。')),
          TextButton(onPressed: _state!.canEdit && !_busy && !_publishing && !_confirming && _pending == null && !_conflict ? () { _legacyNames[slot['slot']]!.clear(); } : null, child: const Text('削除')),
        ]))),
        const Padding(padding: EdgeInsets.all(8), child: Text('追加した手当')),
      ]),
      header: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.header != null) widget.header!,
        if (_repository is SupabaseCompanyCommonAllowanceRepository)
          CompanyCommonPayrollPublicationPanel(
            key: ValueKey('common-publications-${widget.companyId}/${_state!.version}'),
            companyId: widget.companyId,
            initialPayrollType: _publicationType,
            canReconcile: _active && !_busy && _authorized,
            enabled: _state!.canEdit && _active && !_busy && !_confirming && _pending == null && !_conflict,
            onBusyChanged: (busy) { if (mounted && _publishing != busy) setState(() => _publishing = busy); },
          ),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_error!)),
        if (_pending != null) TextButton(onPressed: _busy || !_active ? null : _reconcile, child: const Text('保存状態を確認')),
        if (_conflict && _pending == null) TextButton(onPressed: _busy || _publishing || !_active ? null : _discardAndReload, child: const Text('入力を破棄して再読み込み')),
      ]));
    return Stack(children: [Offstage(offstage: !_active || !_authorized, child: page), if (!_active || !_authorized) Positioned.fill(child: ColoredBox(color: Theme.of(context).colorScheme.surface, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error ?? '本人確認を再確認しています'), if (_active) TextButton(onPressed: _busy ? null : _verifyResume, child: const Text('権限を再確認'))]))))]);
  }
}

class _CompanyCommonPayrollPageState extends State<CompanyCommonPayrollPage> {
  var _type = CompanyPayrollType.hourly;
  var _section = PayrollItemSection.earning;
  var _unit = PayrollItemUnit.hour;
  var _saving = false;
  final _footers = {
    for (final type in CompanyPayrollType.values) type: PayrollUnitEditorController(),
  };
  late final _footerChanges = Listenable.merge(_footers.values.toList());
  @override
  void dispose() {
    for (final controller in _footers.values) { controller.dispose(); }
    super.dispose();
  }
  Widget _fixedFooter() {
    final controller = _footers[_type]!;
    final editable = widget.canEdit && widget.onRegister != null && !_saving;
    return SafeArea(
      key: const ValueKey('company-common-fixed-footer'), top: false,
      child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: editable && controller.canAdd ? controller.add : null,
          icon: const Icon(Icons.add), label: const Text('追加'))),
        const SizedBox(width: 12),
        Expanded(child: FilledButton.icon(
          onPressed: editable && controller.canRegister ? controller.register : null,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving || controller.saving ? '登録中' : '登録'))),
      ])),
    );
  }

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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _footerChanges, builder: (context, _) => _buildPage(context));

  Widget _buildPage(BuildContext context) {
    if (widget.companyId != null) return _ConnectedCompanyCommonPayrollPage(companyId: widget.companyId!, repository: widget.repository, pendingStore: widget.pendingStore, header: widget.header, embedded: widget.embedded);
    final scaffold = Scaffold(
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
                '日給・時給・月給ごとに共通支給と共通控除を分けます。給与形態と、手当の時間・日・月単位は別の設定です。追加手当を保存した後、「給与への適用月」で給与形態と月を選ぶと、保存済みの条件を自動下書きへ反映します。未保存の編集内容、従来3枠、確定済み・手入力給与はこの適用操作で上書きしません。給与側の接続と会社の適用開始月が有効な場合に利用できます。',
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
    bottomNavigationBar: _fixedFooter(),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 12, 9, 4),
            child: Row(
              children: [
                for (final type in [CompanyPayrollType.hourly, CompanyPayrollType.daily, CompanyPayrollType.monthly])
                  _choice(
                    _labels[type]!,
                    _type == type,
                    () => setState(() => _type = type),
                  ),
              ],
            ),
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
          if (widget.header != null) widget.header!,
          if (widget.onRegister == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(widget.connectionMessage ?? '保存・個別給料設定への反映は接続準備中です。現在の給与設定は変更されません。'),
            ),
          Expanded(
            child: IndexedStack(
              index: _type.index,
              children: [
                for (final type in CompanyPayrollType.values)
                  ListView(children: [
                  if (type == _type && widget.legacyBuilder != null && _unit == PayrollItemUnit.day && _section == PayrollItemSection.earning)
                    widget.legacyBuilder!(type, _unit, _section) ?? const SizedBox.shrink(),
                  PayrollUnitItemEditor(
                    key: ValueKey('company-common-${type.name}-${widget.editorRevisions[type] ?? 0}'),
                    initialItems: widget.initialItems[type] ?? const [],
                    embedded: true,
                    controller: _footers[type],
                    showFooter: false,
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
                  ]),
              ],
            ),
          ),
        ],
      ),
    ),
  );
    return widget.embedded
        ? Column(children: [Expanded(child: scaffold.body!), _fixedFooter()])
        : scaffold;
  }
}

