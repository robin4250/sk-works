import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'line_import_draft.dart';
import 'line_import_repository.dart';
import 'line_reading_rules.dart';
import 'line_release_access.dart';

class LineReadingReapplyPage extends StatelessWidget {
  const LineReadingReapplyPage({super.key, required this.groupId, required this.month,
    this.repositoryOverride});
  final String groupId;
  final DateTime month;
  final LineImportRepository? repositoryOverride;
  @override
  Widget build(BuildContext context) => LineReleaseBoundary(builder: (_) =>
    _Reapply(groupId: groupId, month: month, repository: repositoryOverride));
}

class _Reapply extends StatefulWidget {
  const _Reapply({required this.groupId, required this.month, this.repository});
  final String groupId;
  final DateTime month;
  final LineImportRepository? repository;
  @override
  State<_Reapply> createState() => _ReapplyState();
}

class _ReapplyState extends State<_Reapply> {
  late final repo = widget.repository ?? LineImportRepository.maybeCreate();
  Map<String, dynamic>? workspace, pending;
  List<Map<String, dynamic>> rows = [], suggestions = [], sites = [], workers = [];
  final selected = <String, String>{}, accepted = <String, String>{};
  bool busy = true;
  int protectedCount = 0;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { busy = true; error = null; });
    try {
      final data = await repo!.load(widget.groupId, 'invoice', widget.month);
      if (data['can_edit'] != true || LineImportFeatures.fromJson(data['features']).invoice != true) {
        throw StateError('Invoice editing required');
      }
      final rules = await repo!.readingRules(widget.groupId);
      final refs = await repo!.references(widget.groupId);
      final loaded = [for (final raw in data['candidate_rows'] as List) Map<String,dynamic>.from(raw as Map)];
      final sources = [for (final raw in data['source_messages'] as List) Map<String,dynamic>.from(raw as Map)];
      final eligible = loaded.where((row) => lineReadingReapplyEligible(row) &&
        sources.where((source) => source['id'] == row['source_message_id'] &&
          lineSourceFingerprint(source) == row['source_fingerprint']).length == 1).toList();
      final proposed = lineReadingSuggestions(eligible, rules);
      if (!mounted) return;
      setState(() {
        workspace = data; rows = loaded; sites = refs.sites; workers = refs.workers;
        suggestions = proposed; protectedCount = loaded.length - eligible.length;
        selected.clear(); accepted.clear(); pending = null;
        for (final proposal in proposed) {
          final targets = lineReadingUniqueTargets(proposal['field'] == 'site_name' ? sites : workers)
            .where((target) => target['name'] == proposal['after']).toList();
          if (targets.length == 1) selected[lineReadingSuggestionKey(proposal)] = '${targets.single['id']}';
        }
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '再適用候補を取得できません。マスター権限・接続・設定を確認してください。');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _save() async {
    if (workspace == null || accepted.isEmpty) return;
    pending ??= repo!.saveCommand(groupId: widget.groupId, target: 'invoice', month: widget.month,
      revision: workspace!['revision'] as int, sourceKind: '${workspace!['source_kind']}',
      sources: [for (final raw in workspace!['source_messages'] as List) Map<String,dynamic>.from(raw as Map)],
      rows: lineAcceptReadingSuggestions(rows, suggestions, accepted, sites: sites, workers: workers),
      note: '${workspace!['note_comparison'] ?? ''}', confirmed: false);
    setState(() { busy = true; error = null; });
    try {
      await repo!.save(pending!);
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
        if (['40001','42501','22023'].contains(e.code)) {
          pending = null; accepted.clear();
          error = '保存元が変更されたか権限が変わりました。再読込して前後を確認し直してください。';
        } else { error = '保存結果を確認できません。同じ内容を再送できます。'; }
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '保存結果を確認できません。同じ内容を再送できます。');
    } finally { if (mounted) setState(() => busy = false); }
  }

  void _help() => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('語句ルールの再適用'),
    content: const Text('自動生成の由来が確認できる未確認行だけを提案します。旧行・確認済み・手修正・除外行は保護し、月別表の個別編集を使います。変更前後を見て、必要な項目だけ「この項目を採用」を押し、最後に「採用した項目だけ保存」を押します。保留の候補は登録済みの一意な対象を選び直せます。同名対象を解消できない場合は個別編集してください。数量・原文・他の仮状態は変更せず、確認済みや正式請求には自動で進みません。'),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('語句ルールの再適用'), actions: [
      IconButton(onPressed: _help, icon: const Icon(Icons.help_outline), tooltip: '使い方'),
      IconButton(onPressed: busy || pending != null ? null : _load, icon: const Icon(Icons.refresh), tooltip: '再読込'),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      Text('保護する行 $protectedCount件。旧行・確認済み・手修正は月別表で個別編集してください。'),
      if (!busy && suggestions.isEmpty) const Text('再適用できる変更候補はありません。'),
      for (final proposal in suggestions) _proposal(proposal),
    ]),
    bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child:
      FilledButton(onPressed: busy || accepted.isEmpty ? null : _save,
        child: Text(pending != null ? '同じ内容を再送' : '採用した項目だけ保存')))),
  );

  Widget _proposal(Map<String, dynamic> proposal) {
    final key = lineReadingSuggestionKey(proposal);
    final targets = lineReadingUniqueTargets(proposal['field'] == 'site_name' ? sites : workers);
    final chosen = targets.where((target) => '${target['id']}' == selected[key]).toList();
    final after = chosen.length == 1 ? chosen.single['name'] : proposal['after'];
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${proposal['field'] == 'site_name' ? '現場' : '従業員'}：${proposal['before']} → $after'),
        DropdownButtonFormField<String>(key: ValueKey('target-$key'), initialValue: selected[key],
          hint: const Text('保留・登録済み対象を選び直す'), isExpanded: true,
          items: [for (final target in targets) DropdownMenuItem(value: '${target['id']}', child: Text('${target['name']}'))],
          onChanged: busy || pending != null ? null : (value) => setState(() {
            accepted.remove(key);
            if (value == null) { selected.remove(key); } else { selected[key] = value; }
          })),
        Text(accepted.containsKey(key) ? '採用予定・保存で反映' : selected[key] == null ? '保留・一意な登録先が必要です' : '候補・まだ反映していません'),
        TextButton(onPressed: busy || pending != null || selected[key] == null ? null : () => setState(() {
          accepted[key] = selected[key]!;
        }), child: const Text('この項目を採用')),
      ])));
  }
}
