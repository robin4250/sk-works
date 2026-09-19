import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'admin_site_financial_repository.dart';

class AdminSiteFinancialPage extends StatefulWidget {
  const AdminSiteFinancialPage({super.key});

  @override
  State<AdminSiteFinancialPage> createState() =>
      _AdminSiteFinancialPageState();
}

class _AdminSiteFinancialPageState extends State<AdminSiteFinancialPage> {
  final _repository = AdminSiteFinancialRepository.maybeCreate();

  List<AdminSiteFinancialRecord> _items = const [];
  bool _loading = true;
  String? _error;
  bool _showCompleted = false;

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
        _error = '管理者用現場データを利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await repository.loadAll();
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
    final visible = _items.where((item) {
      final completed = item.status == 'completed';
      return _showCompleted ? completed : !completed;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '管理者用現場データ',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('登録中'),
                    icon: Icon(Icons.work_outline),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('完了'),
                    icon: Icon(Icons.task_alt),
                  ),
                ],
                selected: {_showCompleted},
                onSelectionChanged: (value) =>
                    setState(() => _showCompleted = value.first),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : visible.isEmpty
                          ? const Center(child: Text('該当する現場はありません'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 6, 12, 24),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = visible[index];
                                  return Card(
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        child: Icon(
                                          Icons.admin_panel_settings_outlined,
                                        ),
                                      ),
                                      title: Text(
                                        item.siteName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '給与単価 ${_yen(item.workerDailyRateYen)} / 請求単価 ${_yen(item.billingUnitPriceYen)}',
                                      ),
                                      trailing:
                                          const Icon(Icons.chevron_right),
                                      onTap: () => _edit(item),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(AdminSiteFinancialRecord record) async {
    final daily = TextEditingController(
      text: record.workerDailyRateYen.toString(),
    );
    final overtime = TextEditingController(
      text: record.overtimeHourRateYen.toString(),
    );
    final early = TextEditingController(
      text: record.earlyHourRateYen.toString(),
    );
    final night = TextEditingController(
      text: record.nightHourRateYen.toString(),
    );
    final billing = TextEditingController(
      text: record.billingUnitPriceYen.toString(),
    );
    final welfare = TextEditingController(
      text: record.welfareRate.toString(),
    );

    final saved = await showDialog<AdminSiteFinancialRecord>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(record.siteName),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '給与計算用',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                _MoneyField(controller: daily, label: '1人工（日額）'),
                const SizedBox(height: 10),
                _MoneyField(controller: overtime, label: '残業 1時間'),
                const SizedBox(height: 10),
                _MoneyField(controller: early, label: '早出 1時間'),
                const SizedBox(height: 10),
                _MoneyField(controller: night, label: '夜間 1時間'),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '請求書用',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                _MoneyField(controller: billing, label: '請求 1人工単価'),
                const SizedBox(height: 10),
                TextField(
                  controller: welfare,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '法定福利費率（%）',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                AdminSiteFinancialRecord(
                  siteId: record.siteId,
                  siteName: record.siteName,
                  status: record.status,
                  workerDailyRateYen: int.tryParse(daily.text) ?? 0,
                  overtimeHourRateYen: int.tryParse(overtime.text) ?? 0,
                  earlyHourRateYen: int.tryParse(early.text) ?? 0,
                  nightHourRateYen: int.tryParse(night.text) ?? 0,
                  billingUnitPriceYen: int.tryParse(billing.text) ?? 0,
                  welfareRate: double.tryParse(welfare.text) ?? 0,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    for (final controller in [
      daily,
      overtime,
      early,
      night,
      billing,
      welfare,
    ]) {
      controller.dispose();
    }

    if (saved == null) return;

    try {
      await _repository?.save(saved);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者用現場データを保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    }
  }

  static String _yen(int value) => '¥$value';
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
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
