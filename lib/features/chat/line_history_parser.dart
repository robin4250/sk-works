class LineHistoryMessage {
  const LineHistoryMessage({
    required this.timestamp,
    required this.sender,
    required this.body,
  });

  final DateTime timestamp;
  final String sender;
  final String body;
}

class LineHistoryParseResult {
  const LineHistoryParseResult({
    required this.messages,
    required this.ignoredLineCount,
  });

  final List<LineHistoryMessage> messages;
  final int ignoredLineCount;
}

class LineHistoryParser {
  static final RegExp _dateHeaderPattern = RegExp(
    r'^(\d{4})[/.年](\d{1,2})[/.月](\d{1,2})日?(?:\([^)]*\))?$',
  );

  static final RegExp _messagePattern = RegExp(
    r'^(\d{1,2}):(\d{2})\t([^\t]+)\t(.*)$',
  );

  const LineHistoryParser();

  LineHistoryParseResult parse(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final messages = <LineHistoryMessage>[];

    DateTime? currentDate;
    DateTime? pendingTimestamp;
    String? pendingSender;
    final pendingBody = StringBuffer();
    var ignoredLineCount = 0;

    void flushPending() {
      if (pendingTimestamp == null || pendingSender == null) {
        pendingBody.clear();
        return;
      }

      messages.add(
        LineHistoryMessage(
          timestamp: pendingTimestamp!,
          sender: pendingSender!.trim(),
          body: pendingBody.toString().trimRight(),
        ),
      );
      pendingTimestamp = null;
      pendingSender = null;
      pendingBody.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final dateMatch = _dateHeaderPattern.firstMatch(line.trim());
      if (dateMatch != null) {
        flushPending();
        currentDate = DateTime(
          int.parse(dateMatch.group(1)!),
          int.parse(dateMatch.group(2)!),
          int.parse(dateMatch.group(3)!),
        );
        continue;
      }

      final messageMatch = _messagePattern.firstMatch(line);
      if (messageMatch != null && currentDate != null) {
        flushPending();
        final hour = int.parse(messageMatch.group(1)!);
        final minute = int.parse(messageMatch.group(2)!);
        pendingTimestamp = DateTime(
          currentDate.year,
          currentDate.month,
          currentDate.day,
          hour,
          minute,
        );
        pendingSender = messageMatch.group(3)!;
        pendingBody.write(messageMatch.group(4)!);
        continue;
      }

      if (pendingTimestamp != null) {
        pendingBody
          ..write('\n')
          ..write(rawLine);
        continue;
      }

      if (line.trim().isNotEmpty) {
        ignoredLineCount += 1;
      }
    }

    flushPending();
    return LineHistoryParseResult(
      messages: List.unmodifiable(messages),
      ignoredLineCount: ignoredLineCount,
    );
  }
}
