import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_journey.dart';
import 'package:sk_works/features/attendance/attendance_journey_snapshot.dart';
import 'attendance_journey_test.dart' as fixture;

AttendanceJourney recorded() => fixture
    .journey()
    .startVisit(
      siteId: 'site1',
      evidence: fixture.event('v1', '2026-10-31T23:00:00+09:00'),
    )
    .endVisit(fixture.event('e1', '2026-11-01T00:30:00+09:00'))
    .startVisit(
      siteId: 'site2',
      evidence: fixture.event('v2', '2026-11-01T01:00:00+09:00'),
    );
Map<String, dynamic> jsonFor(AttendanceJourney value) =>
    jsonDecode(jsonEncode(AttendanceJourneySnapshot.encode(value)))
        as Map<String, dynamic>;
AttendanceJourney read(Map<String, dynamic> json) =>
    AttendanceJourneySnapshot.decode(
      json,
      sourceClockInId: 'in1',
      companyId: 'company1',
      workerId: 'worker1',
    );

void main() {
  test(
    'reopening a midnight journey retains the open visit and original work date',
    () {
      final before = recorded();
      final restored = read(jsonFor(before));
      expect(restored.sourceClockInId, 'in1');
      expect(restored.workDate, DateTime(2026, 10, 31));
      expect(restored.openVisit!.siteId, 'site2');
      expect(
        restored.nextChoices.single.action,
        AttendanceJourneyAction.endVisit,
      );
      expect(restored.end, isNull);
      expect(
        restored.visits.first.ended!.occurredAt,
        before.visits.first.ended!.occurredAt,
      );
      final next = restored.endVisit(
        fixture.event('e2', '2026-11-01T02:00:00+09:00'),
      );
      expect(next.isWorking, isTrue);
      expect(next.openVisit, isNull);
      expect(restored.openVisit, isNotNull);
      expect(() => restored.visits.clear(), throwsUnsupportedError);
    },
  );

  test(
    'completed journey and proxy GPS provenance survive a JSON round trip',
    () {
      final time = DateTime.parse('2026-11-01T06:00:00+09:00');
      final done = recorded()
          .endVisit(fixture.event('e2', '2026-11-01T05:00:00+09:00'))
          .clockOut(
            place: AttendanceJourneyPlace.site,
            evidence: fixture.event(
              'out',
              '2026-11-01T06:00:00+09:00',
              origin: AttendanceJourneyOrigin.teamProxy,
              gps: AttendanceJourneyGps(
                latitude: 35,
                longitude: 139,
                observedAt: time,
                accuracyM: 5,
              ),
            ),
          );
      final restored = read(jsonFor(done));
      expect(restored.isWorking, isFalse);
      expect(restored.end!.siteId, 'site2');
      expect(restored.end!.evidence.isProxy, isTrue);
      expect(restored.end!.evidence.hasPersonalGps, isFalse);
      expect(restored.end!.evidence.gps!.accuracyM, 5);
      expect(jsonFor(restored), jsonFor(done));
    },
  );

  test('missing GPS remains missing instead of acquiring current position', () {
    final restored = read(jsonFor(recorded()));
    expect(restored.visits.every((v) => v.started.gps == null), isTrue);
  });

  test('another selected company, worker or source is rejected', () {
    final json = jsonFor(recorded());
    for (final values in [
      ['other', 'company1', 'worker1'],
      ['in1', 'other', 'worker1'],
      ['in1', 'company1', 'other'],
    ]) {
      expect(
        () => AttendanceJourneySnapshot.decode(
          json,
          sourceClockInId: values[0],
          companyId: values[1],
          workerId: values[2],
        ),
        throwsFormatException,
      );
    }
  });

  test('mixed source and next-calendar-day work dates are rejected', () {
    for (final change in [
      {'source_clock_in_id': 'other'},
      {'work_date': '2026-11-01'},
    ]) {
      final json = jsonFor(recorded());
      (json['visits'][1] as Map).addAll(change);
      expect(() => read(json), throwsFormatException);
    }
  });

  test(
    'missing history, unknown schema/state and normalized dates fail closed',
    () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (j) => j['version'] = 2,
        (j) => j.remove('visits'),
        (j) => j.remove('end'),
        (j) => (j['visits'][0] as Map).remove('ended'),
        (j) =>
            j['visits'][0]['started']['occurred_at'] = '2026-02-30T23:00:00Z',
        (j) =>
            j['visits'][0]['started']['occurred_at'] = '2026-10-31T25:00:00Z',
        (j) => j['start']['path'] = 'unknown',
        (j) => j['start']['work_date'] = '2026-02-30',
        (j) => j['visits'][0]['started']['occurred_at'] = '2026-10-31T23:00:00',
        (j) => j['visits'][0]['started']['actor_id'] = '',
      ];
      for (final mutate in mutations) {
        final json = jsonFor(recorded());
        mutate(json);
        expect(() => read(json), throwsFormatException);
      }
    },
  );

  test(
    'replay rejects out-of-order times, duplicate IDs and another worker',
    () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (j) =>
            j['visits'][1]['started']['occurred_at'] = '2026-10-31T13:00:00Z',
        (j) => j['visits'][1]['started']['id'] = 'v1',
        (j) => j['visits'][1]['started']['worker_id'] = 'other',
        (j) => j['visits'][0]['ended'] = null,
      ];
      for (final mutate in mutations) {
        final json = jsonFor(recorded());
        mutate(json);
        expect(() => read(json), throwsStateError);
      }
    },
  );

  test(
    'cannot restore clock-out over an open visit or a different last site',
    () {
      final done = recorded()
          .endVisit(fixture.event('e2', '2026-11-01T05:00:00+09:00'))
          .clockOut(
            place: AttendanceJourneyPlace.site,
            evidence: fixture.event('out', '2026-11-01T06:00:00+09:00'),
          );
      final open = jsonFor(done);
      open['visits'][1]['ended'] = null;
      expect(() => read(open), throwsStateError);
      final wrongSite = jsonFor(done);
      wrongSite['end']['site_id'] = 'site1';
      expect(() => read(wrongSite), throwsStateError);
      final wrongDate = jsonFor(done);
      wrongDate['end']['work_date'] = '2026-11-01';
      expect(() => read(wrongDate), throwsFormatException);
    },
  );

  test('typed restore also rejects a foreign shift before replay', () {
    final start = fixture.journey().start;
    final foreign = AttendanceJourneyStart(
      clockIn: start.clockIn,
      companyId: 'other',
      workDate: start.workDate,
      place: start.place,
    );
    expect(
      () => AttendanceJourney.restore(
        start: start,
        visits: [
          AttendanceJourneyVisit(
            shift: foreign,
            siteId: 'site1',
            started: fixture.event('v', '2026-10-31T23:00:00+09:00'),
          ),
        ],
      ),
      throwsStateError,
    );
  });
}
