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
    r'^(?:\d{4}[/.年])?(\d{1,2})月?(\d{1,2})日?(?:[（(][^）)]*[）)])?$',
  );

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

      final dateMatch = _workDatePattern.firstMatch(_normalizeDateLine(lines.first));
      if (dateMatch == null) continue;

      final workDate = DateTime(
        message.timestamp.year,
        int.parse(dateMatch.group(1)!),
        int.parse(dateMatch.group(2)!),
      );

      String? pendingSite;
      for (final line in lines.skip(1)) {
        if (_looksLikeStatusLine(line)) continue;

        final parsed = _splitSiteAndWorkers(line);
        if (parsed != null) {
          final site = parsed.$1;
          final workers = parsed.$2;
          if (workers.isEmpty) {
            pendingSite = site;
            continue;
          }
          for (final worker in workers) {
            candidates.add(
              LineAttendanceCandidate(
                workDate: workDate,
                siteName: site,
                workerName: worker,
                sourceSender: message.sender,
                sourceTimestamp: message.timestamp,
              ),
            );
          }
          pendingSite = null;
          continue;
        }

        if (pendingSite != null && _looksLikeWorkerList(line)) {
          for (final worker in _splitWorkers(line)) {
            candidates.add(
              LineAttendanceCandidate(
                workDate: workDate,
                siteName: pendingSite,
                workerName: worker,
                sourceSender: message.sender,
                sourceTimestamp: message.timestamp,
              ),
            );
          }
          pendingSite = null;
        }
      }
    }

    return List.unmodifiable(candidates);
  }

  String _normalizeDateLine(String value) {
    return value
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll('５', '5')
        .replaceAll('６', '6')
        .replaceAll('７', '7')
        .replaceAll('８', '8')
        .replaceAll('９', '9')
        .replaceAll('０', '0');
  }

  bool _looksLikeStatusLine(String line) {
    return line.contains('定時') ||
        line.contains('残業') ||
        line.contains('夜勤') ||
        line.contains('鉄骨') ||
        line.startsWith('訂正');
  }

  (String, List<String>)? _splitSiteAndWorkers(String line) {
    final match = RegExp(r'^(.+?)[　\s]+(.+)$').firstMatch(line);
    if (match == null) {
      if (_looksLikeSiteOnly(line)) return (line, const <String>[]);
      return null;
    }

    final site = match.group(1)!.trim();
    final workerPart = match.group(2)!.trim();
    if (site.isEmpty || workerPart.isEmpty) return null;

    if (_looksLikeStatusLine(workerPart)) return null;
    if (!_looksLikeWorkerList(workerPart)) return null;

    return (site, _splitWorkers(workerPart));
  }

  bool _looksLikeSiteOnly(String line) {
    if (_looksLikeStatusLine(line)) return false;
    if (line.length > 20) return false;
    return !_looksLikeWorkerList(line);
  }

  bool _looksLikeWorkerList(String line) {
    if (_looksLikeStatusLine(line)) return false;
    if (line.contains('。') || line.contains('：') || line.contains(':')) {
      return false;
    }
    return _splitWorkers(line).isNotEmpty;
  }

  List<String> _splitWorkers(String value) {
    return value
        .split(RegExp(r'[、,，／/]+'))
        .map((worker) => worker.trim())
        .where((worker) => worker.isNotEmpty)
        .toList();
  }
}
