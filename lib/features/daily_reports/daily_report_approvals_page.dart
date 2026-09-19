import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'daily_report_repository.dart';

class DailyReportApprovalsPage extends StatefulWidget {
  const DailyReportApprovalsPage({super.key});

  @override
  State<DailyReportApprovalsPage> createState() =>
      _DailyReportApprovalsPageState();
}

class _DailyReportApprovalsPageState extends State<DailyReportApprovalsPage> {
  final _repository = DailyReportRepository.maybeCreate();

  List<Map<String, dynamic>> _items = const [];
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
        _error = '承認機能を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await repository.loadPendingApprovals();
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

  Future<void> _decide(String id, bool approve) async {
    final repository = _repository;
    if (repository == null) return;

    try {
      final result = await repository.decideEdit(
        requestId: id,
        approve: approve,
      );
      if (!mounted) return;

      final message = switch (result) {
        'approved' => '2名の承認が揃い、編集可能になりました',
        'rejected' => '修正申請を却下しました',
        _ => '承認しました。もう1名の承認待ちです',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('処理できませんでした: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '承認待ち',
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.task_alt, size: 56),
                            SizedBox(height: 12),
                            Text(
                              '承認待ちはありません',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
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
                            final report = item['daily_reports'];
                            final reportMap = report is Map
                                ? Map<String, dynamic>.from(report)
                                : <String, dynamic>{};
                            final site = reportMap['sites'];
                            final siteName = site is Map
                                ? site['name']?.toString() ?? ''
                                : '';
                            final date =
                                reportMap['report_date']?.toString() ?? '';
                            final reason = item['reason']?.toString() ?? '';

                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const CircleAvatar(
                                          child: Icon(Icons.edit_note_outlined),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                siteName.isEmpty
                                                    ? '日報修正申請'
                                                    : siteName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              Text(date),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (reason.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Text('理由：$reason'),
                                    ],
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _decide(
                                              item['id'].toString(),
                                              false,
                                            ),
                                            icon: const Icon(Icons.close),
                                            label: const Text('却下'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: () => _decide(
                                              item['id'].toString(),
                                              true,
                                            ),
                                            icon: const Icon(Icons.check),
                                            label: const Text('承認'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}
