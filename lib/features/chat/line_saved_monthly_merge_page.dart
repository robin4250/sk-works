import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'line_release_access.dart';
import 'line_import_repository.dart';
import 'line_saved_monthly_merge.dart';
import 'line_saved_monthly_merge_repository.dart';

/// Adds a snapshot of another saved monthly draft, never moves its originals.
class LineSavedMonthlyMergePage extends StatelessWidget {
  const LineSavedMonthlyMergePage({super.key, required this.groupId,
    required this.groupName, required this.month, this.repository});
  final String groupId, groupName;
  final DateTime month;
  final LineSavedMonthlyMergeRepository? repository;

  @override
  Widget build(BuildContext context) => LineReleaseBoundary(builder: (_) =>
    _MergeContent(groupId: groupId, groupName: groupName, month: month,
      repository: repository));
}

class _MergeContent extends StatefulWidget {
  const _MergeContent({required this.groupId, required this.groupName,
    required this.month, this.repository});
  final String groupId, groupName;
  final DateTime month;
  final LineSavedMonthlyMergeRepository? repository;
  @override
  State<_MergeContent> createState() => _MergeState();
}

class _MergeState extends State<_MergeContent> {
  LineSavedMonthlyMergeRepository? _repository;
  List<Map<String, dynamic>> _groups = [];
  String? _source, _error;
  Map<String, dynamic>? _targetWorkspace, _sourceWorkspace, _pending;
  LineSavedMonthlyMergePreview? _preview;
  bool _busy = true, _blocked = false, _checked = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    try {
      _repository = widget.repository ?? LineSavedMonthlyMergeRepository.maybeCreate();
      _repository?.addListener(_identityChanged);
    } catch (_) { /* Fail closed without retaining another session's data. */ }
    _initialize();
  }

  bool _live(int generation) {
    if (!mounted || _blocked || generation != _generation) return false;
    if (_repository?.isCurrent == true) return true;
    // Admission can fail before the listener observes an auth event. Retire the
    // page and clear its busy state even in that initial failure path.
    _identityChanged();
    return false;
  }

  void _identityChanged() {
    if (!mounted || _blocked || _repository?.isCurrent == true) return;
    _generation++;
    setState(() {
      _blocked = true; _busy = false; _groups = []; _source = null;
      _preview = null; _targetWorkspace = null; _sourceWorkspace = null;
      _pending = null; _checked = false;
      _error = 'ログイン状態が変わりました。画面を開き直してください。';
    });
  }

  Future<void> _initialize() async {
    final repository = _repository;
    if (repository == null) {
      if (mounted) setState(() { _busy = false; _error = '接続とログイン状態を確認してください。'; });
      return;
    }
    final generation = ++_generation;
    try {
      final groups = await repository.destinations();
      if (!_live(generation)) return;
      setState(() {
        _groups = groups.where((group) => group['id'].toString() != widget.groupId &&
          group['group_type'] != 'direct').toList();
        _busy = false;
      });
    } catch (_) {
      if (_live(generation)) setState(() { _busy = false; _error = '保存済みグループを確認できません。画面を開き直してください。'; });
    }
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List || value.any((row) => row is! Map)) {
      throw StateError('保存済みデータの形式を確認できません。');
    }
    return [for (final row in value) Map<String, dynamic>.from(row as Map)];
  }

  void _requireWorkspace(Map<String, dynamic> workspace) {
    if (workspace['can_edit'] != true ||
        !LineImportFeatures.fromJson(workspace['features']).invoice) {
      throw StateError('対象グループの権限と取込設定を確認してください。');
    }
  }

  Object? _canonical(Object? value) {
    if (value is List) return value.map(_canonical).toList();
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is num) return value.toDouble();
    return value;
  }
  bool _same(Object? a, Object? b) => jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

  Future<void> _prepare() async {
    final repository = _repository, source = _source;
    if (_busy || _blocked || _pending != null || repository == null || source == null) return;
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; _preview = null; _checked = false; });
    try {
      await repository.verifyGroups(widget.groupId, source);
      final target = await repository.load(widget.groupId, widget.month);
      final incoming = await repository.load(source, widget.month);
      _requireWorkspace(target); _requireWorkspace(incoming);
      final preview = linePreviewSavedMonthlyMerge(month: widget.month,
        sourceGroupId: source, targetSources: _maps(target['source_messages']),
        targetRows: _maps(target['candidate_rows']),
        incomingSources: _maps(incoming['source_messages']),
        incomingRows: _maps(incoming['candidate_rows']));
      if (!_live(generation)) return;
      setState(() { _targetWorkspace = target; _sourceWorkspace = incoming;
        _preview = preview; _busy = false; });
    } catch (_) {
      if (_live(generation)) {
        setState(() { _busy = false;
          _error = '保存済みデータを取得できません。対象グループの権限と接続を確認してください。'; });
      }
    }
  }

  bool get _changed => _preview != null && _targetWorkspace != null &&
    (!_same(_preview!.rows, _targetWorkspace!['candidate_rows']) ||
     !_same(_preview!.sources, _targetWorkspace!['source_messages']));

  bool _matchesSaved(Map<String, dynamic> value, Map<String, dynamic> command) =>
    value['revision'] == (command['p_expected_revision'] as int) + 1 &&
    value['confirmed'] == command['p_confirmed'] &&
    value['source_kind'] == command['p_source_kind'] &&
    _same(value['candidate_rows'], command['p_rows']) &&
    _same(value['source_messages'], command['p_sources']) &&
    value['note_comparison'] == command['p_note'];

  Future<void> _save() async {
    final repository = _repository, preview = _preview, source = _source;
    if (_busy || _blocked || !_checked || _pending != null || !_changed ||
        repository == null || preview == null || !preview.canSave || source == null) {
      return;
    }
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; });
    var sent = false;
    try {
      await repository.verifyGroups(widget.groupId, source);
      final latestSource = await repository.load(source, widget.month);
      _requireWorkspace(latestSource);
      if (latestSource['revision'] != _sourceWorkspace!['revision'] ||
          !_same(latestSource['source_messages'], _sourceWorkspace!['source_messages']) ||
          !_same(latestSource['candidate_rows'], _sourceWorkspace!['candidate_rows'])) {
        throw StateError('追加元が変更されました。もう一度内容を確認してください。');
      }
      final latestTarget = await repository.load(widget.groupId, widget.month);
      _requireWorkspace(latestTarget);
      if (latestTarget['revision'] != _targetWorkspace!['revision']) {
        throw StateError('まとめ先が変更されました。もう一度内容を確認してください。');
      }
      if (!_live(generation)) return;
      final types = preview.sources.map((s) => s['source_type']).toSet();
      _pending = repository.saveCommand(groupId: widget.groupId,
        target: 'invoice', month: widget.month,
        revision: _targetWorkspace!['revision'] as int,
        sourceKind: types.length > 1 ? 'mixed' : 'history',
        sources: preview.sources, rows: preview.rows,
        note: _targetWorkspace!['note_comparison']?.toString() ?? '',
        confirmed: false);
      sent = true;
      final result = await repository.save(_pending!);
      if (!_live(generation)) return;
      if (!_matchesSaved(result, _pending!)) throw StateError('保存結果が一致しません。');
      _pending = null;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!_live(generation)) return;
      if (['22023', '40001', '42501'].contains(error.code)) _pending = null;
      setState(() { _busy = false; _checked = false;
        if (_pending == null) _preview = null;
        _error = _pending == null
          ? '保存できませんでした。最新の内容・権限を確認してから、追加内容を再確認してください。'
          : '保存結果が未確認です。「保存結果を確認」で照会してください。再送は行いません。'; });
    } catch (_) {
      if (!_live(generation)) return;
      setState(() { _busy = false; _checked = false;
        if (!sent) _preview = null;
        _error = sent
          ? '保存結果が未確認です。「保存結果を確認」で照会してください。再送は行いません。'
          : 'データが更新されたか、接続を確認できません。追加内容をもう一度確認してください。'; });
    }
  }

  Future<void> _verifyOutcome() async {
    final repository = _repository, command = _pending;
    if (_busy || _blocked || repository == null || command == null) return;
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await repository.load(widget.groupId, widget.month);
      if (!_live(generation)) return;
      if (_matchesSaved(result, command)) {
        _pending = null;
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      setState(() { _busy = false; _error = '保存結果を特定できません。元データと操作内容を保持し、自動再送はしません。'; });
    } catch (_) {
      if (_live(generation)) setState(() { _busy = false; _error = '保存結果を照会できません。接続を確認してから、もう一度照会してください。'; });
    }
  }

  @override
  void dispose() {
    _generation++; _repository?.removeListener(_identityChanged);
    if (widget.repository == null && _repository != null) unawaited(_repository!.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PopScope(canPop: !_busy && (_pending == null || _blocked),
      child: Scaffold(appBar: AppBar(title: const Text('保存済みデータを追加')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!_blocked) ...[
            Text('まとめ先：${widget.groupName}', style: Theme.of(context).textTheme.titleMedium),
            Text('対象：${widget.month.year}年${widget.month.month}月'),
            const Text('別グループの保存済みデータを追加します。元グループの原文・データと既存の手直しを残します。正式請求書は発行・送信しません。'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(initialValue: _source,
              isExpanded: true, decoration: const InputDecoration(labelText: '追加元のグループ'),
              items: [for (final group in _groups) DropdownMenuItem(
                value: group['id'].toString(), child: Text(
                  group['display_name']?.toString() ?? group['name']?.toString() ?? '保存済みグループ',
                  maxLines: 2, overflow: TextOverflow.ellipsis))],
              onChanged: _busy || _pending != null ? null : (value) => setState(() {
                _source = value; _preview = null; _checked = false; _error = null;
              })),
            if (!_busy && _groups.isEmpty) const Text('追加元として選べる別グループはありません。'),
            OutlinedButton(onPressed: _busy || _source == null || _pending != null ? null : _prepare,
              child: const Text('追加内容を確認')),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!_blocked && preview != null) ...[
            const Divider(),
            Text('追加 ${preview.addedCount}件 ／ 一致する重複 ${preview.duplicateCount}件 ／ 内容の相違 ${preview.conflictCount}件'),
            Text('対象月外 ${preview.outOfMonthCount}件 ／ 除外 ${preview.excludedCount}件 ／ 要確認 ${preview.reviewCount}件'),
            Text('統合後の対象日：${preview.workDates.isEmpty ? 'なし' : preview.workDates.join('、')}'),
            for (final conflict in preview.conflicts)
              if (conflict.beforeBody != null || conflict.afterBody != null)
                ExpansionTile(title: Text(conflict.description,
                  style: TextStyle(color: conflict.blocking ? Theme.of(context).colorScheme.error : null)),
                  children: [
                    const Text('保存済みの原文'),
                    Padding(padding: const EdgeInsets.all(12),
                      child: SelectableText(conflict.beforeBody ?? '原文なし')),
                    const Text('今回追加しようとした原文'),
                    Padding(padding: const EdgeInsets.all(12),
                      child: SelectableText(conflict.afterBody ?? '原文なし')),
                  ])
              else Text(conflict.description,
                style: TextStyle(color: conflict.blocking ? Theme.of(context).colorScheme.error : null)),
            ExpansionTile(title: const Text('対象行・相違の内容と原文を確認'), children: [
              for (final row in preview.rows) ListTile(dense: true,
                title: Text('${row['work_date']} ／ ${row['site_name']} ／ ${row['worker_name']} ／ ${row['work_category']}'),
                subtitle: Text('人工 ${row['man_days']}・残業 ${row['overtime_hours']}・早出 ${row['early_hours']}・手当 ${row['allowance_names']}\n'
                  '${row['excluded'] == true ? '除外' : row['confirmed'] == true ? '確認済み' : '要確認'} ${row['review_reason'] ?? ''}')),
              for (final source in preview.sources) ExpansionTile(
                title: Text('原文 ${source['sent_at']} ${source['sender_display_name'] ?? ''}'),
                children: [Padding(padding: const EdgeInsets.all(12),
                  child: SelectableText(source['body']?.toString() ?? ''))]),
            ]),
            const Text('一致する重複と内容の相違は二重計上せず、原文を残します。相違のある記録は既存内容を上書きせず除外し、月別表で確認できます。'),
            if (!preview.canSave) const Text('ソースの衝突があります。追加せず、元データを確認してください。'),
            if (!_changed && preview.canSave) const Text('追加済み、または追加対象がありません。保存は不要です。'),
            CheckboxListTile(value: _checked, contentPadding: EdgeInsets.zero,
              title: const Text('対象日・件数・重複・相違を確認しました'),
              onChanged: _busy || _pending != null ? null : (value) => setState(() => _checked = value == true)),
            FilledButton(onPressed: _busy || !_checked || !preview.canSave || !_changed || _pending != null ? null : _save,
              child: const Text('まとめ先へ追加する')),
          ],
          if (!_blocked && _pending != null) OutlinedButton(onPressed: _busy ? null : _verifyOutcome,
            child: const Text('保存結果を確認')),
        ]))));
  }
}
