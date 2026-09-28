enum AppUpdateRequirement {
  none,
  optional,
  required,
}

class AppVersionPolicy {
  const AppVersionPolicy({
    required this.latestVersion,
    this.minimumSupportedVersion,
  });

  final String latestVersion;
  final String? minimumSupportedVersion;

  AppUpdateRequirement evaluate(String currentVersion) {
    if (_compare(currentVersion, latestVersion) >= 0) {
      return AppUpdateRequirement.none;
    }

    final minimum = minimumSupportedVersion;
    if (minimum != null &&
        minimum.trim().isNotEmpty &&
        _compare(currentVersion, minimum) < 0) {
      return AppUpdateRequirement.required;
    }

    return AppUpdateRequirement.optional;
  }

  static int compare(String left, String right) => _compare(left, right);

  static int _compare(String left, String right) {
    final a = _parts(left);
    final b = _parts(right);
    final length = a.length > b.length ? a.length : b.length;

    for (var index = 0; index < length; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static List<int> _parts(String value) {
    final core = value.trim().split('+').first.split('-').first;
    return [
      for (final raw in core.split('.'))
        int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
    ];
  }
}
