class LineAttendanceStatus {
  const LineAttendanceStatus({
    required this.siteName,
    required this.isRegularTime,
    required this.overtimeHours,
    required this.earlyHours,
    required this.isNightWork,
    required this.hasSteelAllowance,
  });

  final String siteName;
  final bool isRegularTime;
  final double overtimeHours;
  final double earlyHours;
  final bool isNightWork;
  final bool hasSteelAllowance;
}

class LineAttendanceStatusParser {
  static final RegExp _linePattern = RegExp(r'^(.+?)[　\s]+(.+)$');

  const LineAttendanceStatusParser();

  List<LineAttendanceStatus> parse(String body) {
    final statuses = <LineAttendanceStatus>[];

    for (final rawLine in body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match = _linePattern.firstMatch(line);
      if (match == null) continue;

      final siteName = match.group(1)!.trim();
      final detail = _normalizeDigits(match.group(2)!.trim());
      if (siteName.isEmpty || !_looksLikeAttendanceStatus(detail)) continue;

      statuses.add(
        LineAttendanceStatus(
          siteName: siteName,
          isRegularTime: detail.contains('定時'),
          overtimeHours: _hoursAfter(detail, '残業'),
          earlyHours: _hoursAfter(detail, '早出'),
          isNightWork: detail.contains('夜勤'),
          hasSteelAllowance: detail.contains('鉄骨'),
        ),
      );
    }

    return List.unmodifiable(statuses);
  }

  bool _looksLikeAttendanceStatus(String value) {
    return value.contains('定時') ||
        value.contains('残業') ||
        value.contains('早出') ||
        value.contains('夜勤') ||
        value.contains('鉄骨');
  }

  double _hoursAfter(String value, String label) {
    final index = value.indexOf(label);
    if (index < 0) return 0;

    final tail = value.substring(index + label.length);
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(tail);
    if (match == null) return 0;
    return double.tryParse(match.group(1)!) ?? 0;
  }

  String _normalizeDigits(String value) {
    const fullWidth = '０１２３４５６７８９．';
    const ascii = '0123456789.';
    var normalized = value;
    for (var i = 0; i < fullWidth.length; i += 1) {
      normalized = normalized.replaceAll(fullWidth[i], ascii[i]);
    }
    return normalized;
  }
}
