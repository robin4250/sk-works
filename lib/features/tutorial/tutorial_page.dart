import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'tutorial_evidence_repository.dart';
import 'tutorial_preferences.dart';
import 'tutorial_progress.dart' as model;
import 'tutorial_workspace.dart';

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key, required this.userId, required this.companyId,
    required this.availableActionKeys, required this.onOpenAction,
    this.repository, this.loadSnapshot, this.preferences});

  final String userId;
  final String companyId;
  final Set<String> availableActionKeys;
  final TutorialOpenAction onOpenAction;
  final TutorialEvidenceRepository? repository;
  final TutorialSnapshotLoader? loadSnapshot;
  final TutorialPreferences? preferences;

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> with WidgetsBindingObserver {
  TutorialWorkspace? _workspace;
  bool _loading = true;
  bool _opening = false;
  String? _error;
  String? _guidedTaskId;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TutorialPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId || widget.companyId != oldWidget.companyId ||
        widget.availableActionKeys.length != oldWidget.availableActionKeys.length ||
        !widget.availableActionKeys.containsAll(oldWidget.availableActionKeys)) {
      _workspace = null; _guidedTaskId = null; _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_opening) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    final userId = widget.userId;
    final companyId = widget.companyId;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final loader = widget.loadSnapshot;
      final repository = widget.repository ?? TutorialEvidenceRepository.maybeCreate();
      if (loader == null && repository == null) throw StateError('Tutorial evidence unavailable');
      final snapshot = loader != null
          ? await loader(Set.unmodifiable(widget.availableActionKeys))
          : await repository!.load(availableActionKeys: widget.availableActionKeys);
      final workspace = TutorialWorkspace.fromSnapshot(snapshot);
      if (!mounted || request != _request) return;
      if (workspace.canCompleteInitial) {
        await (widget.preferences ?? TutorialPreferences()).markInitialCompleted(
          userId: userId, companyId: companyId);
      }
      if (!mounted || request != _request) return;
      setState(() {
        _workspace = workspace;
        _guidedTaskId ??= workspace.nextTaskId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() { _workspace = null; _loading = false; _error = '準備状況を確認できません。再読み込みしてください。'; });
    }
  }

  Future<void> _open(String taskId) async {
    final task = _workspace?.tasksById[taskId];
    if (_opening || task == null || !widget.availableActionKeys.contains(task.actionKey)) return;
    setState(() { _opening = true; _guidedTaskId = taskId; });
    try {
      // The caller uses the same existing protected route as a normal button.
      await widget.onOpenAction(task.actionKey);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('この項目を開けません。利用権限を確認してください。'))));
    } finally {
      if (mounted) { setState(() => _opening = false); await _refresh(); }
    }
  }

  void _restartGuide() {
    final tasks = _workspace?.progress.tasks;
    if (tasks == null || tasks.isEmpty) return;
    // Explanation cursor only: never clear evidence, records or completion flag.
    setState(() => _guidedTaskId = tasks.first.task.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      SkoLanguageController.tr('案内を初めから表示します。登録済みデータはそのままです。'))));
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('初期準備ガイド')),
        actions: [IconButton(onPressed: _loading || _opening ? null : _refresh,
          tooltip: SkoLanguageController.tr('再読み込み'), icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: _loading && workspace == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          if (_error != null) ...[
            Text(SkoLanguageController.tr(_error!)),
            TextButton(onPressed: _refresh, child: Text(SkoLanguageController.tr('再読み込み'))),
          ],
          if (workspace != null) ...[
            TutorialProgressSummary(counts: workspace.progress.required, title: '必須の準備'),
            const SizedBox(height: 12),
            Text(SkoLanguageController.tr('登録済みの内容で進行率が更新されます。通常の登録画面から保存しても反映されます。')),
            if (workspace.canCompleteInitial) ...[
              const SizedBox(height: 12),
              Text(SkoLanguageController.tr('初期準備は完了しました。案内はいつでも開き直せます。')),
              if (widget.availableActionKeys.contains('help'))
                FilledButton.icon(
                  onPressed: _opening ? null : () => widget.onOpenAction('help'),
                  icon: const Icon(Icons.help_outline),
                  label: Text(SkoLanguageController.tr('利用方法を見る')),
                ),
            ],
            const SizedBox(height: 16),
            for (final requirement in [model.TutorialRequirement.required, model.TutorialRequirement.recommended]) ...[
              if (workspace.progress.tasks.any((t) => t.task.requirement == requirement)) ...[
                Text(SkoLanguageController.tr(requirement == model.TutorialRequirement.required ? '必須項目' : '推奨項目（任意）'),
                  style: Theme.of(context).textTheme.titleMedium),
                for (final task in workspace.progress.tasks.where((t) => t.task.requirement == requirement))
                  _taskCard(workspace, task),
                const SizedBox(height: 12),
              ],
            ],
            if (workspace.progress.recommended.total > 0 || !workspace.progress.recommended.isKnown)
              TutorialProgressSummary(counts: workspace.progress.recommended, title: '推奨項目（任意）'),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _opening ? null : _restartGuide,
              icon: const Icon(Icons.restart_alt), label: Text(SkoLanguageController.tr('案内を初めから'))),
          ],
        ])),
    );
  }

  Widget _taskCard(TutorialWorkspace workspace, model.TutorialTaskProgress task) {
    final sourceTask = workspace.tasksById[task.task.id]!;
    final enabled = !_opening && widget.availableActionKeys.contains(sourceTask.actionKey);
    final selected = _guidedTaskId == task.task.id;
    return Card(shape: selected ? RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.primary)) : null,
      child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(SkoLanguageController.tr(task.task.title), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final checkpoint in sourceTask.checkpoints) Row(children: [
            Icon(switch (checkpoint.state) {
              TutorialEvidenceState.saved => checkpoint.evidenceKey?.trim().isNotEmpty == true
                ? Icons.check_circle_outline : Icons.help_outline,
              TutorialEvidenceState.missing => Icons.radio_button_unchecked,
              TutorialEvidenceState.unknown => Icons.help_outline,
              TutorialEvidenceState.notApplicable => Icons.remove_circle_outline,
            }, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(SkoLanguageController.tr(checkpoint.label))),
            Text(SkoLanguageController.tr(switch (checkpoint.state) {
              TutorialEvidenceState.saved => checkpoint.evidenceKey?.trim().isNotEmpty == true ? '登録済み' : '未確定',
              TutorialEvidenceState.missing => '未登録',
              TutorialEvidenceState.unknown => '未確定',
              TutorialEvidenceState.notApplicable => '対象外',
            })),
          ]),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: enabled ? () => _open(task.task.id) : null,
            child: Text(SkoLanguageController.tr(task.counts.isComplete ? '登録画面を開き直す' : '登録画面を開く'))),
        ])));
  }
}

