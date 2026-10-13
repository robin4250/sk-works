import 'line_attendance_candidate_parser.dart';

class LineAttendanceConflict {
  const LineAttendanceConflict({
    required this.workDate,
    required this.workerName,
    required this.siteNames,
  });

  final DateTime workDate;
  final String workerName;
  final List<String> siteNames;
}

class LineAttendanceCandidateValidation {
  const LineAttendanceCandidateValidation({
    required this.uniqueCandidates,
    required this.duplicateCount,
    required this.conflicts,
  });

  final List<LineAttendanceCandidate> uniqueCandidates;
  final int duplicateCount;
  final List<LineAttendanceConflict> conflicts;
}

class LineAttendanceCandidateValidator {
  const LineAttendanceCandidateValidator();

  LineAttendanceCandidateValidation validate(
    Iterable<LineAttendanceCandidate> candidates,
  ) {
    final uniqueByKey = <String, LineAttendanceCandidate>{};
    var duplicateCount = 0;

    for (final candidate in candidates) {
      final key = _candidateKey(candidate);
      if (uniqueByKey.containsKey(key)) {
        duplicateCount += 1;
        continue;
      }
      uniqueByKey[key] = candidate;
    }

    final sitesByWorkerDate = <String, Set<String>>{};
    final detailsByWorkerDate = <String, ({DateTime date, String worker})>{};

    for (final candidate in uniqueByKey.values) {
      final key = _workerDateKey(candidate);
      sitesByWorkerDate.putIfAbsent(key, () => <String>{}).add(candidate.siteName);
      detailsByWorkerDate[key] = (
        date: candidate.workDate,
        worker: candidate.workerName,
      );
    }

    final conflicts = <LineAttendanceConflict>[];
    for (final entry in sitesByWorkerDate.entries) {
      if (entry.value.length < 2) continue;
      final details = detailsByWorkerDate[entry.key]!;
      final sites = entry.value.toList()..sort();
      conflicts.add(
        LineAttendanceConflict(
          workDate: details.date,
          workerName: details.worker,
          siteNames: List.unmodifiable(sites),
        ),
      );
    }

    conflicts.sort((a, b) {
      final dateCompare = a.workDate.compareTo(b.workDate);
      if (dateCompare != 0) return dateCompare;
      return a.workerName.compareTo(b.workerName);
    });

    final uniqueCandidates = uniqueByKey.values.toList()
      ..sort((a, b) {
        final dateCompare = a.workDate.compareTo(b.workDate);
        if (dateCompare != 0) return dateCompare;
        final siteCompare = a.siteName.compareTo(b.siteName);
        if (siteCompare != 0) return siteCompare;
        return a.workerName.compareTo(b.workerName);
      });

    return LineAttendanceCandidateValidation(
      uniqueCandidates: List.unmodifiable(uniqueCandidates),
      duplicateCount: duplicateCount,
      conflicts: List.unmodifiable(conflicts),
    );
  }

  String _candidateKey(LineAttendanceCandidate candidate) {
    return '${_dateKey(candidate.workDate)}|'
        '${candidate.siteName.trim()}|'
        '${candidate.workerName.trim()}';
  }

  String _workerDateKey(LineAttendanceCandidate candidate) {
    return '${_dateKey(candidate.workDate)}|${candidate.workerName.trim()}';
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
