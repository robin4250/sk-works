import 'line_release_access.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../daily_reports/signature_capture_page.dart';
import 'line_history_parser.dart';
import 'line_import_draft.dart';
import 'line_historical_monthly_import.dart';
import 'line_import_repository.dart';
import 'line_reading_rules.dart';
import 'line_reading_rule_application.dart';
import 'line_historical_monthly_import_page.dart';
import 'line_historical_invoice_page.dart';
import 'line_historical_amount_preview.dart';
import '../invoices/invoice_pdf_service.dart';

class LineImportPage extends StatelessWidget {
  const LineImportPage({super.key, required this.target, this.initialGroupId, this.initialMonth, this.repositoryOverride, this.groupsLoader}) : monthlyTable = false;
  const LineImportPage.monthly({super.key, this.initialGroupId, this.initialMonth, this.repositoryOverride, this.groupsLoader}) : target = 'invoice', monthlyTable = true;
  final bool monthlyTable;
  @visibleForTesting
  final LineImportRepository? repositoryOverride;
  @visibleForTesting
  final Future<List<Map<String, dynamic>>> Function()? groupsLoader;
  final String target;
  final String? initialGroupId;
  final DateTime? initialMonth;
  @override
  Widget build(BuildContext context) => LineReleaseBoundary(builder: (_) => monthlyTable ? _LineImportPageContent.monthly(initialGroupId: initialGroupId, initialMonth: initialMonth, repositoryOverride: repositoryOverride, groupsLoader: groupsLoader) : _LineImportPageContent(target: target, initialGroupId: initialGroupId, initialMonth: initialMonth, repositoryOverride: repositoryOverride, groupsLoader: groupsLoader));
}

class _LineImportPageContent extends StatefulWidget {
  const _LineImportPageContent({required this.target, this.initialGroupId, this.initialMonth, this.repositoryOverride, this.groupsLoader}) : monthlyTable = false;
  const _LineImportPageContent.monthly({this.initialGroupId, this.initialMonth, this.repositoryOverride, this.groupsLoader}) : target = 'invoice', monthlyTable = true;
  final bool monthlyTable;
  @visibleForTesting
  final LineImportRepository? repositoryOverride;
  @visibleForTesting
  final Future<List<Map<String, dynamic>>> Function()? groupsLoader;
  final String target;
  final String? initialGroupId;
  final DateTime? initialMonth;
  @override
  State<_LineImportPageContent> createState() => _LineImportPageState();
}

class _LineImportPageState extends State<_LineImportPageContent> {
  late final _repository = widget.repositoryOverride ?? LineImportRepository.maybeCreate();
  final _note = TextEditingController();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _groups = const [], _workers = const [], _sites = const [], _sources = const [], _rows = const [];
  String? _groupId, _error, _workerFilter;
  List<LineReadingRule> _readingRules = const [];
  String _sourceKind = 'received';
  int _revision = 0, _unreadable = 0;
  String? _draftId;
  Map<String, dynamic>? _formalPending;
  bool _busy = true, _canEdit = false, _enabled = false, _comparisonConfirmed = false, _dirty = false;
  Map<String, dynamic>? _pending;

  @override
  void initState() {
    super.initState();
    final month = widget.initialMonth;
    if (month != null) _month = DateTime(month.year, month.month);
    _initialize();
  }
  @override
  void dispose() { _note.dispose(); super.dispose(); }
  String get _title => widget.monthlyTable ? 'LINE月別の表' : widget.target == 'attendance' ? 'LINE出勤表' : 'LINE請求書';

