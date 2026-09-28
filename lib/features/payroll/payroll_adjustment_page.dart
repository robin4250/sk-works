import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'payroll_adjustment_repository.dart';

class PayrollAdjustmentPage extends StatefulWidget {
  const PayrollAdjustmentPage({super.key});

  @override
  State<PayrollAdjustmentPage> createState() => _PayrollAdjustmentPageState();
}

class _PayrollAdjustmentPageState extends State<PayrollAdjustmentPage> {
  final _repository = PayrollAdjustmentRepository.maybeCreate();

  PayrollAdjustmentAccess? _access;
  List<PayrollAdjustmentWorker> _workers = const [];
  List<PayrollAdjustmentTypeOption> _types = const [];
  List<PayrollAdjustmentListItem> _items = const [];
  String? _workerFilter;
  bool _loading = true;
  bool _busy = false;
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
        _error = '給与調整を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final access = await repository.loadAccess();
      if (!access.canView) {
        if (!mounted) return;
        setState(() {
          _access = access;
          _loading = false;
          _error = '給与調整を閲覧する権限がありません。';
        });
        return;
      }

      final values = await Future.wait([
        repository.loadWorkers(),
        repository.loadTypes(),
        repository.loadAdjustments(workerId: _workerFilter),
      ]);

      if (!mounted) return;
      setState(() {
        _access = access;
        _workers = values[0] as List<PayrollAdjustmentWorker>;
        _types = values[1] as List<PayrollAdjustmentTypeOption>;
        _items = values[2] as List<PayrollAdjustmentListItem>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _reloadItems() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final values = await Future.wait([
        repository.loadTypes(),
        repository.loadAdjustments(workerId: _workerFilter),
      ]);
      if (!mounted) return;
      setState(() {
        _types = values[0] as List<PayrollAdjustmentTypeOption>;
        _items = values[1] as List<PayrollAdjustmentListItem>;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('再読み込みできませんでした: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final pageLabel = access?.pageLabel ?? '給与調整';
    final activeItems = _items.where((item) => !item.isCancelled);
    final additions = activeItems
        .where((item) => item.isAddition)
        .fold<int>(0, (sum, item) => sum + item.amountYen);
    final deductions = activeItems
        .where((item) => !item.isAddition)
        .fold<int>(0, (sum, item) => sum + item.amountYen);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pageLabel,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (access?.canRename == true)
            IconButton(
              tooltip: 'ページ名を変更',
              onPressed: _busy ? null : _renamePage,
              icon: const Icon(Icons.edit_outlined),
            ),
          const SkoNotificationBell(),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: access?.canManage == true && !_loading
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _addAdjustment,
              icon: const Icon(Icons.add),
              label: const Text('登録'),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DropdownButtonFormField<String?>(
                                  initialValue: _workerFilter,
                                  decoration: const InputDecoration(
                                    labelText: '従業員',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('全員'),
                                    ),
                                    for (final worker in _workers)
                                      DropdownMenuItem<String?>(
                                        value: worker.id,
                                        child: Text(worker.name),
                                      ),
                                  ],
                                  onChanged: (value) async {
                                    setState(() => _workerFilter = value);
                                    await _reloadItems();
                                  },
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _SummaryChip(
                                      label: '加算',
                                      value: _yen(additions),
                                    ),
                                    _SummaryChip(
                                      label: '控除',
                                      value: _yen(deductions),
                                    ),
                                    _SummaryChip(
                                      label: '差引',
                                      value: _signedYen(additions - deductions),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_items.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Column(
                                children: [
                                  Icon(Icons.payments_outlined, size: 48),
                                  SizedBox(height: 10),
                                  Text(
                                    '給与調整の登録はまだありません',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          for (final item in _items) ...[
                            _AdjustmentCard(
                              item: item,
                              canManage: access?.canManage == true,
                              onCancel: () => _cancelAdjustment(item),
                            ),
                            const SizedBox(height: 8),
                          ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Future<void> _renamePage() async {
    final repository = _repository;
    final access = _access;
    if (repository == null || access == null || !access.canRename) return;

    final controller = TextEditingController(text: access.pageLabel);
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ページ名を変更'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '表示名',
            hintText: '例：前借り',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim(),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (label == null || label.isEmpty) return;
    setState(() => _busy = true);
    try {
      await repository.setPageLabel(label);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ページ名を変更できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAdjustment() async {
    final repository = _repository;
    final access = _access;
    if (repository == null || access?.canManage != true) return;

    if (_workers.isEmpty) {
      _show('登録可能な従業員がいません。');
      return;
    }

    if (_types.where((item) => item.isActive).isEmpty) {
      final created = await _addType();
      if (!created) return;
    }

    String workerId = _workerFilter ?? _workers.first.id;
    String? typeId = _types.where((item) => item.isActive).isNotEmpty
        ? _types.where((item) => item.isActive).first.id
        : null;
    DateTime effectiveDate = DateTime.now();
    final amount = TextEditingController();
    final note = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final activeTypes = _types.where((item) => item.isActive).toList();
          if (typeId != null &&
              !activeTypes.any((item) => item.id == typeId)) {
            typeId = activeTypes.isEmpty ? null : activeTypes.first.id;
          }

          return AlertDialog(
            title: Text('${access?.pageLabel ?? '給与調整'}を登録'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: workerId,
                      decoration: const InputDecoration(
                        labelText: '従業員',
                      ),
                      items: [
                        for (final worker in _workers)
                          DropdownMenuItem(
                            value: worker.id,
                            child: Text(worker.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => workerId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: typeId,
                            decoration: const InputDecoration(
                              labelText: '項目',
                            ),
                            items: [
                              for (final type in activeTypes)
                                DropdownMenuItem(
                                  value: type.id,
                                  child: Text(
                                    '${type.label}（${type.isAddition ? '加算' : '控除'}）',
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setDialogState(() => typeId = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final created = await _addType();
                            if (!created || !mounted) return;
                            final types = await repository.loadTypes();
                            if (!mounted) return;
                            setState(() => _types = types);
                            setDialogState(() {
                              final active =
                                  types.where((item) => item.isActive).toList();
                              if (active.isNotEmpty) {
                                typeId = active.last.id;
                              }
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('項目追加'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '金額',
                        suffixText: '円',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('対象日'),
                      subtitle: Text(_date(effectiveDate)),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: effectiveDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => effectiveDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '備考（任意）',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () async {
                  final parsed = int.tryParse(
                    amount.text.replaceAll(',', '').trim(),
                  );
                  if (typeId == null || parsed == null || parsed <= 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('項目と金額を確認してください')),
                    );
                    return;
                  }

                  try {
                    await repository.createAdjustment(
                      workerId: workerId,
                      typeId: typeId!,
                      amountYen: parsed,
                      effectiveDate: effectiveDate,
                      note: note.text,
                    );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('登録できませんでした: $error')),
                    );
                  }
                },
                child: const Text('登録'),
              ),
            ],
          );
        },
      ),
    );

    amount.dispose();
    note.dispose();

    if (saved == true) {
      await _reloadItems();
      if (!mounted) return;
      _show('給与調整を登録しました');
    }
  }

  Future<bool> _addType() async {
    final repository = _repository;
    if (repository == null || _access?.canManage != true) return false;

    final label = TextEditingController();
    var direction = 'deduction';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('給与調整の項目を追加'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  autofocus: true,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: '項目名',
                    hintText: '例：前借り、道具代、交通費',
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'deduction',
                      label: Text('控除'),
                      icon: Icon(Icons.remove_circle_outline),
                    ),
                    ButtonSegment(
                      value: 'addition',
                      label: Text('加算'),
                      icon: Icon(Icons.add_circle_outline),
                    ),
                  ],
                  selected: {direction},
                  onSelectionChanged: (value) =>
                      setDialogState(() => direction = value.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () async {
                if (label.text.trim().isEmpty) return;
                try {
                  await repository.saveType(
                    label: label.text,
                    direction: direction,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('項目を追加できませんでした: $error')),
                  );
                }
              },
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );

    label.dispose();
    if (saved == true) {
      final types = await repository.loadTypes();
      if (mounted) setState(() => _types = types);
      return true;
    }
    return false;
  }

  Future<void> _cancelAdjustment(PayrollAdjustmentListItem item) async {
    final repository = _repository;
    if (repository == null || _access?.canManage != true || item.isCancelled) {
      return;
    }

    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('この登録を取消しますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${item.workerName} / ${item.label} / ${_yen(item.amountYen)}'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '取消理由（任意）',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('取消する'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      reason.dispose();
      return;
    }

    setState(() => _busy = true);
    try {
      await repository.cancelAdjustment(
        id: item.id,
        reason: reason.text,
      );
      await _reloadItems();
    } catch (error) {
      if (!mounted) return;
      _show('取消できませんでした: $error');
    } finally {
      reason.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  static String _yen(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, digits.length);
      groups.insert(0, digits.substring(start, end));
    }
    return '¥${groups.join(',')}';
  }

  static String _signedYen(int value) =>
      '${value > 0 ? '+' : value < 0 ? '-' : ''}${_yen(value.abs())}';
}

class _AdjustmentCard extends StatelessWidget {
  const _AdjustmentCard({
    required this.item,
    required this.canManage,
    required this.onCancel,
  });

  final PayrollAdjustmentListItem item;
  final bool canManage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: item.isCancelled ? 0.55 : 1,
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Icon(
              item.isAddition
                  ? Icons.add_circle_outline
                  : Icons.remove_circle_outline,
            ),
          ),
          title: Text(
            '${item.workerName}  ${item.label}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            [
              _PayrollAdjustmentPageState._date(item.effectiveDate),
              if (item.note?.trim().isNotEmpty == true) item.note!.trim(),
              if (item.isCancelled) '取消済み',
              if (item.cancellationReason?.trim().isNotEmpty == true)
                '理由: ${item.cancellationReason!.trim()}',
            ].join(' / '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${item.isAddition ? '+' : '-'}${_PayrollAdjustmentPageState._yen(item.amountYen)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: item.isCancelled
                      ? scheme.onSurfaceVariant
                      : item.isAddition
                          ? scheme.primary
                          : scheme.error,
                ),
              ),
              if (canManage && !item.isCancelled)
                PopupMenuButton<String>(
                  tooltip: '操作',
                  onSelected: (value) {
                    if (value == 'cancel') onCancel();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'cancel',
                      child: Text('取消'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        '$label  $value',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
