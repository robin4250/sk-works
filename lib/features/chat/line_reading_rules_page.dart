import 'package:flutter/material.dart';

import 'line_reading_rules.dart';
import 'line_reading_rules_repository.dart';
import 'line_import_repository.dart';

class LineReadingRulesPage extends StatefulWidget {
  const LineReadingRulesPage({
    super.key,
    required this.groupId,
    required this.sources,
    this.repository,
  });
  final String groupId;
  final List<Map<String, dynamic>> sources;
  final LineReadingRulesRepository? repository;
  @override
  State<LineReadingRulesPage> createState() => _LineReadingRulesPageState();
}

class _LineReadingRulesPageState extends State<LineReadingRulesPage> {
  late final repo =
      widget.repository ?? LineReadingRulesRepository.maybeCreate();
  List<LineReadingRule> rules = [];
  List<Map<String, dynamic>> sites = [], workers = [];
  int revision = 0;
  bool loading = true, editable = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await repo?.load(widget.groupId);
      final refs = await LineImportRepository.maybeCreate()?.references(
        widget.groupId,
      );
      if (data == null) throw StateError('ログインを確認してください。');
      if (!mounted) return;
      setState(() {
        rules = (data['rules'] as List)
            .map((v) => LineReadingRule.fromJson(v as Map))
            .toList();
        revision = data['revision'] as int;
        editable = data['can_edit'] == true;
        sites = refs?.sites ?? [];
        workers = refs?.workers ?? [];
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '設定を取得できませんでした。再読込してください。';
          loading = false;
        });
      }
    }
  }

  Future<void> _edit(String phrase) async {
    final initial = lineAutomaticReadingRule(
      phrase,
      saved: rules,
      sites: sites,
      workers: workers,
    );
    var kind = initial?.kind ?? LineReadingKind.site;
    final controller = TextEditingController(text: initial?.value ?? phrase);
    final result = await showDialog<LineReadingRule>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('「$phrase」の振り分け'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<LineReadingKind>(
                value: kind,
                isExpanded: true,
                items: [
                  for (final k in LineReadingKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (k) {
                  if (k != null) update(() => kind = k);
                },
              ),
              TextField(
                controller: controller,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '正式名称・読み取り値'),
              ),
              if (kind == LineReadingKind.site ||
                  kind == LineReadingKind.worker)
                DropdownButton<String>(
                  hint: const Text('登録済みの対象を選ぶ'),
                  isExpanded: true,
                  items: [
                    for (final name
                        in (kind == LineReadingKind.site ? sites : workers)
                            .map((v) => v['name']?.toString() ?? '')
                            .where((v) => v.isNotEmpty)
                            .toSet())
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.text = value;
                  },
                ),
              const Text('元の投稿は変更しません。曖昧な読み取りは月別表で確認します。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(
                    context,
                    LineReadingRule(
                      phrase: phrase,
                      kind: kind,
                      value: controller.text.trim(),
                    ),
                  );
                }
              },
              child: const Text('設定'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null && mounted) {
      setState(() {
        rules.removeWhere((r) => r.phrase == result.phrase);
        rules.add(result);
      });
    }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final result = await repo!.save(widget.groupId, revision, rules);
      if (!mounted) return;
      setState(() => revision = result['revision'] as int);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('読み取りルールを保存しました。過去の表・承認済みデータは変更していません。')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存できませんでした。他の更新がある場合は再読込してください。')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phrases = lineReadingPhrases(widget.sources);
    return Scaffold(
      appBar: AppBar(title: const Text('初期設定・読み取りルール')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(onPressed: _load, child: const Text('再読込')),
                ],
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '繰り返し使う語句を選んで、現場・氏名・手当などに振り分けます。原文と出典は保持します。既存の手修正・確定データを自動で上書きしません。',
                  ),
                ),
                for (final r in rules)
                  ListTile(
                    title: Text('${r.phrase} → ${r.value}'),
                    subtitle: Text('保存する設定・${r.kind.label}'),
                    trailing: IconButton(
                      tooltip: 'ルールを削除',
                      onPressed: editable && !busy
                          ? () => setState(() => rules.remove(r))
                          : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                const Divider(),
                if (phrases.isEmpty)
                  const ListTile(title: Text('元データを取り込むと語句が表示されます')),
                for (final p in phrases)
                  ListTile(
                    title: Text('${p.phrase}　${p.count}回'),
                    subtitle: Text(
                      rules.any((r) => r.phrase == p.phrase)
                          ? '手動設定済み'
                          : lineAutomaticReadingRule(
                                  p.phrase,
                                  sites: sites,
                                  workers: workers,
                                ) !=
                                null
                          ? '自動候補・確認してください'
                          : '要確認・未設定',
                    ),
                    trailing: OutlinedButton(
                      onPressed: editable && !busy
                          ? () => _edit(p.phrase)
                          : null,
                      child: Text(
                        lineAutomaticReadingRule(
                              p.phrase,
                              saved: rules,
                              sites: sites,
                              workers: workers,
                            )?.kind.label ??
                            '振り分け先',
                      ),
                    ),
                    onTap: editable && !busy ? () => _edit(p.phrase) : null,
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: editable && !busy ? _save : null,
            child: Text(busy ? '保存中…' : '読み取りルールを保存'),
          ),
        ),
      ),
    );
  }
}
