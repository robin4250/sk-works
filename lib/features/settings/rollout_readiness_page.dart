import 'package:flutter/material.dart';

import 'rollout_readiness_repository.dart';

class RolloutReadinessPage extends StatefulWidget {
  const RolloutReadinessPage({super.key});

  @override
  State<RolloutReadinessPage> createState() => _RolloutReadinessPageState();
}

class _RolloutReadinessPageState extends State<RolloutReadinessPage> {
  final _repository = RolloutReadinessRepository.maybeCreate();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Supabase接続またはログイン状態を確認してください。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status = await repository.loadStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
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
    final status = _status;
    final workers = _count('active_workers');
    final sites = _count('sites');
    final groups = _count('communication_groups');
    final bindings = _count('active_line_bindings');
    final lineMessages = _count('line_messages');
    final attendance = _count('attendance_entries');

    final checks = <_ReadinessCheck>[
      _ReadinessCheck(
        title: '作業員マスター',
        detail: workers > 0 ? '$workers人登録済み' : '作業員の登録が必要です',
        ready: workers > 0,
      ),
      _ReadinessCheck(
        title: '現場マスター',
        detail: sites > 0 ? '$sites現場登録済み' : '現場の登録が必要です',
        ready: sites > 0,
      ),
      _ReadinessCheck(
        title: '通信グループ',
        detail: groups > 0 ? '$groupsグループ登録済み' : '通信グループの準備が必要です',
        ready: groups > 0,
      ),
      _ReadinessCheck(
        title: 'LINEグループ連携',
        detail: bindings > 0 ? '$bindings件の連携が有効' : '有効なLINE連携はまだありません',
        ready: bindings > 0,
      ),
      _ReadinessCheck(
        title: 'LINE受信実績',
        detail: lineMessages > 0 ? '$lineMessages件受信済み' : '会社に紐付いたLINE受信はまだありません',
        ready: lineMessages > 0,
      ),
      _ReadinessCheck(
        title: '勤怠実績',
        detail: attendance > 0 ? '$attendance件登録済み' : '正式な勤怠実績はまだありません',
        ready: attendance > 0,
        informational: true,
      ),
    ];

    final required = checks.where((item) => !item.informational).toList();
    final readyCount = required.where((item) => item.ready).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('10月運用 準備チェック'),
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
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '運用準備 $readyCount / ${required.length}',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '本番Supabaseの現在状態を読み取り専用で確認します。ここからデータの追加・変更・削除は行いません。',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (status != null) ...[
                    const SizedBox(height: 14),
                    for (final check in checks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                check.informational
                                    ? Icons.info_outline
                                    : check.ready
                                        ? Icons.check
                                        : Icons.priority_high,
                              ),
                            ),
                            title: Text(
                              check.title,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(check.detail),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'LINE出勤の自動登録は、作業員・現場・LINEグループの対応が確認できるまでは有効にしません。まず候補を安全に読み取れる状態を完成させます。',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  int _count(String key) {
    final value = _status?[key];
    return value is num ? value.toInt() : 0;
  }
}

class _ReadinessCheck {
  const _ReadinessCheck({
    required this.title,
    required this.detail,
    required this.ready,
    this.informational = false,
  });

  final String title;
  final String detail;
  final bool ready;
  final bool informational;
}
