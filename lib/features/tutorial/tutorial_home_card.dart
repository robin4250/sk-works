import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'tutorial_evidence_repository.dart';
import 'tutorial_page.dart';
import 'tutorial_preferences.dart';
import 'tutorial_workspace.dart';

/// Parent places this card in the fixed top area, above normal home content.
class TutorialHomeCard extends StatefulWidget {
  const TutorialHomeCard({super.key, required this.userId, required this.companyId,
    required this.availableActionKeys, required this.onOpenAction,
    this.repository, this.loadSnapshot, this.preferences, this.refreshToken});

  final String userId;
  final String companyId;
  final Set<String> availableActionKeys;
  final TutorialOpenAction onOpenAction;
  final TutorialEvidenceRepository? repository;
  final TutorialSnapshotLoader? loadSnapshot;
  final TutorialPreferences? preferences;

  /// Change after returning from any existing data-edit page, not only this guide.
  final Object? refreshToken;

  @override
  State<TutorialHomeCard> createState() => _TutorialHomeCardState();
}

class _TutorialHomeCardState extends State<TutorialHomeCard> with WidgetsBindingObserver {
  TutorialWorkspace? _workspace;
  bool _completed = false;
  bool _loading = true;
  bool _opening = false;
  String? _error;
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

  bool _sameKeys(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  @override
  void didUpdateWidget(covariant TutorialHomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scopeChanged = widget.userId != oldWidget.userId || widget.companyId != oldWidget.companyId;
    if (scopeChanged) { _completed = false; _workspace = null; }
    if (scopeChanged || widget.refreshToken != oldWidget.refreshToken ||
        !_sameKeys(widget.availableActionKeys, oldWidget.availableActionKeys)) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_opening) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_completed) {
      return;
    } // Terminal flag survives registry additions and refreshes.
    final request = ++_request;
    final userId = widget.userId;
    final companyId = widget.companyId;
    if (mounted) {
      setState(() { _loading = true; _error = null; });
    }
    try {
      final preferences = widget.preferences ?? TutorialPreferences();
      if (await preferences.initialCompleted(userId: userId, companyId: companyId)) {
        if (mounted && request == _request) {
          setState(() { _completed = true; _loading = false; });
        }
        return;
      }
      final loader = widget.loadSnapshot;
      final repository = widget.repository ?? TutorialEvidenceRepository.maybeCreate();
      if (loader == null && repository == null) {
        throw StateError('Tutorial evidence unavailable');
      }
      final keys = Set<String>.unmodifiable(widget.availableActionKeys);
      final snapshot = loader != null ? await loader(keys)
          : await repository!.load(availableActionKeys: keys);
      if (!mounted || request != _request) {
        return;
      }
      final workspace = TutorialWorkspace.fromSnapshot(snapshot);
      if (workspace.canCompleteInitial) {
        await preferences.markInitialCompleted(userId: userId, companyId: companyId);
      }
      if (!mounted || request != _request) {
        return;
      }
      setState(() {
        _workspace = workspace;
        _completed = workspace.canCompleteInitial;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) {
        return;
      }
      setState(() { _workspace = null; _loading = false; _error = '準備状況を確認できません。再読み込みしてください。'; });
    }
  }

  Future<void> _openGuide() async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => TutorialPage(
        userId: widget.userId, companyId: widget.companyId,
        availableActionKeys: widget.availableActionKeys, onOpenAction: widget.onOpenAction,
        repository: widget.repository, loadSnapshot: widget.loadSnapshot, preferences: widget.preferences,
      )));
    } finally {
      if (mounted) { setState(() => _opening = false); await _refresh(); }
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    if (_completed) {
      return const SizedBox.shrink();
    }
    final workspace = _workspace;
    return Card(margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.school_outlined), const SizedBox(width: 8),
            Expanded(child: Text(SkoLanguageController.tr('SKOの初期準備'),
              style: Theme.of(context).textTheme.titleMedium)),
            IconButton(onPressed: _loading || _opening ? null : _refresh,
              tooltip: SkoLanguageController.tr('再読み込み'), icon: const Icon(Icons.refresh)),
          ]),
          if (workspace != null)
            TutorialProgressSummary(counts: workspace.progress.required, title: '必須の準備')
          else Text(SkoLanguageController.tr('準備状況：未確定')),
          if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(SkoLanguageController.tr(_error!))),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _opening ? null : _openGuide,
            icon: const Icon(Icons.arrow_forward), label: Text(SkoLanguageController.tr('準備ガイドを開く'))),
        ])));
  }
}
