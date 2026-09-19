import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'payroll_statement_repository.dart';

class PayrollStatementsPage extends StatefulWidget {
  const PayrollStatementsPage({super.key});

  @override
  State<PayrollStatementsPage> createState() => _PayrollStatementsPageState();
}

class _PayrollStatementsPageState extends State<PayrollStatementsPage> {
  final _repository = PayrollStatementRepository.maybeCreate();

  List<PayrollStatementRecord> _items = const [];
  bool _loading = true;
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
        _error = '給与明細を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await repository.loadMyStatements();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '給与明細',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.payments_outlined, size: 56),
                              SizedBox(height: 12),
                              Text(
                                '給与明細はまだ発行されていません',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PayrollStatementPreviewPage(
                                      statement: item,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.monthLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      if (item.companyName.isNotEmpty)
                                        Text(
                                          item.companyName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      if (item.workerName.isNotEmpty)
                                        Text(item.workerName),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '差引支給額',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                          ),
                                          Text(
                                            _yen(item.netPay),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(Icons.chevron_right),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  static String _yen(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, digits.length);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}¥${groups.join(',')}';
  }
}

class PayrollStatementPreviewPage extends StatelessWidget {
  const PayrollStatementPreviewPage({
    super.key,
    required this.statement,
  });

  final PayrollStatementRecord statement;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(statement.monthLabel),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 1 / 1.414,
              child: Card(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '給 与 明 細',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          statement.companyName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(statement.workerName),
                        const SizedBox(height: 8),
                        Text(
                          '対象期間：${_date(statement.periodStart)} ～ ${_date(statement.periodEnd)}',
                        ),
                        const Divider(height: 24),
                        _MoneyRow(
                          label: '総支給額',
                          value: statement.grossPay,
                        ),
                        _MoneyRow(
                          label: '控除額',
                          value: statement.deductions,
                        ),
                        const Divider(height: 20),
                        _MoneyRow(
                          label: '差引支給額',
                          value: statement.netPay,
                          strong: true,
                        ),
                        const SizedBox(height: 18),
                        if (statement.detail.isNotEmpty) ...[
                          const Text(
                            '内訳',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          for (final entry in statement.detail.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(child: Text(entry.key)),
                                  Text(entry.value.toString()),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('実機ではiOS印刷ダイアログへ接続します'),
                  ),
                );
              },
              icon: const Icon(Icons.print),
              label: const Text('印刷'),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final int value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            )
        : Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style,
            ),
          ),
          Text(
            PayrollStatementsPage._yen(value),
            style: style,
          ),
        ],
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
