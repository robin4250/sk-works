import 'package:flutter/material.dart';

import '../../international/language_controller.dart';

import 'group_checkout_repository.dart';

/// Called only after personal checkout succeeds. Failures never repeat that INSERT.
Future<void> showGroupCheckoutAfterPersonalSave(BuildContext context, {
  required String anchorId, required DateTime workDate,
}) async {
  final repository = GroupCheckoutRepository.maybeCreate();
  if (repository == null) {
    return;
  }
  List<GroupCheckoutCandidate>? candidates;
  Object? failure;
  try {
    candidates = await repository.loadIfEnabled(anchorId, workDate);
    if (candidates == null || !candidates.any((candidate) => candidate.isOpen)) {
      return;
    }
  } catch (error) {
    failure = error;
  }
  if (!context.mounted) {
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupCheckoutPage(
    repository: repository, anchorId: anchorId, workDate: workDate,
    initialCandidates: candidates, initialError: failure,
  )));
}

class GroupCheckoutPage extends StatefulWidget {
  const GroupCheckoutPage({super.key, required this.repository, required this.anchorId,
    required this.workDate, this.initialCandidates, this.initialError});
  final GroupCheckoutRepository repository;
  final String anchorId;
  final DateTime workDate;
  final List<GroupCheckoutCandidate>? initialCandidates;
  final Object? initialError;
  @override
  State<GroupCheckoutPage> createState() => _GroupCheckoutPageState();
}

class _GroupCheckoutPageState extends State<GroupCheckoutPage> {
  List<GroupCheckoutCandidate> _candidates = const [];
  final Set<String> _selected = {};
  GroupCheckoutRequest? _request;
  String? _error;
  bool _busy = false;
  bool _uncertain = false;

  @override
  void initState() {
    super.initState();
    _candidates = widget.initialCandidates ?? const [];
    _selected.addAll(_candidates.where((row) => row.isOpen).map((row) => row.sourceId));
    _error = widget.initialError?.toString();
  }

  Future<void> _reload() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final rows = await widget.repository.loadIfEnabled(widget.anchorId, widget.workDate);
      if (!mounted) {
        return;
      }
      if (rows == null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _candidates = rows;
        if (!_uncertain) {
          _selected.clear();
          _selected.addAll(rows.where((row) => row.isOpen).map((row) => row.sourceId));
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _commit() async {
    if (_busy || _selected.isEmpty) {
      return;
    }
    if (_request == null || !_request!.matches(_selected)) {
      _request = GroupCheckoutRequest(anchorId: widget.anchorId, sourceIds: _selected);
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.repository.commit(_request!);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('選択したメンバーの退勤を登録しました'))));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() { _error = error.toString(); _uncertain = true; });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _continueToReport() async {
    if (_busy) {
      return;
    }
    final proceed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(SkoLanguageController.tr('日報へ進みますか？')),
      content: Text(SkoLanguageController.tr(_uncertain
        ? 'あなたの退勤は登録済みです。他メンバーの退勤結果が未確認です。重複を避けるため、同じ内容で再確認することをおすすめします。'
        : 'あなたの退勤は登録済みです。未選択・未処理のメンバーの退勤は登録されません。')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(SkoLanguageController.tr('戻る'))),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(SkoLanguageController.tr('日報へ進む')))],
    ));
    if (proceed == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = '${widget.workDate.year}/${widget.workDate.month}/${widget.workDate.day}';
    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        _continueToReport();
      }
    }, child: Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('現場メンバーの退勤')),
        leading: IconButton(onPressed: _busy ? null : _continueToReport, icon: const Icon(Icons.arrow_back))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(SkoLanguageController.trParams('勤務日 {date}', {'date': date}), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(SkoLanguageController.tr('あなたの退勤は登録済みです。同じ現場・勤務日のメンバーを集計しました。早退・退勤済みの時刻は変更しません。')),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(SkoLanguageController.trParams('他メンバーの退勤を確認できません: {error}', {'error': _error ?? ''}), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_uncertain) Text(SkoLanguageController.tr('送信結果が未確認のため、対象を変えず同じ内容で再確認してください。')),
        for (final row in _candidates) CheckboxListTile(
          title: Text(row.name), subtitle: Text(SkoLanguageController.tr(row.isOpen ? '出勤中' : '退勤済み・時刻を保持')),
          value: row.isOpen && _selected.contains(row.sourceId),
          onChanged: _busy || _uncertain || !row.isOpen ? null : (selected) {
            setState(() { if (selected == true) { _selected.add(row.sourceId); } else { _selected.remove(row.sourceId); } });
          },
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy || _selected.isEmpty ? null : _commit,
          child: Text(SkoLanguageController.tr(_busy ? '登録中…' : _uncertain ? '同じ内容で再確認' : '選択したメンバーを代理退勤'))),
        TextButton(onPressed: _busy ? null : _reload, child: Text(SkoLanguageController.tr('状態を再確認'))),
        TextButton(onPressed: _busy ? null : _continueToReport, child: Text(SkoLanguageController.tr('日報へ進む'))),
      ]),
    ));
  }
}
