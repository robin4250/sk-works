import 'line_release_access.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'line_historical_monthly_import.dart';
import 'line_import_page.dart';
import 'line_history_file_decoder.dart';
import 'line_import_repository.dart';

/// Saves reviewable monthly drafts through the existing authenticated contract.
class LineHistoricalMonthlyImportPage extends StatelessWidget {
  const LineHistoricalMonthlyImportPage({super.key, required this.groupId});
  final String groupId;
  @override
  Widget build(BuildContext context) => LineReleaseBoundary(builder: (_) => _LineHistoricalMonthlyImportPageContent(groupId: groupId));
}

class _LineHistoricalMonthlyImportPageContent extends StatefulWidget {
  const _LineHistoricalMonthlyImportPageContent({required this.groupId});
  final String groupId;
  @override
  State<_LineHistoricalMonthlyImportPageContent> createState() =>
      _LineHistoricalMonthlyImportPageState();
}
class _LineHistoricalMonthlyImportPageState
    extends State<_LineHistoricalMonthlyImportPageContent> {
  final _repository = LineImportRepository.maybeCreate();
  final _months = lineHistoryImportMonths();
  final _commands = <String, Map<String, dynamic>>{};
  final _status = <String, String>{};
  final _counts = <String, int>{};
  final _sourceCounts = <String, int>{};
  bool _replaceHistory = false;
  List<Map<String, dynamic>> _history = [];
  bool _busy = false, _enabled = false;
  String? _error, _fileName;
  String _key(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';
  @override
  void initState() { super.initState(); _loadFeatures(); }
  Future<void> _loadFeatures() async {
    try {
      final features = await _repository?.features();
      if (mounted) setState(() => _enabled = features?.invoice == true);
      if (_enabled && mounted && _commands.isEmpty) await _receive();
    } catch (_) {
      if (mounted) setState(() => _error = '取込設定とログイン状態を確認してください。');
    }
  }
  Future<void> _enable() async {
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _repository!.setEnabled('invoice', true);
      if (mounted) setState(() => _enabled = result.invoice);
      if (_enabled && mounted) await _receive();
    } catch (_) {
      if (mounted) setState(() => _error = 'マスター権限と取込設定を確認してください。');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _pick() async {
    setState(() { _busy = true; _error = null; });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['txt', 'zip']);
      if (file == null || !mounted) return;
      final length = await file.length();
      if (length != null && length > 5 * 1024 * 1024) {
        throw const FormatException('File too large');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('Empty or too large');
      }
      final fileHistory = lineHistorySources(decodeLineHistoryFile(bytes, file.name));
      if (fileHistory.isEmpty) throw const FormatException('No LINE messages');
      final received = await _repository!.sources(widget.groupId);
      final history = lineMergeImportSources(received, fileHistory);
      final counts = <String, int>{};
      final sourceCounts = <String, int>{};
      for (final month in _months) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        final candidates = lineMonthlyCandidates(history, month);
        counts[_key(month)] = candidates.rows.length;
        sourceCounts[_key(month)] = candidates.sources.length;
      }
      if (!mounted) return;
      setState(() {
        _history = history; _fileName = file.name; _counts.clear();
        _counts.addAll(counts); _sourceCounts.clear(); _sourceCounts.addAll(sourceCounts);
        _commands.clear(); _status.clear(); _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() =>
          _error = '5MB以下のUTF-8 LINE書き出しテキストを選択してください。');
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _receive() async {
    if (_repository == null || _commands.isNotEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final received = await _repository.sources(widget.groupId);
      final retainedHistory = _history.where(
        (source) => source['source_type'] == 'history').toList();
      final history = lineMergeImportSources(received, retainedHistory);
      final counts = <String, int>{}, sourceCounts = <String, int>{};
      for (final month in _months) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        final result = lineMonthlyCandidates(history, month);
        counts[_key(month)] = result.rows.length;
        sourceCounts[_key(month)] = result.sources.length;
      }
      if (mounted) {
        setState(() {
          _history = history; _counts.clear(); _counts.addAll(counts);
          _sourceCounts.clear(); _sourceCounts.addAll(sourceCounts); _status.clear();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '連携LINEの受信データを取得できませんでした。接続と権限を確認してください。');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || _history.isEmpty || !_enabled) return;
    setState(() { _busy = true; _error = null; });
    try {
      final refs = await repository.references(widget.groupId);
      final received = await repository.sources(widget.groupId);
      final incoming = lineMergeImportSources(_history, received);
      for (final month in _months) {
        if (!mounted) return;
        final key = _key(month);
        // A partial September/October file must never clear unrelated months.
        if (lineMonthlyCandidates(incoming, month).sources.isEmpty ||
            _status[key] == '保存済み') {
          continue;
        }
        setState(() => _status[key] = '保存中');
        try {
          if (!_commands.containsKey(key)) {
            final workspace = await repository.load(widget.groupId, 'invoice', month);
            if (workspace['can_edit'] != true) throw StateError('Invoice management required');
            final previous = [for (final row in workspace['candidate_rows'] as List)
              Map<String, dynamic>.from(row as Map)];
            final existing = [for (final source in workspace['source_messages'] as List)
              <String, dynamic>{...Map<String, dynamic>.from(source as Map),
                'source_type': source['source_type'] ?? workspace['source_kind']}];
            final merged = lineMergeImportSources(existing, incoming,
              replaceHistory: _replaceHistory);
            final prepared = lineMonthlyCandidates(merged, month,
              previous: previous, workers: refs.workers, sites: refs.sites);
            final types = prepared.sources.map((s) => s['source_type']).toSet();
            _commands[key] = repository.saveCommand(
              groupId: widget.groupId, target: 'invoice', month: month,
              revision: workspace['revision'] as int,
              sourceKind: types.length > 1 ? 'mixed' : types.isEmpty ? 'history' : types.single.toString(),
              sources: prepared.sources, rows: prepared.rows,
              note: workspace['note_comparison']?.toString() ?? '', confirmed: false);
          }
          await repository.save(_commands[key]!);
          _commands.remove(key);
          if (mounted) setState(() => _status[key] = '保存済み');
        } on PostgrestException catch (error) {
          if (['22023', '40001', '42501'].contains(error.code)) {
            _commands.remove(key);
          }
          if (mounted) {
            setState(() => _status[key] = error.code == '40001'
              ? '保存版が変更・再取得して再送' : '入力・権限を確認して再送');
          }
        } catch (_) {
          // Keep the exact command ID/payload after an ambiguous response.
          if (mounted) setState(() => _status[key] = '未確認・同じ保存を再送');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = '編集権限・会社・接続を確認してください。');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _open(DateTime month) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      LineImportPage(target: 'invoice', initialGroupId: widget.groupId,
        initialMonth: month)));
    if (mounted) await _loadFeatures();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LINE月別表の取込')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('2024年1月〜${_months.last.year}年${_months.last.month}月（過去33ヶ月と追加月）'),
      const SizedBox(height: 8),
      const Text('LINEの書き出しファイルを一度選び、月別の候補として保存します。各月を開いて作業員・現場・数量を照合してから、単価設定と請求書へ進んでください。再取込は変わっていない投稿の修正を保持し、変わった投稿を要確認に戻します。'),
      const SizedBox(height: 12),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (!_enabled) OutlinedButton(onPressed: _busy || _repository == null ? null : _enable,
        child: const Text('マスター設定で請求書取込を有効にする')),
      OutlinedButton.icon(onPressed: _busy || _commands.isNotEmpty || _repository == null ? null : _pick,
        icon: const Icon(Icons.file_open_outlined),
        label: Text(_fileName ?? 'LINE書き出しファイル（TXT・ZIP）を選択')),
      OutlinedButton.icon(
        onPressed: _busy || _commands.isNotEmpty || _repository == null ? null : _receive,
        icon: const Icon(Icons.sync),
        label: const Text('連携LINEの受信データを更新'),
      ),
      const Text('受信済みの投稿も同じ月別表に含めます。ファイルと一致する投稿はまとめ、曖昧な重複は要確認にします。'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('対象月の過去履歴を入れ替える'),
        subtitle: const Text('通常は既存の履歴を残して不足分を追加します。入れ替えはファイルに投稿がある月だけ。受信トークは残します。'),
        value: _replaceHistory,
        onChanged: _busy || _commands.isNotEmpty ? null :
          (value) => setState(() => _replaceHistory = value),
      ),
      FilledButton(onPressed: _busy || !_enabled || _history.isEmpty ? null : _save,
        child: const Text('ファイル・受信データの対象月を保存・未確認分を再送')),
      const SizedBox(height: 12),
      for (final month in _months) Card(child: ListTile(
        title: Text('${month.year}年${month.month}月'),
        subtitle: Text((_counts.containsKey(_key(month)) ?
          '今回の投稿から候補 ${_counts[_key(month)]}件 ／ ' : '') +
          (_status[_key(month)] ?? ((_sourceCounts[_key(month)] ?? 0) == 0 && _history.isNotEmpty
            ? '今回のファイル・受信データに対象投稿なし・保存版を維持' : '月別表を開いて確認・入れ直し'))),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : () => _open(month))),
    ]),
  );
}

