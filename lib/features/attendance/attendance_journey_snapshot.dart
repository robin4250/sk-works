import 'attendance_journey.dart';

/// Versioned transport for a recorded journey. This codec does not authorize a
/// write or replace the server's source selection/transaction checks.
class AttendanceJourneySnapshot {
  static Map<String, Object?> encode(AttendanceJourney journey) => {
    'version': 1,
    'start': {
      'clock_in': _evidence(journey.start.clockIn),
      'company_id': journey.start.companyId,
      'work_date': _date(journey.workDate),
      'place': journey.start.place.name,
      'path': journey.start.path.name,
      'site_id': journey.start.siteId,
      'route_id': journey.start.routeId,
      'vehicle_id': journey.start.vehicleId,
    },
    'visits': [
      for (final visit in journey.visits)
        {
          'source_clock_in_id': visit.sourceClockInId,
          'work_date': _date(visit.workDate),
          'site_id': visit.siteId,
          'started': _evidence(visit.started),
          'ended': visit.ended == null ? null : _evidence(visit.ended!),
        },
    ],
    'end': journey.end == null
        ? null
        : {
            'source_clock_in_id': journey.end!.sourceClockInId,
            'work_date': _date(journey.end!.workDate),
            'place': journey.end!.place.name,
            'site_id': journey.end!.siteId,
            'evidence': _evidence(journey.end!.evidence),
          },
  };

  /// The caller supplies the exact selected source, company and worker.
  /// A failed decode must not be interpreted as an empty/new shift.
  static AttendanceJourney decode(
    Map<String, dynamic> json, {
    required String sourceClockInId,
    required String companyId,
    required String workerId,
  }) {
    if (json['version'] != 1 || !json.containsKey('end')) {
      throw const FormatException('Unknown or incomplete journey version');
    }
    final rawStart = _map(json['start']);
    final start = AttendanceJourneyStart(
      clockIn: _readEvidence(rawStart['clock_in']),
      companyId: _string(rawStart['company_id']),
      workDate: _readDate(rawStart['work_date']),
      place: _enum(AttendanceJourneyPlace.values, rawStart['place']),
      path: _enum(AttendanceJourneyPath.values, rawStart['path']),
      siteId: _optionalString(rawStart['site_id']),
      routeId: _optionalString(rawStart['route_id']),
      vehicleId: _optionalString(rawStart['vehicle_id']),
    );
    if (sourceClockInId.isEmpty ||
        companyId.isEmpty ||
        workerId.isEmpty ||
        start.clockIn.id != sourceClockInId ||
        start.companyId != companyId ||
        start.clockIn.workerId != workerId) {
      throw const FormatException(
        'Journey belongs to a different selected shift',
      );
    }
    void checkSource(Map<String, dynamic> row) {
      if (row['source_clock_in_id'] != sourceClockInId ||
          _readDate(row['work_date']) != start.workDate) {
        throw const FormatException('Recorded visit source/work date mismatch');
      }
    }

    final rawVisits = json['visits'];
    if (rawVisits is! List) {
      throw const FormatException('Missing recorded visits');
    }
    final visits = <AttendanceJourneyVisit>[];
    for (final value in rawVisits) {
      final row = _map(value);
      checkSource(row);
      if (!row.containsKey('ended')) {
        throw const FormatException('Missing recorded visit end state');
      }
      visits.add(
        AttendanceJourneyVisit(
          shift: start,
          siteId: _string(row['site_id']),
          started: _readEvidence(row['started']),
          ended: row['ended'] == null ? null : _readEvidence(row['ended']),
        ),
      );
    }
    AttendanceJourneyEnd? end;
    if (json['end'] != null) {
      final row = _map(json['end']);
      checkSource(row);
      end = AttendanceJourneyEnd(
        shift: start,
        evidence: _readEvidence(row['evidence']),
        place: _enum(AttendanceJourneyPlace.values, row['place']),
        siteId: _optionalString(row['site_id']),
      );
    }
    return AttendanceJourney.restore(start: start, visits: visits, end: end);
  }

  static Map<String, Object?> _evidence(AttendanceJourneyEvidence value) => {
    'id': value.id,
    'worker_id': value.workerId,
    'actor_id': value.actorId,
    'occurred_at': value.occurredAt.toUtc().toIso8601String(),
    'origin': value.origin.name,
    'gps': value.gps == null
        ? null
        : {
            'latitude': value.gps!.latitude,
            'longitude': value.gps!.longitude,
            'observed_at': value.gps!.observedAt.toUtc().toIso8601String(),
            'accuracy_m': value.gps!.accuracyM,
          },
  };
  static AttendanceJourneyEvidence _readEvidence(Object? value) {
    final row = _map(value);
    AttendanceJourneyGps? gps;
    if (row['gps'] != null) {
      final rawGps = _map(row['gps']);
      gps = AttendanceJourneyGps(
        latitude: _number(rawGps['latitude']),
        longitude: _number(rawGps['longitude']),
        observedAt: _time(rawGps['observed_at']),
        accuracyM: rawGps['accuracy_m'] == null
            ? null
            : _number(rawGps['accuracy_m']),
      );
    }
    return AttendanceJourneyEvidence(
      id: _string(row['id']),
      workerId: _string(row['worker_id']),
      actorId: _string(row['actor_id']),
      occurredAt: _time(row['occurred_at']),
      origin: _enum(AttendanceJourneyOrigin.values, row['origin']),
      gps: gps,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Expected recorded object');
    }
    return Map<String, dynamic>.from(value);
  }

  static String _string(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Missing recorded value');
    }
    return value;
  }

  static String? _optionalString(Object? value) =>
      value == null ? null : _string(value);
  static double _number(Object? value) {
    if (value is! num || !value.isFinite) {
      throw const FormatException('Invalid GPS number');
    }
    return value.toDouble();
  }

  static T _enum<T extends Enum>(List<T> values, Object? value) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    throw const FormatException('Unknown recorded state');
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static DateTime _readDate(Object? value) {
    final text = _string(value);
    final date = DateTime.tryParse(text);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
        date == null ||
        _date(date) != text) {
      throw const FormatException('Invalid server work date');
    }
    return date;
  }

  static DateTime _time(Object? value) {
    final text = _string(value);
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](\d{2}):(\d{2}))$',
    ).firstMatch(text);
    if (match == null ||
        int.parse(match[2]!) > 23 ||
        int.parse(match[3]!) > 59 ||
        int.parse(match[4]!) > 59 ||
        (match[5] != null && int.parse(match[5]!) > 23) ||
        (match[6] != null && int.parse(match[6]!) > 59)) {
      throw const FormatException('Invalid recorded time or time zone');
    }
    _readDate(match[1]);
    final time = DateTime.tryParse(text);
    if (time == null) throw const FormatException('Invalid recorded time');
    return time;
  }
}
