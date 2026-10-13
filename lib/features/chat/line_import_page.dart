import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../daily_reports/signature_capture_page.dart';
import 'chat_cloud_repository.dart';
import 'line_history_parser.dart';
import 'line_import_draft.dart';
import 'line_import_repository.dart';

class LineImportPage extends StatefulWidget {
  const LineImportPage({super.key, required this.target, this.initialGroupId, this.initialMonth});
  final String target;
  final String? initialGroupId;
  final DateTime? initialMonth;
  @override
  State<LineImportPage> createState() => _LineImportPageState();
}

class _LineImportPageState extends State<LineImportPage> {
  final _repository = LineImportRepository.maybeCreate();
  final _chat = ChatCloudRepository.maybeCreate();
  final _note = TextEditingController();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _groups = const [], _workers = const [], _sites = const [], _sources = const [], _rows = const [];
  String? _groupId, _error, _workerFilter;
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
  String get _title => widget.target == 'attendance' ? 'LINE出勤表' : 'LINE請求書';

  Future<void> _initialize() async {
    if (_repository == null || _chat == null) {
      setState(() { _busy = false; _error = 'ログインを確認してください。'; });
      return;
    }
    try {
      final groups = await _chat.loadGroups();
      if (!mounted) return;
      setState(() { _groups = groups.where((group) => group['group_type'] != 'direct').toList(); _groupId = _groups.any((g) => g['id'].toString() == widget.initialGroupId)
          ? widget.initialGroupId : _groups.isEmpty ? null : _groups.first['id'].toString(); });
      await _load();
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'LINEのグループを読み込めませんでした。'; });
    }
  }

  Future<void> _load() async {
    final id = _groupId;
    if (id == null) { setState(() => _busy = false); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final data = await _repository!.load(id, widget.target, _month);
      final canEdit = data['can_edit'] == true;
      final features = LineImportFeatures.fromJson(data['features']);
      final refs = canEdit ? await _repository.references(id) : (workers: <Map<String, dynamic>>[], sites: <Map<String, dynamic>>[]);
      if (!mounted || _groupId != id) return;
      setState(() {
        _canEdit = canEdit; _enabled = widget.target == 'attendance' ? features.attendance : features.invoice;
        _workers = refs.workers; _sites = refs.sites; _apply(data); _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = '取込データを読み込めませんでした。権限と接続を確認してください。'; });
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
    final draft = LineImportDraft.extract(sources, _month, previous: _rows);
    final rows = [for (final row in draft.rows) Map<String, dynamic>.from(row)];
    for (final row in rows) {
      if (row['worker_id'] == null) {
        final matching = _workers.where((worker) => worker['name'] == row['worker_name']).toList();
        if (matching.length == 1) row['worker_id'] = matching.single['id'];
      }
      if (row['site_id'] == null) {
        final matching = _sites.where((site) => site['name'] == row['site_name']).toList();
        if (matching.length == 1) { row['site_id'] = matching.single['id']; row['customer_id'] = matching.single['customer_id']; }
      }
    }
    final used = rows.map((row) => row['source_message_id'].toString()).toSet();
    final relevant = sources.where((source) {
      final at = DateTime.tryParse(source['sent_at']?.toString() ?? '')?.toLocal();
      return used.contains(source['id']) || (draft.unreadableSourceIds.contains(source['id']) && at?.year == _month.year && at?.month == _month.month);
    }).toList();
    final types = relevant.map((source) => source['source_type']?.toString() ?? kind).toSet();
    setState(() { _sources = relevant; _rows = rows; _sourceKind = types.length > 1 ? 'mixed' : types.isEmpty ? kind : types.single; _unreadable = draft.unreadableSourceIds.length; _comparisonConfirmed = false; _dirty = true; });
  }

  Future<void> _reimport() async {
    if (_groupId == null) return;
    setState(() => _busy = true);
    try {
      final sources = await _repository!.sources(_groupId!);
      if (mounted) {
        final savedHistory = _sources.where((source) => source['source_type'] == 'history' || (source['source_type'] == null && _sourceKind == 'history'));
        _extract([...savedHistory, ...sources], 'received');
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

  Future<void> _edit(int index) async {
    final row = Map<String, dynamic>.from(_rows[index]);
    final date = TextEditingController(text: row['work_date']?.toString() ?? '');
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
        TextField(controller: days, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '人工（1 または 0.5）')),
        TextField(controller: overtime, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '残業時間')),
        TextField(controller: early, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '早出時間')),
        DropdownButtonFormField<String>(initialValue: category, items: const [
          DropdownMenuItem(value: 'day', child: Text('通常勤務')), DropdownMenuItem(value: 'night', child: Text('夜勤')),
          DropdownMenuItem(value: 'holiday', child: Text('休日出勤')), DropdownMenuItem(value: 'holiday_night', child: Text('休日夜勤'))],
          onChanged: (value) => category = value ?? 'day', decoration: const InputDecoration(labelText: '勤務区分')),
        CheckboxListTile(value: steel, onChanged: (value) => update(() => steel = value == true), title: const Text('PC・鉄骨手当（設定を確認）')),
        TextField(controller: allowance, decoration: const InputDecoration(labelText: '手当名（登録名を「、」区切り）', hintText: '会社・現場に設定している名称')),
        if (validation != null) Text(validation!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('戻る')),
        FilledButton(onPressed: () {
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
          Navigator.pop(context, {...row, 'work_date': date.text.trim(), 'worker_id': worker, 'worker_name': w['name'], 'site_id': site, 'site_name': s['name'], 'customer_id': s['customer_id'],
            'man_days': quantity, 'overtime_hours': ot, 'early_hours': eh, 'night_work': category == 'night' || category == 'holiday_night', 'work_category': category, 'allowance_names': allowance.text.split('、').map((name) => name.trim()).where((name) => name.isNotEmpty).toSet().toList(), 'steel_allowance': steel, 'confirmed': true, 'review_reason': ''});
        }, child: const Text('確認済みにする'))],
    )));
    date.dispose(); days.dispose(); overtime.dispose(); early.dispose(); allowance.dispose();
    if (edited != null && mounted) setState(() { _rows[index] = edited; _comparisonConfirmed = false; _dirty = true; });
  }

  Future<void> _save() async {
    if (_groupId == null) return;
    final allConfirmed = _rows.where((row) => row['excluded'] != true).every((row) => row['confirmed'] == true);
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

  void _show(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _help() => showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(_title),
    content: const SingleChildScrollView(child: Text('受信済みの投稿、またはLINEから書き出した履歴から対象月の候補を抽出します。作業員・現場・数量を確認して修正し、重複行は除外してください。\n\nLINEノートの集計を貼り付けて人数・人工・残業・早出と照合します。確認後に保存してください。再取込では変わっていない投稿の修正を保持し、変わった投稿は要確認へ戻します。一般メンバーは本人の確認済み出勤だけ閲覧できます。\n\nマスターのOFFでも保存データは消しません。正式な勤怠・請求書の登録は別の確認・承認手順を通します。')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]));

  @override
  Widget build(BuildContext context) {
    final editable = _canEdit && _enabled && !_busy && _pending == null && _formalPending == null;
    final shown = _rows.where((row) => _workerFilter == null || row['worker_id'] == _workerFilter).toList();
    final workerOptions = <String, String>{for (final row in _rows) if (row['worker_id'] is String) row['worker_id'] as String: row['worker_name'].toString()};
    final totals = LineImportDraft.aggregate(shown, bySite: widget.target == 'invoice');
    return Scaffold(appBar: AppBar(title: Text(_title), actions: [IconButton(onPressed: _help, icon: const Icon(Icons.help_outline), tooltip: '使い方'),
      IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: '再読み込み')]),
      body: _error != null ? Center(child: Text(_error!)) : ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        DropdownButtonFormField<String>(initialValue: _groupId, items: [for (final group in _groups) DropdownMenuItem(value: group['id'].toString(), child: Text(group['display_name']?.toString() ?? group['name'].toString()))],
          onChanged: _busy || _dirty || _pending != null || _formalPending != null ? null : (id) { setState(() => _groupId = id); _load(); }, decoration: const InputDecoration(labelText: 'LINEグループ')),
        ListTile(contentPadding: EdgeInsets.zero, title: Text('${_month.year}年${_month.month}月'), subtitle: Text(_dirty ? '未保存の変更があります' : '保存版 $_revision'),
          trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _busy || _dirty || _pending != null || _formalPending != null ? null : () async {
            final day = await showDatePicker(context: context, initialDate: _month, firstDate: DateTime(2000), lastDate: DateTime(DateTime.now().year + 1, 12, 31));
            if (day != null && mounted) { setState(() => _month = DateTime(day.year, day.month)); _load(); }
          })),
        if (!_enabled) const Text('この追加機能はマスター設定でOFFです。保存データは残っています。'),
        if (editable) Wrap(spacing: 8, runSpacing: 8, children: [OutlinedButton.icon(onPressed: _reimport, icon: const Icon(Icons.sync), label: const Text('受信トークを再取込')),
          OutlinedButton.icon(onPressed: _history, icon: const Icon(Icons.paste), label: const Text('過去履歴を貼付'))]),
        if (_unreadable > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('読み取れない投稿 $_unreadable 件：元の投稿を確認してください。', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: workerOptions.containsKey(_workerFilter) ? _workerFilter : null, decoration: const InputDecoration(labelText: '個人別表示'),
          items: [const DropdownMenuItem<String>(value: null, child: Text('表示できる全員')), for (final item in workerOptions.entries) DropdownMenuItem(value: item.key, child: Text(item.value))],
          onChanged: _busy || _formalPending != null ? null : (value) => setState(() => _workerFilter = value)),
        if (widget.target == 'invoice') const Text('請求書はこの月の確認済み全員分を作成します。'),
        Text('確認済み集計', style: Theme.of(context).textTheme.titleMedium),
        if (totals.isEmpty) const Text('確認済みの候補はありません。'),
        for (final total in totals) ListTile(contentPadding: EdgeInsets.zero, title: Text(total['name'].toString()), subtitle: Text('人工 ${total['man_days']} ／ 残業 ${total['overtime_hours']}時間 ／ 早出 ${total['early_hours']}時間')),
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
          OutlinedButton.icon(onPressed: _busy || !_enabled || _dirty || _draftId == null || !_comparisonConfirmed || _pending != null ? null : _formal, icon: const Icon(Icons.fact_check_outlined), label: Text(_formalPending != null ? '同じ登録を再送' : widget.target == 'attendance' ? '署名して出勤を申請' : '金額を確認して請求書を作成')),
          const Text('出勤は既存の承認待ちへ、請求書は下書きとして保存します。同じ日の出勤や同じ月の請求書がある場合は、既存データの確認へ進んでください。'),
        ],
      ]));
  }
}
