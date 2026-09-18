import 'package:flutter/material.dart';

import 'line_attendance_candidate_parser.dart';
import 'line_history_parser.dart';
import 'line_history_summary.dart';

class LineHistoryPreviewPage extends StatefulWidget {
  const LineHistoryPreviewPage({super.key});

  @override
  State<LineHistoryPreviewPage> createState() => _LineHistoryPreviewPageState();
}

class _LineHistoryPreviewPageState extends State<LineHistoryPreviewPage> {
  final _controller = TextEditingController();
  final _parser = const LineHistoryParser();
  final _attendanceParser = const LineAttendanceCandidateParser();

  LineHistoryParseResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _preview() {
    FocusScope.of(context).unfocus();
    setState(() => _result = _parser.parse(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final messages = result?.messages ?? const <LineHistoryMessage>[];
    final summary = result == null
        ? null
        : LineHistorySummary.fromMessages(messages);
    final attendanceCandidates = result == null
        ? const <LineAttendanceCandidate>[]
        : _attendanceParser.parseMessages(messages);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LINE履歴プレビュー'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '書き出したLINEトークを確認',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ここでは解析結果を表示するだけです。SKOのデータベースには保存・変更・削除しません。',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _controller,
                      minLines: 10,
                      maxLines: 18,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'LINEの書き出しテキストを貼り付け',
                        alignLabelWithHint: true,
                        hintText: '2026/09/01\n08:10\t山田\tおはようございます…',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _controller.text.trim().isEmpty ? null : _preview,
                        icon: const Icon(Icons.preview_outlined),
                        label: const Text('解析して確認'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (result != null && summary != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 20,
                        runSpacing: 12,
                        children: [
                          _Metric(
                            label: 'メッセージ',
                            value: '${summary.totalMessages}件',
                          ),
                          _Metric(
                            label: '送信者',
                            value: '${summary.participantCount}人',
                          ),
                          _Metric(
                            label: '解析対象外',
                            value: '${result.ignoredLineCount}行',
                          ),
                          _Metric(
                            label: '期間',
                            value: _formatRange(summary),
                          ),
                        ],
                      ),
                      if (summary.messageCountBySender.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          '送信者別メッセージ数',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry
                                in summary.messageCountBySender.entries.take(8))
                              Chip(
                                label: Text('${entry.key} ${entry.value}件'),
                              ),
                          ],
                        ),
                        if (summary.participantCount > 8) ...[
                          const SizedBox(height: 8),
                          Text('ほか ${summary.participantCount - 8} 人'),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '出勤候補（確認用）',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '日付・現場・作業員が明確な記載だけを候補表示します。ここから出勤実績を自動確定することはありません。',
                      ),
                      const SizedBox(height: 12),
                      if (attendanceCandidates.isEmpty)
                        const Text('明確な出勤候補は検出されませんでした。')
                      else ...[
                        Text(
                          '${attendanceCandidates.length}件の候補を検出',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        for (final candidate in attendanceCandidates.take(30))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '${_formatDate(candidate.workDate)}  '
                              '${candidate.siteName}  ${candidate.workerName}',
                            ),
                          ),
                        if (attendanceCandidates.length > 30)
                          Text('ほか ${attendanceCandidates.length - 30} 件あります。'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '先頭20件',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              if (messages.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('メッセージを解析できませんでした。LINEの書き出し形式を確認してください。'),
                  ),
                )
              else
                for (final message in messages.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(
                          message.sender,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(message.body),
                        trailing: Text(
                          _formatTimestamp(message.timestamp),
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
              if (messages.length > 20)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'ほか ${messages.length - 20} 件あります。現段階では確認用のため先頭20件だけ表示します。',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRange(LineHistorySummary summary) {
    final first = summary.firstTimestamp;
    final last = summary.lastTimestamp;
    if (first == null || last == null) return '—';
    final firstText = _formatDate(first);
    final lastText = _formatDate(last);
    return firstText == lastText ? firstText : '$firstText〜$lastText';
  }

  String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)}';
  }

  String _formatTimestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)}\n${two(value.hour)}:${two(value.minute)}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}
