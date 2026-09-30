class JapanPhoneRules {
  const JapanPhoneRules._();

  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('+')) {
      return '+${trimmed.substring(1).replaceAll(RegExp(r'\D'), '')}';
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('81')) return '+$digits';
    if (digits.startsWith('0') && digits.length >= 10) {
      return '+81${digits.substring(1)}';
    }
    return '+$digits';
  }

  static bool isSupportedMobile(String raw) {
    final normalized = normalize(raw);
    return normalized.length == 13 &&
        RegExp(r'^\+81(?:70|80|90)\d{8}').hasMatch(normalized);
  }
}
