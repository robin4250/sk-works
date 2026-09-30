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
  Map<String, dynamic> _storage = const {};
  Map<String, dynamic> _usage = const {};
  int _usageDays = 30;

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
      final data = await repository.load(usageDays: _usageDays);
      if (!mounted) return;
      setState(() {
        _growth = Map<String, dynamic>.from(data['growth'] as Map? ?? {});
        _operations =
            Map<String, dynamic>.from(data['operations'] as Map? ?? {});
        _storage = Map<String, dynamic>.from(data['storage'] as Map? ?? {});
        _usage = Map<String, dynamic>.from(data['usage'] as Map? ?? {});
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

  num _number(Map<String, dynamic> source, String key) {
    final value = source[key];
    return value is num ? value : 0;
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
                            _Metric('現場', _count(_operations, 'sites_total')),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '会社間連携',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _MetricGrid(
                          items: [
                            _Metric('接続レコード', _count(_growth, 'connections')),
                            _Metric(
                              '連携済み会社',
                              _count(_growth, 'connected_companies'),
                            ),
                            _Metric(
                              '未連携会社',
                              _count(_growth, 'unconnected_companies'),
                            ),
                            _Metric(
                              '連携率 %',
                              _number(_growth, 'connection_rate_percent'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '新規登録',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _MetricGrid(
                          items: [
                            _Metric('会社 7日', _count(_growth, 'companies_last_7_days')),
                            _Metric('会社 30日', _count(_growth, 'companies_last_30_days')),
                            _Metric('会社 今月', _count(_growth, 'companies_current_month')),
                            _Metric('利用者 7日', _count(_growth, 'users_last_7_days')),
                            _Metric('利用者 30日', _count(_growth, 'users_last_30_days')),
                            _Metric('利用者 今月', _count(_growth, 'users_current_month')),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '1社あたり利用者',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _MetricGrid(
                          items: [
                            _Metric('平均', _number(_growth, 'members_per_company_average')),
                            _Metric('中央値', _number(_growth, 'members_per_company_median')),
                            _Metric('最小', _number(_growth, 'members_per_company_min')),
                            _Metric('最大', _number(_growth, 'members_per_company_max')),
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
                          'ストレージ',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _MetricGrid(
                          items: [
                            _Metric('ファイル', _count(_storage, 'objects_total')),
                            _Metric(
                              '使用量 MB',
                              _number(_storage, 'bytes_total') / (1024 * 1024),
                            ),
                            _Metric('画像', _count(_storage, 'images_total')),
                            _Metric('PDF', _count(_storage, 'pdfs_total')),
                            _Metric(
                              '使用中バケット',
                              _count(_storage, 'buckets_with_objects'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '利用状況',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ),
                            DropdownButton<int>(
                              value: _usageDays,
                              items: const [
                                DropdownMenuItem(value: 7, child: Text('7日')),
                                DropdownMenuItem(value: 30, child: Text('30日')),
                                DropdownMenuItem(value: 90, child: Text('90日')),
                              ],
                              onChanged: _loading
                                  ? null
                                  : (value) {
                                      if (value == null || value == _usageDays) return;
                                      setState(() => _usageDays = value);
                                      _load();
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _MetricGrid(
                          items: [
                            _Metric('イベント', _count(_usage, 'events_total')),
                            _Metric('利用会社', _count(_usage, 'companies_active')),
                            _Metric('利用者', _count(_usage, 'users_active')),
                            _Metric('集計日数', _count(_usage, 'window_days')),
                            _Metric(
                              '1社あたり利用回数',
                              _number(_usage, 'events_per_company'),
                            ),
                            _Metric(
                              '1人あたり利用回数',
                              _number(_usage, 'events_per_user'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _UsageTrendSummary(usage: _usage),
                        const SizedBox(height: 10),
                        _RankingCard(
                          title: 'よく使われる操作',
                          rows: _rankingRows(
                            _usage['top_events'],
                            keyName: 'event_key',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _RankingCard(
                          title: 'よく開かれる画面',
                          rows: _rankingRows(
                            _usage['top_surfaces'],
                            keyName: 'surface_key',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _RankingCard(
                          title: 'よく使われる機能',
                          rows: _rankingRows(
                            _usage['top_features'],
                            keyName: 'feature_key',
                          ),
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

List<_RankingRow> _rankingRows(
  dynamic raw, {
  required String keyName,
}) {
  if (raw is! List) return const <_RankingRow>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .map(
        (item) => _RankingRow(
          key: item[keyName]?.toString() ?? '',
          count: item['event_count'] is num
              ? (item['event_count'] as num).toInt()
              : 0,
          companyCount: item['company_count'] is num
              ? (item['company_count'] as num).toInt()
              : 0,
          userCount: item['user_count'] is num
              ? (item['user_count'] as num).toInt()
              : 0,
          eventsPerCompany: item['events_per_company'] is num
              ? item['events_per_company'] as num
              : 0,
          eventsPerUser: item['events_per_user'] is num
              ? item['events_per_user'] as num
              : 0,
        ),
      )
      .where((item) => item.key.isNotEmpty)
      .toList(growable: false);
}

String _friendlyUsageKey(String value) {
  return switch (value) {
    'page_open' => '画面を開いた',
    'button_tap' => 'ボタン操作',
    'feature_use' => '機能利用',
    'action_complete' => '操作完了',
    'home' => 'ホーム',
    'attendance' => '出勤・退勤',
    'attendance_sheet' => '出勤表',
    'daily_report' => '日報',
    'payroll' => '給与明細',
    'invoice' => '請求書',
    'chat' => 'チャット',
    'people' => '人員管理',
    'qualifications' => '資格',
    'documents' => '書類',
    'sites' => '現場',
    'vehicle_routes' => '車両・ルート',
    'settings' => '設定',
    'profile' => 'プロフィール',
    'help' => 'ヘルプ',
    'clock_in' => '出勤',
    'clock_out' => '退勤',
    'print' => '印刷',
    'company_connection' => '会社間連携',
    'site_chat' => '現場チャット',
    'vehicle_management' => '車両管理',
    'route_assignment' => 'ルート・配車',
    _ => value,
  };
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<_RankingRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('まだ集計データがありません')
            else
              for (var index = 0; index < rows.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${index + 1}.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(child: Text(_friendlyUsageKey(rows[index].key))),
                      Text(
                        '${rows[index].count}回 / '
                        '${rows[index].companyCount}社 / '
                        '${rows[index].userCount}人',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RankingRow {
  const _RankingRow({
    required this.key,
    required this.count,
    required this.companyCount,
    required this.userCount,
    required this.eventsPerCompany,
    required this.eventsPerUser,
  });

  final String key;
  final int count;
  final int companyCount;
  final int userCount;
  final num eventsPerCompany;
  final num eventsPerUser;
}

class _UsageTrendSummary extends StatelessWidget {
  const _UsageTrendSummary({required this.usage});

  final Map<String, dynamic> usage;

  @override
  Widget build(BuildContext context) {
    String trend(String key) {
      final value = usage[key];
      if (value is! num) return '比較データなし';
      final prefix = value > 0 ? '+' : '';
      return '$prefix${_formatMetricValue(value)}%';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            Text('イベント 前期間比 ${trend('events_change_percent')}'),
            Text('利用会社 前期間比 ${trend('companies_change_percent')}'),
            Text('利用者 前期間比 ${trend('users_change_percent')}'),
          ],
        ),
      ),
    );
  }
}

String _formatMetricValue(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
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
                    _formatMetricValue(item.value),
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
  final num value;
}
