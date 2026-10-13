class QualificationMasterCandidate {
  const QualificationMasterCandidate({
    required this.masterId,
    required this.canonicalName,
    required this.matchedText,
    required this.score,
  });

  final String masterId;
  final String canonicalName;
  final String matchedText;
  final double score;
}

class QualificationRecognitionCandidate {
  const QualificationRecognitionCandidate({
    required this.rawText,
    required this.qualificationCandidates,
    this.personName,
    this.expiresAt,
    this.certificateNumber,
  });

  final String rawText;
  final List<QualificationMasterCandidate> qualificationCandidates;
  final String? personName;
  final DateTime? expiresAt;
  final String? certificateNumber;
}

class QualificationRecognitionMatcher {
  const QualificationRecognitionMatcher();

  QualificationRecognitionCandidate buildCandidate({
    required String rawText,
    required List<Map<String, dynamic>> masters,
    required List<Map<String, dynamic>> aliases,
    List<String> knownWorkerNames = const [],
  }) {
    final compact = _normalize(rawText);
    final candidates = <QualificationMasterCandidate>[];

    for (final master in masters) {
      final id = master['id']?.toString() ?? '';
      final name = master['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;

      final names = <String>{name};
      for (final alias in aliases) {
        if (alias['qualification_master_id']?.toString() == id) {
          final value = alias['alias_name']?.toString().trim();
          if (value != null && value.isNotEmpty) names.add(value);
        }
      }

      double best = 0;
      String matched = name;
      for (final value in names) {
        final normalized = _normalize(value);
        if (normalized.isEmpty) continue;
        final score = compact.contains(normalized)
            ? 1.0
            : _tokenOverlap(compact, normalized);
        if (score > best) {
          best = score;
          matched = value;
        }
      }
      if (best >= 0.45) {
        candidates.add(
          QualificationMasterCandidate(
            masterId: id,
            canonicalName: name,
            matchedText: matched,
            score: best,
          ),
        );
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    return QualificationRecognitionCandidate(
      rawText: rawText,
      qualificationCandidates: candidates.take(5).toList(growable: false),
      personName: _matchWorker(rawText, knownWorkerNames),
      expiresAt: _extractExpiry(rawText),
      certificateNumber: _extractCertificateNumber(rawText),
    );
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[\s　・･()（）【】\[\]「」『』:：/／\\._-]+'), '');
  }

  double _tokenOverlap(String haystack, String needle) {
    if (needle.length < 2 || haystack.isEmpty) return 0;
    final grams = <String>{};
    for (var i = 0; i < needle.length - 1; i++) {
      grams.add(needle.substring(i, i + 2));
    }
    if (grams.isEmpty) return 0;
    var hit = 0;
    for (final gram in grams) {
      if (haystack.contains(gram)) hit++;
    }
    return hit / grams.length;
  }

  String? _matchWorker(String rawText, List<String> names) {
    final compact = _normalize(rawText);
    final matches = names
        .where((name) => name.trim().isNotEmpty)
        .where((name) => compact.contains(_normalize(name)))
        .toList(growable: false);
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.length.compareTo(a.length));
    return matches.first;
  }

  DateTime? _extractExpiry(String rawText) {
    final patterns = [
      RegExp(r'(?:有効期限|期限|満了)[^0-9]{0,12}(20\d{2})[年./-](\d{1,2})[月./-](\d{1,2})'),
      RegExp(r'(20\d{2})[年./-](\d{1,2})[月./-](\d{1,2})[^\n]{0,12}(?:まで|有効|期限)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(rawText);
      if (match == null) continue;
      final year = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final day = int.tryParse(match.group(3) ?? '');
      if (year == null || month == null || day == null) continue;
      final value = DateTime(year, month, day);
      if (value.year == year && value.month == month && value.day == day) {
        return value;
      }
    }
    return null;
  }

  String? _extractCertificateNumber(String rawText) {
    final match = RegExp(
      r'(?:証明書番号|修了証番号|免許番号|番号|No\.?)[：:\s]*([A-Za-z0-9-]{4,32})',
      caseSensitive: false,
    ).firstMatch(rawText);
    return match?.group(1);
  }
}
