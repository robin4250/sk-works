import 'dart:convert';
import 'dart:math';

/// A verified historical record is not an active clock-in or an unknown result.
class ArchivedCaptureVerification implements Exception {
  const ArchivedCaptureVerification(this.verification);
  final Map<String, dynamic> verification;
}

/// One immutable INSERT identity. Server-owned time and work_date are excluded.
class CaptureVerificationDraft {
  CaptureVerificationDraft(Map<String, Object?> payload, {DateTime? preparedAt})
    : preparedAt = (preparedAt ?? DateTime.now()).toUtc(),
      payload = Map.unmodifiable({...payload, 'id': _uuid()});
  CaptureVerificationDraft._(this.payload, this.preparedAt);
  factory CaptureVerificationDraft.restore(String encoded) {
    final envelope = jsonDecode(encoded) as Map;
    final payload = Map<String, Object?>.from(envelope['payload'] as Map);
    final preparedAt = DateTime.tryParse(
      envelope['prepared_at']?.toString() ?? '',
    );
    if (preparedAt == null ||
        payload['id'] is! String ||
        payload['capture_contract_version'] != 1 ||
        payload['verification_mode'] != 'location_photo' ||
        payload['company_id'] is! String ||
        payload['worker_id'] is! String ||
        payload['created_by'] is! String ||
        payload.containsKey('confirmed_at') ||
        payload.containsKey('work_date')) {
      throw StateError('保留中の撮影記録を確認できません');
    }
    return CaptureVerificationDraft._(
      Map.unmodifiable(payload),
      preparedAt.toUtc(),
    );
  }
  final DateTime preparedAt;
  bool canInsertOn(DateTime now) {
    if (payload['event_type'] != 'clock_in') {
      return true;
    }
    String japanDate(DateTime time) => time
        .toUtc()
        .add(const Duration(hours: 9))
        .toIso8601String()
        .substring(0, 10);
    return japanDate(preparedAt) == japanDate(now);
  }

  final Map<String, Object?> payload;
  String get id => payload['id'] as String;
  String get encoded => jsonEncode({
    'prepared_at': preparedAt.toIso8601String(),
    'payload': payload,
  });

  // Postgres float8 output with extra_float_digits=0 has 15 significant
  // digits. Recover that database representation without accepting arbitrary
  // GPS tolerances or changing the durable original capture payload.
  static const _floatEvidenceFields = {
    'latitude',
    'longitude',
    'accuracy_m',
    'distance_to_site_m',
  };
  static bool _sameFloatEvidence(Object? actual, Object? expected) {
    if (actual is! num ||
        expected is! num ||
        !actual.isFinite ||
        !expected.isFinite)
      return false;
    return actual == expected ||
        actual == double.parse(expected.toStringAsPrecision(15));
  }

  bool matchesRow(Map<String, dynamic> row) {
    for (final entry in payload.entries) {
      final actual = row[entry.key];
      final expected = entry.value;
      if (_floatEvidenceFields.contains(entry.key) &&
          actual is num &&
          expected is num) {
        if (!_sameFloatEvidence(actual, expected)) return false;
      } else if (entry.key.endsWith('_at') &&
          expected is String &&
          actual is String) {
        final a = DateTime.tryParse(actual);
        final b = DateTime.tryParse(expected);
        if (a == null || b == null || !a.isAtSameMomentAs(b)) {
          return false;
        }
      } else if (actual != expected) {
        return false;
      }
    }
    return row['confirmed_at'] is String && row['work_date'] is String;
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// Read failure never falls through to INSERT; retries retain the identical UUID.
Future<Map<String, dynamic>> recoverOrInsertCaptureDraft(
  CaptureVerificationDraft draft, {
  required Future<Map<String, dynamic>?> Function() readExact,
  required Future<Map<String, dynamic>> Function() insert,
}) async {
  Map<String, dynamic> checked(Map<String, dynamic> row) {
    if (!draft.matchesRow(row)) {
      throw StateError('保留中の勤怠記録が一致しません');
    }
    return row;
  }

  final existing = await readExact();
  if (existing != null) {
    return checked(existing);
  }
  try {
    return checked(await insert());
  } catch (_) {
    final recovered = await readExact();
    if (recovered == null) {
      rethrow;
    }
    return checked(recovered);
  }
}
