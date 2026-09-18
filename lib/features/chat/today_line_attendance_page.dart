import 'package:flutter/material.dart';

import '../attendance/attendance_verification_repository.dart';
import 'line_attendance_candidate_parser.dart';
import 'line_attendance_reference_matcher.dart';
import 'line_history_parser.dart';
import 'today_line_attendance_repository.dart';

class TodayLineAttendancePage extends StatefulWidget {
  const TodayLineAttendancePage({super.key});

  @override
  State<TodayLineAttendancePage> createState() => _TodayLineAttendancePageState();
}

class _TodayLineAttendancePageState extends State<TodayLineAttendancePage> {
  final _lineRepository = TodayLineAttendanceRepository.maybeCreate();
  final _referenceRepository = AttendanceVerificationRepository.maybeCreate();
  final _candidateParser = const LineAttendanceCandidateParser();
  final _matcher = const LineAttendanceReferenceMatcher();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _sites = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lineRepository = _lineRepository;
    final referenceRepository = _referenceRepository;
    if (lineRepository == null || referenceRepository == null) {
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
      final values = await Future.wait([
        lineRepository.loadTodayLineMessages(),
        referenceRepository.loadWorkers(),
        referenceRepository.loadSites(),
      ]);
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(values[0]);
        _workers = List<Map<String, dynamic>>.from(values[1]);
        _sites = List<Map<String, dynamic>>.from(values[2]);
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
    final today = DateTime.now();
    final historyMessages = _messages
        .map(_toHistoryMessage)
        .whereType<LineHistoryMessage>()
        .toList(growable: false);

    final candidates = _candidateParser
        .parseMessages(historyMessages)
        .where((candidate) => _sameDate(candidate.workDate, today))
        .toList(growable: false);

    final workerNames = _workers
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final siteNames = _sites
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);

    final evaluated = candidates
        .map(
          (candidate) => _EvaluatedCandidate(
            candidate: candidate,
            workerMatch: _matcher.match(
              input: candidate.workerName,
              candidates: workerNames,
            ),
            siteMatch: _matcher.match(
              input: candidate.siteName,
              candidates: siteNames,
            ),
          ),
        )
        .toList(growable: false);

    final matchedCount = evaluated.where((item) => item.isFullyMatched).length;
    final needsReviewCount = evaluated.length - matchedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本日のLINE出勤候補'),
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
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(today),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'LINE連携で本日受信したメッセージを読み取り、出勤候補だけを表示します。ここでは正式な勤怠データへの保存は行いません。',
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          label: 'LINE受信',
                          value: '${_messages.length}件',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryCard(
                          label: '出勤候補',
                          value: '${evaluated.length}件',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          label: '登録済みと一致',
                          value: '$matchedCount件',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryCard(
                          label: '要確認',
                          value: '$needsReviewCount件',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_messages.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          '本日、SKOに取り込まれたLINEメッセージはまだありません。LINE連携が有効か、グループからメッセージが届いているか確認してください。',
                        ),
                      ),
                    )
                  else if (evaluated.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          '本日のLINEメッセージは届いていますが、今日の日付・現場・作業員を明確に読み取れる出勤候補はまだありません。',
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      '候補一覧',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in evaluated)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                item.isFullyMatched
                                    ? Icons.check
                                    : Icons.priority_high,
                              ),
                            ),
                            title: Text(
                              '${item.candidate.siteName} / ${item.candidate.workerName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              item.statusText,
                            ),
                            trailing: Text(
                              _formatTime(item.candidate.sourceTimestamp),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '安全のため、未登録名・同名重複・表記ゆれを自動確定しません。正式な勤怠登録は、候補と登録済みデータの対応を確認できるようになってから追加します。',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  LineHistoryMessage? _toHistoryMessage(Map<String, dynamic> row) {
    final body = row['body']?.toString() ?? '';
    final createdAt = DateTime.tryParse(row['sent_at']?.toString() ?? '');
    if (body.trim().isEmpty || createdAt == null) return null;

    return LineHistoryMessage(
      timestamp: createdAt.toLocal(),
      sender: row['sender_display_name']?.toString().trim().isNotEmpty == true
          ? row['external_sender_name'].toString()
          : 'LINE',
      body: body,
    );
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)}';
  }

  String _formatTime(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }
}

class _EvaluatedCandidate {
  const _EvaluatedCandidate({
    required this.candidate,
    required this.workerMatch,
    required this.siteMatch,
  });

  final LineAttendanceCandidate candidate;
  final LineReferenceMatch workerMatch;
  final LineReferenceMatch siteMatch;

  bool get isFullyMatched => workerMatch.isMatched && siteMatch.isMatched;

  String get statusText {
    final parts = <String>[];

    if (siteMatch.isMatched) {
      parts.add('現場: 登録済み');
    } else if (siteMatch.isAmbiguous) {
      parts.add('現場: 同名候補あり');
    } else {
      parts.add('現場: 未登録/表記違い');
    }

    if (workerMatch.isMatched) {
      parts.add('作業員: 登録済み');
    } else if (workerMatch.isAmbiguous) {
      parts.add('作業員: 同名候補あり');
    } else {
      parts.add('作業員: 未登録/表記違い');
    }

    return parts.join(' / ');
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }
}
