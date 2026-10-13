class QualificationRecognitionCandidate {
  const QualificationRecognitionCandidate({
    required this.rawText,
    this.qualificationName,
    this.personName,
    this.expiresAt,
    this.matchedMasterId,
    this.matchedMasterName,
    this.suggestedAlias,
  });

  final String rawText;
  final String? qualificationName;
  final String? personName;
  final DateTime? expiresAt;
  final String? matchedMasterId;
  final String? matchedMasterName;
  final String? suggestedAlias;

  bool get matchedExistingMaster => matchedMasterId != null;
}

class QualificationRecognitionService {
  const QualificationRecognitionService();

  QualificationRecognitionCandidate fromRecognizedText({
    required String recognizedText,
    required List<Map<String, dynamic>> masters,
    required List<Map<String, dynamic>> aliases,
  }) {
    final lines = recognizedText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    final match = _matchMaster(lines, masters, aliases);
    final qualificationName =
        match?.displayName ?? _qualificationCandidate(lines);
    final personName = _personCandidate(lines);
    final expiresAt = _expiryCandidate(recognizedText);

    return QualificationRecognitionCandidate(
      rawText: recognizedText,
      qualificationName: qualificationName,
      personName: personName,
      expiresAt: expiresAt,
      matchedMasterId: match?.id,
      matchedMasterName: match?.masterName,
      suggestedAlias: match != null &&
              qualificationName != null &&
              _normalize(qualificationName) != _normalize(match.masterName)
          ? qualificationName
          : null,
    );
  }

  _MasterMatch? _matchMaster(
    List<String> lines,
    List<Map<String, dynamic>> masters,
    List<Map<String, dynamic>> aliases,
  ) {
    final masterById = <String, Map<String, dynamic>>{
      for (final master in masters)
        if ((master['id']?.toString() ?? '').isNotEmpty)
          master['id'].toString(): master,
    };

    final names = <_MasterMatch>[];
    for (final master in masters) {
      final id = master['id']?.toString() ?? '';
      final name = master['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      names.add(_MasterMatch(id: id, masterName: name, displayName: name));
    }
    for (final alias in aliases) {
      final id = alias['qualification_master_id']?.toString() ?? '';
      final aliasName = alias['alias_name']?.toString().trim() ?? '';
      final master = masterById[id];
      final masterName = master?['name']?.toString().trim() ?? '';
      if (id.isEmpty || aliasName.isEmpty || masterName.isEmpty) continue;
      names.add(
        _MasterMatch(
          id: id,
          masterName: masterName,
          displayName: aliasName,
        ),
      );
    }

    _MasterMatch? best;
    var bestScore = 0;
    for (final line in lines) {
      final normalizedLine = _normalize(line);
      if (normalizedLine.isEmpty) continue;
      for (final candidate in names) {
        final normalizedCandidate = _normalize(candidate.displayName);
        if (normalizedCandidate.isEmpty) continue;
        final exact = normalizedLine == normalizedCandidate;
        final contained = normalizedLine.contains(normalizedCandidate) ||
            normalizedCandidate.contains(normalizedLine);
        if (!exact && !contained) continue;
        final score = exact ? 10000 + normalizedCandidate.length : normalizedCandidate.length;
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }
    }
    return best;
  }

  String? _qualificationCandidate(List<String> lines) {
    const hints = [
      '資格',
      '免許',
      '技能講習',
      '特別教育',
      '修了証',
      '認定証',
      '資格者証',
      '運転者証',
    ];
    for (final line in lines) {
      if (hints.any(line.contains) && line.length <= 80) return line;
    }
    return null;
  }

  String? _personCandidate(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final normalized = _normalize(line);
      if (normalized == '氏名' || normalized == '姓名' || normalized == '名前') {
        if (i + 1 < lines.length && lines[i + 1].length <= 40) {
          return lines[i + 1];
        }
      }
      for (final label in ['氏名', '姓名', '名前']) {
        if (line.startsWith(label)) {
          final value = line.substring(label.length).replaceFirst(
                RegExp(r'^[：:\s]+'),
                '',
              );
          if (value.isNotEmpty && value.length <= 40) return value;
        }
      }
    }
    return null;
  }

  DateTime? _expiryCandidate(String text) {
    final patterns = <RegExp>[
      RegExp(
        r'(?:有効期限|期限|満了日)[^0-9]{0,10}(20\d{2})[年/.-]\s*(\d{1,2})[月/.-]\s*(\d{1,2})日?',
      ),
      RegExp(
        r'(20\d{2})[年/.-]\s*(\d{1,2})[月/.-]\s*(\d{1,2})日?[^\n]{0,12}(?:まで|有効)',
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final year = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final day = int.tryParse(match.group(3) ?? '');
      if (year == null || month == null || day == null) continue;
      final parsed = DateTime(year, month, day);
      if (parsed.year == year &&
          parsed.month == month &&
          parsed.day == day) {
        return parsed;
      }
    }
    return null;
  }

  String _normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune >= 0xFF21 && rune <= 0xFF3A) {
        buffer.writeCharCode(rune - 0xFEE0 + 0x20);
      } else if (rune >= 0xFF41 && rune <= 0xFF5A) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s　・･:：()（）\-ー_/／.]'), '');
  }
}

class _MasterMatch {
  const _MasterMatch({
    required this.id,
    required this.masterName,
    required this.displayName,
  });

  final String id;
  final String masterName;
  final String displayName;
}