  Future<void> _initialize() async {
    if (_repository == null) {
      setState(() { _busy = false; _error = 'ログインを確認してください。'; });
      return;
    }
    try {
      final groups = await (widget.groupsLoader?.call() ?? _repository.destinations());
      if (!mounted) return;
      setState(() { _groups = groups.where((group) => group['group_type'] != 'direct').toList(); _groupId = _groups.any((g) => g['id'].toString() == widget.initialGroupId)
          ? widget.initialGroupId : _groups.isEmpty ? null : _groups.first['id'].toString(); });
      await _load();
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'LINEのグループを読み込めませんでした。'; });
    }
  }

  int _loadGeneration = 0;
  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final month = _month;
    final id = _groupId;
    if (id == null) { setState(() => _busy = false); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final data = await _repository!.load(id, widget.target, month);
      final canEdit = data['can_edit'] == true;
      final features = LineImportFeatures.fromJson(data['features']);
      final refs = canEdit ? await _repository.references(id) : (workers: <Map<String, dynamic>>[], sites: <Map<String, dynamic>>[]);
      final enabled = widget.target == 'attendance' ? features.attendance : features.invoice;
      final rules = canEdit && enabled && widget.target == 'invoice'
        ? await _repository.readingRules(id) : <LineReadingRule>[];
      final received = canEdit && enabled ? await _repository.sources(id) : <Map<String, dynamic>>[];
      final existing = [for (final source in data['source_messages'] as List)
        <String, dynamic>{...Map<String, dynamic>.from(source as Map),
          'source_type': source['source_type'] ?? data['source_kind']}];
      final previous = [for (final row in data['candidate_rows'] as List)
        Map<String, dynamic>.from(row as Map)];
      final prepared = lineMonthlyCandidates(lineMergeImportSources(existing, received),
        month, previous: previous, workers: refs.workers, sites: refs.sites, readingRules: rules);
      final oldKeys = existing.map(lineSourceFingerprint).toSet();
      final newKeys = prepared.sources.map(lineSourceFingerprint).toSet();
      final changed = received.isNotEmpty &&
        (oldKeys.length != newKeys.length || !oldKeys.containsAll(newKeys));
      if (!mounted || generation != _loadGeneration || _groupId != id || _month != month) return;
      setState(() {
        _canEdit = canEdit; _enabled = widget.target == 'attendance' ? features.attendance : features.invoice;
        _workers = refs.workers; _sites = refs.sites; _readingRules = rules; _apply(data);
        if (changed) {
          _sources = prepared.sources; _rows = prepared.rows;
          final types = prepared.sources.map((source) => source['source_type']).toSet();
          _sourceKind = types.length > 1 ? 'mixed' : types.isEmpty ? 'received' : types.single.toString();
          _unreadable = prepared.unreadableSourceIds.length;
          _comparisonConfirmed = false; _dirty = true;
        }
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) setState(() { _busy = false; _error = '取込データを読み込めませんでした。権限と接続を確認してください。'; });
    }
  }

  void _apply(Map<String, dynamic> data) {
    _revision = data['revision'] as int;
    _draftId = data['draft_id']?.toString();
    _sources = [for (final value in data['source_messages'] as List) Map<String, dynamic>.from(value as Map)];
    _rows = [for (final value in data['candidate_rows'] as List) Map<String, dynamic>.from(value as Map)];
    _sourceKind = data['source_kind']?.toString() ?? 'received';
    _note.text = data['note_comparison']?.toString() ?? '';
    _comparisonConfirmed = data['confirmed'] == true;
    if (!_rows.any((row) => row['worker_id'] == _workerFilter)) _workerFilter = null;
    _dirty = false; _pending = null; _formalPending = null; _unreadable = 0;
  }

  void _extract(List<Map<String, dynamic>> sources, String kind) {
    final prepared = lineMonthlyCandidates(sources, _month,
      previous: _rows, workers: _workers, sites: _sites, readingRules: _readingRules);
    final types = prepared.sources.map((source) =>
      source['source_type']?.toString() ?? kind).toSet();
    setState(() {
      _sources = prepared.sources; _rows = prepared.rows;
      _sourceKind = types.length > 1 ? 'mixed' : types.isEmpty ? kind : types.single;
      _unreadable = prepared.unreadableSourceIds.length;
      _comparisonConfirmed = false; _dirty = true;
    });
  }

  Future<void> _reimport() async {
    if (_groupId == null) return;
    setState(() => _busy = true);
    try {
      final sources = await _repository!.sources(_groupId!);
      if (mounted) {
        final savedHistory = _sources.where((source) => source['source_type'] == 'history' || (source['source_type'] == null && _sourceKind == 'history'));
        _extract(lineMergeImportSources(savedHistory.toList(), sources), 'received');
      }
    } catch (_) {
      if (mounted) _show('受信した投稿を読み込めませんでした。');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _history() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('書き出したトークを取込'),
      content: SizedBox(width: 500, child: TextField(controller: controller, minLines: 10, maxLines: 15,
        decoration: const InputDecoration(labelText: 'LINEから書き出した履歴を貼り付け', hintText: '2026/10/01\n08:10\t名前\t10月1日…'))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('戻る')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('抽出する'))],
    ));
    controller.dispose();
    if (text == null || !mounted) return;
    final parsed = const LineHistoryParser().parse(text);
    final unique = <String, Map<String, dynamic>>{};
    for (final message in parsed.messages) {
      final source = <String, dynamic>{'body': message.body, 'sent_at': message.timestamp.toUtc().toIso8601String(), 'sender_display_name': message.sender, 'source_type': 'history'};
      final id = 'history:${lineSourceFingerprint(source)}';
      source['id'] = id; unique[id] = source;
    }
    final retained = {for (final source in _sources) source['id'].toString(): source};
    retained.addAll(unique);
    _extract(retained.values.toList(), 'history');
    if (parsed.ignoredLineCount > 0) _show('解析できない行が${parsed.ignoredLineCount}行あります。元の履歴を確認してください。');
  }

  Future<void> _assignSource(Map<String, dynamic> source) async {
    final row = <String, dynamic>{
      'row_id': 'manual:${DateTime.now().microsecondsSinceEpoch}',
      'source_message_id': source['id'],
      'source_fingerprint': lineSourceFingerprint(source),
      'work_date': '${_month.year}-${_month.month.toString().padLeft(2, '0')}-01',
      'man_days': null, 'overtime_hours': null, 'early_hours': null,
      'work_category': 'day', 'allowance_names': <String>[],
      'confirmed': false, 'review_reason': '元本文から手入力してください。',
    };
    setState(() => _rows = [..._rows, row]);
    await _edit(_rows.length - 1);
    if (!mounted) return;
    if (_rows.any((r) => r['row_id'] == row['row_id'] && r['confirmed'] != true)) {
      setState(() => _rows = _rows.where((r) => r['row_id'] != row['row_id']).toList());
    }
  }

  Future<void> _repairAssumed(int index, String field) async {
    final row = _rows[index];
    final controller = TextEditingController(text: '${row[field] ?? 1}');
    String? error;
    final value = await showDialog<double>(context: context, builder: (context) =>
      StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text(field == 'overtime_hours' ? '残業時間（仮）を確認' : '早出時間（仮）を確認'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${(lineAssumedFields(row)[field] as Map?)?['reason'] ?? ''}'),
          TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '時間', errorText: error)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('戻る')),
          FilledButton(onPressed: () {
            final parsed = double.tryParse(controller.text);
            if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 24) {
              update(() => error = '0〜24時間で入力してください。'); return;
            }
            Navigator.pop(context, parsed);
          }, child: const Text('この数値を採用'))],
      )));
    controller.dispose();
    if (value != null && mounted) {
      setState(() {
        _rows[index] = lineRepairAssumedQuantity(row, field, value);
        _comparisonConfirmed = false; _dirty = true;
      });
    }
  }

  Future<void> _edit(int index) async {
    final row = Map<String, dynamic>.from(_rows[index]);
    final assumed = lineAssumedFields(row);
    var overtimeReviewed = !assumed.containsKey('overtime_hours');
    var earlyReviewed = !assumed.containsKey('early_hours');
    final date = TextEditingController(text: row['work_date']?.toString() ?? '');
    final formalName = TextEditingController(text: row['formal_site_name']?.toString() ?? '');
    final days = TextEditingController(text: row['man_days']?.toString() ?? '');
    final overtime = TextEditingController(text: row['overtime_hours']?.toString() ?? '0');
    final early = TextEditingController(text: row['early_hours']?.toString() ?? '0');
    final allowance = TextEditingController(text: (row['allowance_names'] as List? ?? const []).join('、'));
    var category = row['work_category']?.toString() ?? (row['night_work'] == true ? 'night' : 'day');
    String? worker = row['worker_id']?.toString(), site = row['site_id']?.toString();
    var steel = row['steel_allowance'] == true;
    String? validation;
    final edited = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text('${row['work_date']} の確認・修正'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: date, decoration: const InputDecoration(labelText: '日付（YYYY-MM-DD）')),
        DropdownButtonFormField<String>(initialValue: _workers.any((item) => item['id'] == worker) ? worker : null,
          items: [for (final item in _workers) DropdownMenuItem(value: item['id'].toString(), child: Text(item['name'].toString()))],
          onChanged: (value) => worker = value, decoration: const InputDecoration(labelText: '作業員')),
        DropdownButtonFormField<String>(initialValue: _sites.any((item) => item['id'] == site) ? site : null,
          items: [for (final item in _sites) DropdownMenuItem(value: item['id'].toString(), child: Text(item['name'].toString()))],
          onChanged: (value) => site = value, decoration: const InputDecoration(labelText: '現場')),
        TextField(controller: formalName, maxLength: 200, decoration: const InputDecoration(labelText: '正式現場名（請求書へ反映）')),
        TextField(controller: days, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '人工（1 または 0.5）')),
        TextField(controller: overtime, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '残業時間')),
        TextField(controller: early, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '早出時間')),
        DropdownButtonFormField<String>(initialValue: category, items: const [
          DropdownMenuItem(value: 'day', child: Text('通常勤務')), DropdownMenuItem(value: 'night', child: Text('夜勤')),
          DropdownMenuItem(value: 'holiday', child: Text('休日出勤')), DropdownMenuItem(value: 'holiday_night', child: Text('休日夜勤'))],
          onChanged: (value) => category = value ?? 'day', decoration: const InputDecoration(labelText: '勤務区分')),
        CheckboxListTile(value: steel, onChanged: (value) => update(() => steel = value == true), title: const Text('PC・鉄骨手当（設定を確認）')),
        TextField(controller: allowance, decoration: const InputDecoration(labelText: '手当名（登録名を「、」区切り）', hintText: '会社・現場に設定している名称')),
        if (assumed.containsKey('overtime_hours')) CheckboxListTile(
          value: overtimeReviewed, title: const Text('残業の仮値を確認して採用'),
          subtitle: Text('${(assumed['overtime_hours'] as Map)['reason']}'),
          onChanged: (v) => update(() => overtimeReviewed = v == true)),
        if (assumed.containsKey('early_hours')) CheckboxListTile(
          value: earlyReviewed, title: const Text('早出の仮値を確認して採用'),
          subtitle: Text('${(assumed['early_hours'] as Map)['reason']}'),
          onChanged: (v) => update(() => earlyReviewed = v == true)),
        if (validation != null) Text(validation!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('戻る')),
        FilledButton(onPressed: () {
          if (!overtimeReviewed || !earlyReviewed) {
            update(() => validation = '仮の時間を確認し、採用する項目にチェックしてください。'); return;
          }
          final workDate = DateTime.tryParse(date.text.trim());
          if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date.text.trim()) || workDate == null || workDate.toIso8601String().substring(0, 10) != date.text.trim() || workDate.year != _month.year || workDate.month != _month.month) {
            update(() => validation = '対象月の日付をYYYY-MM-DD形式で入力してください。'); return;
          }
          final quantity = double.tryParse(days.text), ot = double.tryParse(overtime.text), eh = double.tryParse(early.text);
          if (worker == null || site == null || (quantity != 1 && quantity != .5) || ot == null || !ot.isFinite || ot < 0 || ot > 24 || eh == null || !eh.isFinite || eh < 0 || eh > 24) {
            update(() => validation = '作業員・現場・数量・時間を確認してください。'); return;
          }
          if (steel && allowance.text.trim().isEmpty) { update(() => validation = 'PC・鉄骨手当の登録名を入力してください。'); return; }
          final w = _workers.singleWhere((item) => item['id'] == worker), s = _sites.singleWhere((item) => item['id'] == site);
          Navigator.pop(context, {...row, 'work_date': date.text.trim(), 'worker_id': worker, 'worker_name': w['name'], 'site_id': site, 'site_name': s['name'], 'customer_id': s['customer_id'], 'formal_site_name': formalName.text.trim(),
            'assumed_fields': <String, dynamic>{}, 'man_days': quantity, 'man_days_inferred': false, 'overtime_hours': ot, 'early_hours': eh, 'night_work': category == 'night' || category == 'holiday_night', 'work_category': category, 'allowance_names': allowance.text.split('、').map((name) => name.trim()).where((name) => name.isNotEmpty).toSet().toList(), 'steel_allowance': steel, 'confirmed': true, 'review_reason': ''});
        }, child: const Text('確認済みにする'))],
    )));
    date.dispose(); formalName.dispose(); days.dispose(); overtime.dispose(); early.dispose(); allowance.dispose();
    if (edited != null && mounted) setState(() { _rows[index] = edited; _comparisonConfirmed = false; _dirty = true; });
  }

  Future<void> _save() async {
    if (_groupId == null) return;
    final allConfirmed = _rows.where((row) => row['excluded'] != true).every((row) => row['confirmed'] == true && !lineHasAssumedQuantities(row));
    final confirmed = _comparisonConfirmed && allConfirmed && _note.text.trim().isNotEmpty;
    if (_comparisonConfirmed && (!allConfirmed || _note.text.trim().isEmpty || !_rows.any((row) => row['excluded'] != true))) {
      _show('明細の確認とLINEノートの照合メモを確認してください。'); return;
    }
    if (confirmed) {
      final keys = <String>{};
      for (final row in _rows.where((row) => row['excluded'] != true)) {
        final key = '${row['work_date']}:${row['worker_id']}:${widget.target == 'invoice' ? row['site_id'] : ''}';
        if (!keys.add(key)) { _show('同日の作業員が重複しています。重複行を除外して確認してください。'); return; }
      }
    }
    _pending ??= _repository!.saveCommand(groupId: _groupId!, target: widget.target, month: _month, revision: _revision,
      sourceKind: _sourceKind, sources: _sources, rows: _rows, note: _note.text.trim(), confirmed: confirmed);
    setState(() => _busy = true);
    try {
      final data = await _repository!.save(_pending!);
      if (!mounted) return;
      setState(() => _apply(data)); _show(confirmed ? '確認済みの取込データを保存しました。' : '取込途中のデータを保存しました。');
    } on PostgrestException catch (error) {
      if (mounted) {
        if (['22023','40001','42501'].contains(error.code)) _pending = null;
        _show(error.code == '40001' ? '保存データが変わりました。再読み込みして修正内容を確認してください。' : error.code == '42501' ? '設定と編集権限を確認してください。' : '入力内容・作業員・現場・重複を確認してください。');
      }
    } catch (_) {
      if (mounted) _show('保存結果を確認できませんでした。同じ内容で再送できます。変更する前に再読み込みしてください。');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _formal() async {
    final id = _draftId;
    if (id == null) return;
    if (_formalPending == null) {
      if (widget.target == 'attendance') {
        final count = _rows.where((row) => row['excluded'] != true && (_workerFilter == null || row['worker_id'] == _workerFilter)).length;
        if (count < 1 || count > 100) { _show('作業員を選び、1～100件をまとめて申請してください。'); return; }
        final signature = await Navigator.of(context).push<SignatureResult>(MaterialPageRoute(builder: (_) => const SignatureCapturePage()));
        if (signature == null || !mounted) return;
        _formalPending = {'p_command_id': LineImportRepository.commandId(), 'p_draft_id': id, 'p_revision': _revision,
          'p_signer_name': signature.signerName, 'p_signature_json': signature.toJson(), 'p_worker_ids': _workerFilter == null ? null : [_workerFilter]};
      } else {
        setState(() => _busy = true);
        try {
          final preview = await _repository!.invoicePreview(id, _revision);
          if (!mounted) return;
          final quotes = preview['quotes'] as List;
          final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
            title: const Text('請求書の下書きを作成'),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('登録済みの現場単価・手当・福利厚生費・会社の税率で計算しました。'),
              for (final raw in quotes) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${raw['customer_name']}\n小計 ${raw['subtotal']}円 ／ 消費税 ${raw['tax']}円 ／ 合計 ${raw['grand_total']}円')),
              const SizedBox(height: 12), const Text('既存の請求書を上書きせず、新しい下書きを作成します。請求書の承認手順は通常どおりです。'),
            ])),
            actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('下書きを作成'))],
          ));
          if (accepted != true || !mounted) return;
          _formalPending = {'p_command_id': LineImportRepository.commandId(), 'p_draft_id': id, 'p_revision': _revision, 'p_expected_fingerprint': preview['fingerprint']};
        } catch (_) {
          if (mounted) _show('金額を計算できませんでした。取引会社・単価・手当の登録設定を確認してください。');
          return;
        } finally { if (mounted) setState(() => _busy = false); }
      }
    }
    setState(() => _busy = true);
    try {
      final result = await _repository!.formal(widget.target, _formalPending!);
      if (!mounted) return;
      _formalPending = null;
      _show(widget.target == 'attendance' ? '${result['item_count']}件を承認待ちへ申請しました。' : '${(result['invoices'] as List).length}件の請求書下書きを作成しました。');
    } on PostgrestException catch (error) {
      if (mounted) {
        if (['22023','40001','42501'].contains(error.code)) _formalPending = null;
        _show(error.code == '40001' ? '確認データや単価が変わりました。再読み込みして再確認してください。' : error.code == '42501' ? 'マスター設定と登録権限を確認してください。' : error.message);
      }
    } catch (_) {
      if (mounted) _show('登録結果を確認できませんでした。同じ登録を再送できます。既存データ・承認待ち・単価変更も確認してください。');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  bool get _monthLocked => _busy || _dirty || _pending != null || _formalPending != null;

  Future<void> _changeMonth(int delta) async {
    if (_busy) return;
    if (_monthLocked) {
      _show('入力中の内容を保存してから月を切り替えてください。');
      return;
    }
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isBefore(DateTime(1900)) || next.isAfter(DateTime(now.year, now.month))) return;
    FocusScope.of(context).unfocus();
    setState(() { _month = next; _workerFilter = null; });
    await _load();
  }

  Future<void> _openMonthlyImport() async {
    final group = _groupId;
    if (group == null || _monthLocked) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      LineHistoricalMonthlyImportPage(groupId: group)));
    if (mounted) await _load();
  }

  Future<void> _openHistorical(bool rates) async {
    final group = _groupId;
    if (group == null || _monthLocked) return;
    final page = rates
      ? LineHistoricalInvoicePage.rates(initialGroupId: group, initialMonth: _month)
      : LineHistoricalInvoicePage(initialGroupId: group, initialMonth: _month);
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }

  Widget _monthlyNavigation() => GestureDetector(
    key: const ValueKey('line-month-swipe'),
    behavior: HitTestBehavior.opaque,
    onHorizontalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      if (velocity.abs() >= 150) _changeMonth(velocity < 0 ? 1 : -1);
    },
    child: Column(children: [
      Row(children: [
        IconButton(key: const ValueKey('line-month-previous'),
          tooltip: '前の月', onPressed: _busy ? null : () => _changeMonth(-1),
          icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text('${_month.year}年${_month.month}月',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge)),
        IconButton(key: const ValueKey('line-month-next'),
          tooltip: '次の月', onPressed: _busy ? null : () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right)),
      ]),
      const Text('左右にスワイプして月を切り替え'),
      Text(_dirty ? '未保存の変更があります・保存して月を切り替え' : '保存版 $_revision'),
    ]),
  );

  void _show(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _help() => showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(_title),
    content: const SingleChildScrollView(child: Text('月別表は各月を選んで確認・入れ直しできます。指定初期単価の参考請求額を表示し、数量を修正すると再計算します。数量不明・不明手当・重複疑いは対象外件数を表示します。正式な金額は現場別単価を保存し、請求書の正式下書きプレビューで確認します。受信済みの投稿、またはLINEから書き出した履歴から対象月の候補を抽出します。作業員・現場・数量を確認して修正し、重複行は除外してください。\n\nLINEノートの集計を貼り付けて人数・人工・残業・早出と照合します。確認後に保存してください。再取込では変わっていない投稿の修正を保持し、変わった投稿は要確認へ戻します。一般メンバーは本人の確認済み出勤だけ閲覧できます。\n\nマスターのOFFでも保存データは消しません。正式な勤怠・請求書の登録は別の確認・承認手順を通します。')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]));

  @override
  Widget build(BuildContext context) {
    final editable = _canEdit && _enabled && !_busy && _pending == null && _formalPending == null;
    final shown = _rows.where((row) => _workerFilter == null || row['worker_id'] == _workerFilter).toList();
    final workerOptions = <String, String>{for (final row in _rows) if (row['worker_id'] is String) row['worker_id'] as String: row['worker_name'].toString()};
    final totals = LineImportDraft.aggregate(shown, bySite: widget.target == 'invoice');
    final estimate = lineHistoricalAmountPreview(_rows);
    return Scaffold(appBar: AppBar(title: Text(_title), actions: [IconButton(onPressed: _help, icon: const Icon(Icons.help_outline), tooltip: '使い方'),
      IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: '再読み込み')]),
      body: _error != null ? Center(child: Text(_error!)) : ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        DropdownButtonFormField<String>(initialValue: _groupId, items: [for (final group in _groups) DropdownMenuItem(value: group['id'].toString(), child: Text(group['display_name']?.toString() ?? group['name'].toString()))],
          onChanged: _busy || _dirty || _pending != null || _formalPending != null ? null : (id) { setState(() => _groupId = id); _load(); }, decoration: const InputDecoration(labelText: 'LINEグループ')),
        if (widget.monthlyTable) _monthlyNavigation(),
        if (!widget.monthlyTable) ListTile(contentPadding: EdgeInsets.zero, title: Text('${_month.year}年${_month.month}月'), subtitle: Text(_dirty ? '未保存の変更があります' : '保存版 $_revision'),
          trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _busy || _dirty || _pending != null || _formalPending != null ? null : () async {
            final day = await showDatePicker(context: context, initialDate: _month, firstDate: DateTime(2000), lastDate: DateTime(DateTime.now().year + 1, 12, 31));
            if (day != null && mounted) { setState(() => _month = DateTime(day.year, day.month)); _load(); }
          })),
        if (widget.monthlyTable) ...[
          const SizedBox(height: 12),
          const Text('連携チャットと書き出しデータをまとめた月間表です。行を押して手入力で修正できます。（仮）の時間はその数値を押して個別修正し、仮値を採用する場合も確認操作が必要です。'),
          OutlinedButton.icon(onPressed: _monthLocked || _groupId == null ? null : _openMonthlyImport,
            icon: const Icon(Icons.file_open_outlined), label: const Text('TXT・ZIPと受信データを月間表へ入れ直す')),
          if (_canEdit) FilledButton(onPressed: _busy || !_enabled ? null : _save, child: Text(_pending == null ? '月間表を保存' : '同じ内容を再送')),
        ],
        if (!_enabled) const Text('この追加機能はマスター設定でOFFです。保存データは残っています。'),
        if (editable) Wrap(spacing: 8, runSpacing: 8, children: [OutlinedButton.icon(onPressed: _reimport, icon: const Icon(Icons.sync), label: const Text('受信トークを再取込')),
          OutlinedButton.icon(onPressed: _history, icon: const Icon(Icons.paste), label: const Text('過去履歴を貼付'))]),
        if (_unreadable > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('読み取れない投稿 $_unreadable 件：元の投稿を確認してください。', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: workerOptions.containsKey(_workerFilter) ? _workerFilter : null, decoration: const InputDecoration(labelText: '個人別表示'),
          items: [const DropdownMenuItem<String>(value: null, child: Text('表示できる全員')), for (final item in workerOptions.entries) DropdownMenuItem(value: item.key, child: Text(item.value))],
          onChanged: _busy || _formalPending != null ? null : (value) => setState(() => _workerFilter = value)),
        if (widget.target == 'invoice') Text(widget.monthlyTable
          ? '照合して保存した月間表から、その月の単価設定と請求書へ進みます。'
          : '請求書はこの月の確認済み全員分を作成します。'),
        if (_canEdit && _enabled && widget.target == 'invoice' && _rows.isNotEmpty) Card(child: Padding(
          padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(estimate.sites.isEmpty ? '参考請求額：数量の確認が必要です' : '読取数量の参考請求額 ${estimate.total}円', style: Theme.of(context).textTheme.titleMedium),
            const Text('指定初期単価での参考計算・月全体。通常日32800円／通常残業・早出5125円／PC・鉄骨各3000円／福利15%／税10%。現場別に変更・保存した単価と登録経費は、正式下書きの金額プレビューで反映します。'),
            Text('未確認 ${estimate.pendingRows}行 ／ 数量・手当・重複などの要確認で計算対象外 ${estimate.incompleteRows}行。未振り分けの原文・訂正は別途照合してください。'),
            Text('残業・早出報告から1人工を仮置きした行 ${_rows.where((row) => row['excluded'] != true && row['man_days_inferred'] == true).length}件：表で確認・修正してください。'),
            for (final site in estimate.sites) Text('${site.name}：${site.total}円（作業・手当 ${site.base}円＋福利 ${site.welfare}円＋税 ${site.tax}円）'),
            const Text('正式請求の確定額ではありません。表を修正すると再計算します。'),
            OutlinedButton.icon(onPressed: _busy || estimate.sites.isEmpty ? null : () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => InvoicePdfPreviewPage(
                invoices: [estimate.invoice(_month)], title: 'SKO請求書・参考／未確認'))),
              icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('SKO請求書の書式で参考金額を確認')),
          ]))),
        Text('確認済み集計', style: Theme.of(context).textTheme.titleMedium),
        if (totals.isEmpty) const Text('確認済みの候補はありません。'),
        for (final total in totals) ListTile(contentPadding: EdgeInsets.zero, title: Text(total['name'].toString()), subtitle: Text('人工 ${total['man_days']} ／ 残業 ${total['overtime_hours']}時間 ／ 早出 ${total['early_hours']}時間')),
        if (widget.target == 'invoice' && shown.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('月別表（行を押して確認・修正）'),
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: DataTable(showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('日付')), DataColumn(label: Text('作業員')),
                DataColumn(label: Text('現場（LINE表記）')), DataColumn(label: Text('正式現場名')), DataColumn(label: Text('人工')),
                DataColumn(label: Text('残業時間')), DataColumn(label: Text('早出時間')),
                DataColumn(label: Text('手当')),
              ],
              rows: [for (final row in shown) DataRow(
                onSelectChanged: editable ? (_) => _edit(_rows.indexOf(row)) : null,
                cells: [
                  DataCell(Text(row['work_date']?.toString() ?? '')),
                  DataCell(Text(row['worker_name']?.toString() ?? '')),
                  DataCell(Text(row['site_name']?.toString() ?? '')),
                  DataCell(Text(row['formal_site_name']?.toString() ?? '未入力')),
                  DataCell(Text(row['man_days'] == null ? '要確認' : '${row['man_days']}${row['man_days_inferred'] == true ? '（仮）' : ''}')),
                  DataCell(Text('${row['overtime_hours'] ?? '要確認'}${lineAssumedFields(row).containsKey('overtime_hours') ? '（仮）' : ''}'),
                    onTap: editable && lineAssumedFields(row).containsKey('overtime_hours') ? () => _repairAssumed(_rows.indexOf(row), 'overtime_hours') : null),
                  DataCell(Text('${row['early_hours'] ?? '要確認'}${lineAssumedFields(row).containsKey('early_hours') ? '（仮）' : ''}'),
                    onTap: editable && lineAssumedFields(row).containsKey('early_hours') ? () => _repairAssumed(_rows.indexOf(row), 'early_hours') : null),
                  DataCell(Text((row['allowance_names'] as List? ?? []).join('、'))),
                ],
              )])),
        ],
        if (_canEdit) ...[
          const SizedBox(height: 16),
          Text('要確認・未振り分け', style: Theme.of(context).textTheme.titleMedium),
          const Text('元本文を確認して手入力できます。1つの投稿から複数行を追加する場合も、投稿を開いて振り分けます。'),
          for (final source in _sources) ExpansionTile(
            title: Text('${source['sent_at']} ／ ${source['sender_display_name'] ?? 'LINE'}'),
            subtitle: Text(_rows.any((r) => r['source_message_id'] == source['id']) ? '候補あり・追加や訂正を確認' : '未振り分け・内容を確認'),
            children: [
              SelectableText(source['body']?.toString() ?? ''),
              TextButton.icon(onPressed: editable ? () => _assignSource(source) : null,
                icon: const Icon(Icons.add), label: const Text('この投稿から行を追加・振り分け')),
            ]),
        ],
        if (_rows.any(lineHasAssumedQuantities))
          const Text('（仮）の時間は未確認です。仮の数値を押すとその欄だけ修正できます。確認済み集計・正式請求へは含めません。'),
        const Divider(), Text('明細 ${shown.length}件', style: Theme.of(context).textTheme.titleMedium),
        for (var index = 0; index < _rows.length; index++) if (_workerFilter == null || _rows[index]['worker_id'] == _workerFilter) Card(child: ListTile(
          title: Text('${_rows[index]['work_date']}  ${_rows[index]['worker_name']}'),
          subtitle: Text('${_rows[index]['site_name']}  人工 ${_rows[index]['man_days'] ?? '要確認'}\n${_rows[index]['excluded'] == true ? '除外' : _rows[index]['confirmed'] == true ? '確認済み' : _rows[index]['review_reason'] ?? '要確認'}'),
          onTap: editable ? () => _edit(index) : null,
          trailing: editable ? Checkbox(value: _rows[index]['excluded'] == true, onChanged: (value) => setState(() { _rows[index]['excluded'] = value == true; _comparisonConfirmed = false; _dirty = true; })) : null,
        )),
        if (_canEdit) ...[
          const SizedBox(height: 16), TextField(controller: _note, readOnly: !editable, maxLines: 6, minLines: 3,
            onChanged: (_) => setState(() { _dirty = true; _comparisonConfirmed = false; }), decoration: const InputDecoration(labelText: 'LINEノートの集計・照合メモ', hintText: 'LINEノートの集計を貼り付け、差分を確認してください。')),
          CheckboxListTile(value: _comparisonConfirmed, onChanged: editable ? (value) => setState(() { _comparisonConfirmed = value == true; _dirty = true; }) : null,
            title: const Text('明細とLINEノートの集計を照合しました')),
          FilledButton(onPressed: _busy || !_enabled ? null : _save, child: Text(_pending == null ? '保存する' : '同じ内容を再送')),
          const SizedBox(height: 12),
          if (!widget.monthlyTable) OutlinedButton.icon(onPressed: _busy || !_enabled || _dirty || _draftId == null || !_comparisonConfirmed || _pending != null ? null : _formal, icon: const Icon(Icons.fact_check_outlined), label: Text(_formalPending != null ? '同じ登録を再送' : widget.target == 'attendance' ? '署名して出勤を申請' : '金額を確認して請求書を作成')),
          if (widget.monthlyTable) ...[
            OutlinedButton.icon(onPressed: _monthLocked || _groupId == null ? null : () => _openHistorical(true),
              icon: const Icon(Icons.price_change_outlined), label: const Text('この月の単価設定')),
            OutlinedButton.icon(onPressed: _monthLocked || _groupId == null ? null : () => _openHistorical(false),
              icon: const Icon(Icons.receipt_long_outlined), label: const Text('この月の請求書')),
            const Text('照合済みの表に過去月の単価を設定し、保存した履歴から請求書の下書きを作成します。'),
          ] else
            const Text('出勤は既存の承認待ちへ、請求書は下書きとして保存します。同じ日の出勤や同じ月の請求書がある場合は、既存データの確認へ進んでください。'),
        ],
      ]));
  }
}