class TutorialProgressSummary extends StatelessWidget {
  const TutorialProgressSummary({super.key, required this.counts, required this.title});
  final model.TutorialCounts counts;
  final String title;

  @override
  Widget build(BuildContext context) {
    final percentage = counts.percentage;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(SkoLanguageController.tr(title), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(percentage != null
        ? SkoLanguageController.trParams('準備 {ready}% / 残り {remaining}%（あと{count}項目）', {
          'ready': percentage.toStringAsFixed(0), 'remaining': (100 - percentage).toStringAsFixed(0),
          'count': counts.remaining ?? 0})
        : SkoLanguageController.tr(counts.isKnown ? '対象の準備項目はありません' : '準備状況：未確定'),
        style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      if (percentage != null) LinearProgressIndicator(value: percentage / 100),
      const SizedBox(height: 6),
      Text(SkoLanguageController.trParams('登録済み {completed}/{total} 項目', {
        'completed': counts.completed, 'total': counts.total})),
      if (!counts.isKnown) Text(SkoLanguageController.tr('未取得の項目を確認するまで進行率は確定しません。')),
      if (counts.excludedNotApplicableCheckpoints > 0)
        Text(SkoLanguageController.trParams('対象外 {count} 項目は進行率に含めません。', {'count': counts.excludedNotApplicableCheckpoints})),
    ]);
  }
}
