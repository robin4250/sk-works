import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'payroll_review_repository.dart';
import 'payroll_statements_page.dart';

class PayrollReviewPage extends StatefulWidget {
  const PayrollReviewPage({super.key});

  @override
  State<PayrollReviewPage> createState() => _PayrollReviewPageState();
}

class _PayrollReviewPageState extends State<PayrollReviewPage> {
  final _repository = PayrollReviewRepository.maybeCreate();
  PayrollReviewWorkspace? _workspace;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final Set<String> _checked = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '給料一覧を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final workspace = await repository.loadWorkspace();
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _loading = false;
        _checked.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<PayrollReviewItem> get _monthItems {
    final items = _workspace?.items ?? const <PayrollReviewItem>[];
    return [
      for (final item in items)
        if (item.statement.periodStart.year == _month.year &&
            item.statement.periodStart.month == _month.month)
          item,
    ];
  }

  Future<void> _confirm() async {
    final repository = _repository;
    final workspace = _workspace;
    final items = _monthItems;
    if (repository == null || workspace == null || !workspace.canConfirm) return;
    if (items.isEmpty) return;
    if (_checked.length != items.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全従業員の給与明細を確認してから確定してください')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await repository.confirmMonth(
        month: _month,
        statementIds: [for (final item in items) item.statement.id],
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全員分を確認済みにしました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('確定できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setVisibility(
    PayrollReviewWorkerVisibility worker,
    bool value,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    await repository.setManagerVisibility(
      workerId: worker.workerId,
      visible: value,
    );
    await _load();
  }

  void _moveMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _checked.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '給料一覧',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : workspace == null
                    ? const SizedBox.shrink()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => _moveMonth(-1),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Expanded(
                                  child: Text(
                                    '${_month.year}年${_month.month}月',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _moveMonth(1),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                            if (workspace.canManageVisibility) ...[
                              const SizedBox(height: 8),
                              Card(
                                child: ExpansionTile(
                                  title: const Text(
                                    'サブ管理者へ見せる従業員',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                  children: [
                                    for (final worker in workspace.workers)
                                      CheckboxListTile(
                                        value: worker.visibleToManager,
                                        title: Text(worker.workerName),
                                        onChanged: (value) => _setVisibility(
                                          worker,
                                          value ?? false,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (_monthItems.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  'この月の給与明細はまだありません',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else
                              for (final item in _monthItems)
                                Card(
                                  child: ListTile(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            PayrollStatementPreviewPage(
                                          statement: item.statement,
                                        ),
                                      ),
                                    ),
                                    leading: workspace.canConfirm
                                        ? Checkbox(
                                            value: _checked.contains(
                                              item.statement.id,
                                            ),
                                            onChanged: (value) {
                                              setState(() {
                                                if (value == true) {
                                                  _checked.add(item.statement.id);
                                                } else {
                                                  _checked
                                                      .remove(item.statement.id);
                                                }
                                              });
                                            },
                                          )
                                        : null,
                                    title: Text(
                                      item.statement.workerName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    subtitle: Text(
                                      item.confirmed ? '確認済み' : '未確定',
                                      style: TextStyle(
                                        color: item.confirmed
                                            ? Colors.green
                                            : Theme.of(context)
                                                .colorScheme
                                                .error,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    trailing: Text(
                                      _yen(item.statement.netPay),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                            if (workspace.canConfirm && _monthItems.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _saving ? null : _confirm,
                                icon: const Icon(Icons.verified_outlined),
                                label: Text(_saving ? '確定中…' : '全員確認後に確定'),
                              ),
                            ],
                          ],
                        ),
                      ),
      ),
    );
  }

  String _yen(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, digits.length);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}¥${groups.join(',')}';
  }
}
