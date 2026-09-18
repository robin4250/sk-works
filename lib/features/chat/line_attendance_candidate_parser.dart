import 'line_history_parser.dart';

class LineAttendanceCandidate {
  const LineAttendanceCandidate({
    required this.workDate,
    required this.siteName,
    required this.workerName,
    required this.sourceSender,
    required this.sourceTimestamp,
  });

  final DateTime workDate;
  final String siteName;
  final String workerName;
  final String sourceSender;
  final DateTime sourceTimestamp;
}

class LineAttendanceCandidateParser {
  static final RegExp _workDatePattern = RegExp(
    r'^(?:(\d{4})[/.年])?(\d{1,2})[/.月](\d{1,2})日?(?:[（(][^）)]*[）)])?$',
  );
  static final RegExp _siteAndWorkersPattern = RegExp(r'^(.+?)[　\s]+(.+)$');
  static final RegExp _workerSeparatorPattern = RegExp(r'[、,，／/]');

  const LineAttendanceCandidateParser();

  List<LineAttendanceCandidate> parseMessages(
    Iterable<LineHistoryMessage> messages,
  ) {
    final candidates = <LineAttendanceCandidate>[];

    for (final message in messages) {
      final lines = message.body
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (lines.length < 2) continue;

      final normalizedDate = _normalizeDigits(lines.first);
      final dateMatch = _workDatePattern.firstMatch(normalizedDate);
      if (dateMatch == null) continue;

      final explicitYear = dateMatch.group(1);
      final workDate = DateTime(
        explicitYear == null ? message.timestamp.year : int.parse(explicitYear),
        int.parse(dateMatch.group(2)!),
        int.parse(dateMatch.group(3)!),
      );

      var index = 1;
      while (index < lines.length) {
        final line = lines[index];
        if (_looksLikeStatusLine(line)) {
          index += 1;
          continue;
        }

        final sameLine = _splitSiteAndWorkers(line);
        if (sameLine != null) {
          _appendCandidates(
            candidates,
            workDate: workDate,
            siteName: sameLine.$1,
            workers: sameLine.$2,
            source: message,
          );
          index += 1;
          continue;
        }

        if (index + 1 < lines.length) {
          final nextLine = lines[index + 1];
          if (_isConservativeSiteOnly(line) &&
              _isExplicitWorkerList(nextLine)) {
            _appendCandidates(
              candidates,
              workDate: workDate,
              siteName: line,
              workers: _splitWorkers(nextLine),
              source: message,
            );
            index += 2;
            continue;
          }
        }

        index += 1;
      }
    }

    return List.unmodifiable(candidates);
  }

  void _appendCandidates(
    List<LineAttendanceCandidate> target, {
    required DateTime workDate,
    required String siteName,
    required List<String> workers,
    required LineHistoryMessage source,
  }) {
    for (final worker in workers) {
      target.add(
        LineAttendanceCandidate(
          workDate: workDate,
          siteName: siteName,
          workerName: worker,
          sourceSender: source.sender,
          sourceTimestamp: source.timestamp,
        ),
      );
    }
  }

  (String, List<String>)? _splitSiteAndWorkers(String line) {
    final match = _siteAndWorkersPattern.firstMatch(line);
    if (match == null) return null;

    final site = match.group(1)!.trim();
    final workerPart = match.group(2)!.trim();
    if (site.isEmpty || workerPart.isEmpty) return null;
    if (_looksLikeStatusLine(site) || _looksLikeStatusLine(workerPart)) {
      return null;
    }
    if (!_looksLikeWorkerSegment(workerPart)) return null;

    return (site, _splitWorkers(workerPart));
  }

  bool _isConservativeSiteOnly(String line) {
    if (_looksLikeStatusLine(line)) return false;
    if (_workerSeparatorPattern.hasMatch(line)) return false;
    if (line.length > 24) return false;
    if (line.contains('。') || line.contains('：') || line.contains(':')) {
      return false;
    }
    return true;
  }

  bool _isExplicitWorkerList(String line) {
    if (_looksLikeStatusLine(line)) return false;
    if (!_workerSeparatorPattern.hasMatch(line)) return false;
    return _splitWorkers(line).length >= 2;
  }

  bool _looksLikeWorkerSegment(String value) {
    if (_looksLikeStatusLine(value)) return false;
    if (value.contains('。') || value.contains('：') || value.contains(':')) {
      return false;
    }
    final workers = _splitWorkers(value);
    return workers.isNotEmpty && workers.every((worker) => worker.length <= 20);
  }

  bool _looksLikeStatusLine(String line) {
    return line.contains('定時') ||
        line.contains('残業') ||
        line.contains('夜勤') ||
        line.contains('早出') ||
        line.contains('鉄骨') ||
        line.startsWith('訂正');
  }

  List<String> _splitWorkers(String value) {
    return value
        .split(RegExp(r'[、,，／/]+'))
        .map((worker) => worker.trim())
        .where((worker) => worker.isNotEmpty)
        .toList();
  }

  String _normalizeDigits(String value) {
    const fullWidth = '０１２３４５６７８９';
    const ascii = '0123456789';
    var normalized = value;
    for (var i = 0; i < fullWidth.length; i += 1) {
      normalized = normalized.replaceAll(fullWidth[i], ascii[i]);
    }
    return normalized;
  }
}
