import 'dart:convert';

/// Status of the published payroll conditions, never the editable company rates.
/// An older reader without this source contract must not be called unregistered.
enum CompanyCommonApplicationStatus { notRegistered, startsLater }

CompanyCommonApplicationStatus? companyCommonApplicationStatus({
  required String? sourceJson,
  required String month,
  required bool frozen,
  required bool historyMissing,
  required bool hasItems,
  required bool blocked,
}) {
  if (sourceJson == null || frozen || historyMissing || hasItems || blocked) {
    return null;
  }
  try {
    final source = jsonDecode(sourceJson);
    if (source is! Map || !source.containsKey('starts_on') ||
        !source.containsKey('publication_version') ||
        !const ['daily', 'hourly', 'monthly'].contains(source['pay_type']) ||
        source['items'] is! List || (source['items'] as List).isNotEmpty ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(month)) {
      return null;
    }
    final startsOn = source['starts_on'];
    if (startsOn == null && source['publication_version'] == null) {
      return CompanyCommonApplicationStatus.notRegistered;
    }
    if (startsOn is String &&
        RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(startsOn) &&
        startsOn.compareTo(month) > 0 && source['publication_version'] == null) {
      return CompanyCommonApplicationStatus.startsLater;
    }
  } on FormatException {
    // The underlying reader remains authoritative for malformed responses.
  }
  return null;
}
