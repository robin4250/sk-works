// ignore_for_file: prefer_interpolation_to_compose_strings

class QualificationMasterCandidate {
  const QualificationMasterCandidate({
    required this.canonicalName,
    required this.variants,
    required this.occurrences,
    this.existingMasterId,
    this.existingMasterName,
  });

  final String canonicalName;
  final List<String> variants;
  final int occurrences;
  final String? existingMasterId;
  final String? existingMasterName;

  bool get needsNewMaster => existingMasterId == null;
}

class QualificationMasterCandidateService {
  const QualificationMasterCandidateService();

  List<QualificationMasterCandidate> buildCandidates({
    required Iterable<String> recognizedQualificationNames,
    required List<Map<String, dynamic>> masters,
    required List<Map<String, dynamic>> aliases,
  }) {
    final existing = _existingNames(masters, aliases);
    final grouped = <String, _CandidateAccumulator>{};

    for (final raw in recognizedQualificationNames) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final normalized = normalize(trimmed);
      if (normalized.isEmpty) continue;

      final matched = existing[normalized];
      final key = matched == null
          ? 'new:' + normalized
          : 'master:' + matched.id;
      final accumulator = grouped.putIfAbsent(
        key,
        () => _CandidateAccumulator(
          canonicalName: matched?.masterName ?? trimmed,
          existingMasterId: matched?.id,
          existingMasterName: matched?.masterName,
        ),
      );
      accumulator.occurrences++;
      accumulator.variants.add(trimmed);
    }

    final result = [
      for (final accumulator in grouped.values)
        QualificationMasterCandidate(
          canonicalName: accumulator.canonicalName,
          variants: accumulator.variants.toList()..sort(),
          occurrences: accumulator.occurrences,
          existingMasterId: accumulator.existingMasterId,
          existingMasterName: accumulator.existingMasterName,
        ),
    ];

    result.sort((a, b) {
      final byExisting =
          (a.needsNewMaster ? 1 : 0).compareTo(b.needsNewMaster ? 1 : 0);
      if (byExisting != 0) return byExisting;
      final byCount = b.occurrences.compareTo(a.occurrences);
      if (byCount != 0) return byCount;
      return a.canonicalName.compareTo(b.canonicalName);
    });
    return result;
  }

  Map<String, _ExistingQualification> _existingNames(
    List<Map<String, dynamic>> masters,
    List<Map<String, dynamic>> aliases,
  ) {
    final mastersById = <String, String>{};
    final result = <String, _ExistingQualification>{};

    for (final master in masters) {
      final id = master['id']?.toString() ?? '';
      final name = master['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      mastersById[id] = name;
      result[normalize(name)] = _ExistingQualification(id, name);
    }

    for (final alias in aliases) {
      final id = alias['qualification_master_id']?.toString() ?? '';
      final aliasName = alias['alias_name']?.toString().trim() ?? '';
      final masterName = mastersById[id];
      if (id.isEmpty || aliasName.isEmpty || masterName == null) continue;
      result[normalize(aliasName)] = _ExistingQualification(id, masterName);
    }
    return result;
  }

  String normalize(String input) {
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

class _ExistingQualification {
  const _ExistingQualification(this.id, this.masterName);

  final String id;
  final String masterName;
}

class _CandidateAccumulator {
  _CandidateAccumulator({
    required this.canonicalName,
    required this.existingMasterId,
    required this.existingMasterName,
  });

  final String canonicalName;
  final String? existingMasterId;
  final String? existingMasterName;
  final Set<String> variants = {};
  int occurrences = 0;
}
