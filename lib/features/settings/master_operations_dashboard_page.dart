import 'package:flutter/material.dart';

import 'master_operations_dashboard_repository.dart';

class MasterOperationsDashboardPage extends StatefulWidget {
  const MasterOperationsDashboardPage({super.key});

  @override
  State<MasterOperationsDashboardPage> createState() =>
      _MasterOperationsDashboardPageState();
}

class _MasterOperationsDashboardPageState
    extends State<MasterOperationsDashboardPage> {
  final _repository = MasterOperationsDashboardRepository.maybeCreate();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _growth = const {};
  Map<String, dynamic> _operations = const {};

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
        _error = 'Masterダッシュボードを利用できません。';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repository.load();
      if (!mounted) return;
      setState(() {
        _growth = Map<String, dynamic>.from(data['growth'] as Map? ?? {});
        _operations =
            Map<String, dynamic>.from(data['operations'] as Map? ?? {});
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

  int _count(Map<String, dynamic> source, String key) {
    final value = source[key];
    return value is num ? value.toInt() : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Master ダッシュボード',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'SKO全体の集計値だけを表示します。車両番号・現場名・チャット本文・写真・書類内容などの個別データは表示しません。',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '全体',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _MetricGrid(
                          items: [
                            _Metric('会社', _count(_growth, 'companies')),
                            _Metric('利用者', _count(_growth, 'users')),
                            _Metric('会社接続', _count(_growth, 'connections')),
                            _Metric('現場', _count(_operations, 'sites_total')),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '車両・ルート',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _MetricGrid(
                          items: [
                            _Metric('車両 合計', _count(_operations, 'vehicles_total')),
                            _Metric('車両 利用中', _count(_operations, 'vehicles_active')),
                            _Metric('車両 休止', _count(_operations, 'vehicles_disabled')),
                            _Metric('ルート 合計', _count(_operations, 'routes_total')),
                            _Metric('ルート 利用中', _count(_operations, 'routes_active')),
                            _Metric('ルート 休止', _count(_operations, 'routes_disabled')),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '現場チャット',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _MetricGrid(
                          items: [
                            _Metric(
                              '現場チャット',
                              _count(_operations, 'site_chats_total'),
                            ),
                            _Metric(
                              'アーカイブ',
                              _count(_operations, 'site_chats_archived'),
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

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<_Metric> items;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.9,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final item in items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.value.toString(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(item.label, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final int value;
}
