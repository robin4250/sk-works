import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_journey.dart';

AttendanceJourneyEvidence event(String id, String time, {
  AttendanceJourneyOrigin origin = AttendanceJourneyOrigin.selfManual,
  String worker = 'worker1', AttendanceJourneyGps? gps,
}) => AttendanceJourneyEvidence(
  id: id, workerId: worker, actorId: 'actor1',
  occurredAt: DateTime.parse(time), origin: origin, gps: gps,
);

AttendanceJourney journey({AttendanceJourneyPlace place = AttendanceJourneyPlace.company}) =>
  AttendanceJourney.begin(AttendanceJourneyStart(
    clockIn: event('in1', '2026-10-31T22:00:00+09:00'),
    companyId: 'company1', workDate: DateTime(2026, 10, 31),
    place: place, siteId: place == AttendanceJourneyPlace.site ? 'site1' : null,
    routeId: 'route1', vehicleId: 'vehicle1',
    path: AttendanceJourneyPath.multiSitePhoto,
  ));

void main() {
  test('company start, two visits and direct clock-out preserve original shift identity', () {
    final initial = journey();
    final first = initial.startVisit(siteId: 'site1',
      evidence: event('v1in', '2026-10-31T23:00:00+09:00'));
    final firstEnded = first.endVisit(event('v1out', '2026-11-01T00:30:00+09:00'));
    expect(firstEnded.isWorking, isTrue);
    expect(firstEnded.end, isNull);
    final second = firstEnded.startVisit(siteId: 'site2',
      evidence: event('v2in', '2026-11-01T01:00:00+09:00'));
    final done = second.endVisit(event('v2out', '2026-11-01T05:30:00+09:00'))
      .clockOut(place: AttendanceJourneyPlace.site,
        evidence: event('out1', '2026-11-01T06:00:00+09:00'));
    expect(done.workDate, DateTime(2026, 10, 31));
    expect(done.sourceClockInId, 'in1');
    expect(done.start.routeId, 'route1');
    expect(done.start.vehicleId, 'vehicle1');
    expect(done.end!.siteId, 'site2');
    expect(done.visits.length, 2);
    expect(done.visits.every((visit) => visit.sourceClockInId == 'in1' &&
      visit.workDate == DateTime(2026, 10, 31)), isTrue);
    expect(done.end!.sourceClockInId, 'in1');
    expect(done.end!.workDate, DateTime(2026, 10, 31));
    expect(done.nextChoices, isEmpty);
    expect(initial.visits, isEmpty);
    expect(() => done.visits.clear(), throwsUnsupportedError);
  });

  test('site start may return to company and keeps clock-in site separately', () {
    final done = journey(place: AttendanceJourneyPlace.site).clockOut(
      place: AttendanceJourneyPlace.company,
      evidence: event('out1', '2026-11-01T06:00:00+09:00'),
    );
    expect(done.start.siteId, 'site1');
    expect(done.end!.place, AttendanceJourneyPlace.company);
    expect(done.end!.siteId, isNull);
  });

  test('unclosed visit cannot silently close for another visit or work clock-out', () {
    final active = journey().startVisit(siteId: 'site1',
      evidence: event('visit', '2026-10-31T23:00:00+09:00'));
    final later = event('later', '2026-11-01T06:00:00+09:00');
    expect(() => active.startVisit(siteId: 'site2', evidence: later), throwsStateError);
    expect(() => active.clockOut(place: AttendanceJourneyPlace.site, evidence: later), throwsStateError);
    expect(active.openVisit!.ended, isNull);
    expect(active.nextChoices.single.action, AttendanceJourneyAction.endVisit);
  });

  test('company start without a visited site offers no direct site clock-out', () {
    final current = journey();
    expect(current.nextChoices.map((item) => item.action),
      [AttendanceJourneyAction.startVisit, AttendanceJourneyAction.companyClockOut]);
    expect(() => current.clockOut(place: AttendanceJourneyPlace.site,
      evidence: event('out1', '2026-11-01T06:00:00+09:00')), throwsStateError);
  });

  test('closed shift rejects another clock-out and an event for another employee', () {
    final current = journey(place: AttendanceJourneyPlace.site);
    final out = event('out1', '2026-11-01T06:00:00+09:00');
    final closed = current.clockOut(place: AttendanceJourneyPlace.site, evidence: out);
    expect(() => closed.clockOut(place: AttendanceJourneyPlace.site, evidence: out), throwsStateError);
    expect(() => current.startVisit(siteId: 'site2',
      evidence: event('v2', '2026-10-31T23:00:00+09:00', worker: 'other')), throwsStateError);
  });

  test('history retains absent GPS and refuses later GPS as old evidence', () {
    final old = event('old', '2026-10-31T23:00:00+09:00',
      origin: AttendanceJourneyOrigin.selfGps);
    expect(old.gps, isNull);
    expect(old.hasPersonalGps, isFalse);
    final laterGps = AttendanceJourneyGps(latitude: 35, longitude: 139,
      observedAt: DateTime.parse('2026-11-01T06:00:00+09:00'));
    expect(() => event('repaired', '2026-10-31T23:00:00+09:00', gps: laterGps),
      throwsArgumentError);
    expect(old.gps, isNull);
  });

  test('team proxy location never becomes the employee personal GPS evidence', () {
    final gps = AttendanceJourneyGps(latitude: 35, longitude: 139,
      observedAt: DateTime.parse('2026-11-01T06:00:00+09:00'));
    final proxy = event('proxy', '2026-11-01T06:00:00+09:00',
      origin: AttendanceJourneyOrigin.teamProxy, gps: gps);
    expect(proxy.isProxy, isTrue);
    expect(proxy.hasPersonalGps, isFalse);
    expect(event('self', '2026-11-01T06:00:00+09:00',
      origin: AttendanceJourneyOrigin.selfGps, gps: gps).hasPersonalGps, isTrue);
  });

  test('record order and evidence ID uniqueness are enforced without inventing times', () {
    final current = journey().startVisit(siteId: 'site1',
      evidence: event('v1', '2026-10-31T23:00:00+09:00'));
    expect(() => current.endVisit(event('tooEarly', '2026-10-31T22:30:00+09:00')), throwsStateError);
    expect(() => current.endVisit(event('v1', '2026-11-01T01:00:00+09:00')), throwsStateError);
    expect(current.openVisit!.started.occurredAt,
      DateTime.parse('2026-10-31T23:00:00+09:00'));
  });
  test('roster includes actual same-site shifts and preserves early leave', () {
    final open = journey(place: AttendanceJourneyPlace.site);
    final earlyStart = AttendanceJourney.begin(AttendanceJourneyStart(
      clockIn: event('early-in', '2026-10-31T22:00:00+09:00', worker: 'worker2'),
      companyId: 'company1', workDate: DateTime(2026, 10, 31),
      place: AttendanceJourneyPlace.site, siteId: 'site1',
    ));
    final early = earlyStart.clockOut(place: AttendanceJourneyPlace.site,
      evidence: event('early-out', '2026-10-31T23:00:00+09:00', worker: 'worker2'));
    final unrelated = AttendanceJourney.begin(AttendanceJourneyStart(
      clockIn: event('other-in', '2026-10-31T22:00:00+09:00', worker: 'worker3'),
      companyId: 'other-company', workDate: DateTime(2026, 10, 31),
      place: AttendanceJourneyPlace.site, siteId: 'site1',
    ));
    final roster = AttendanceJourneyRoster(companyId: 'company1', siteId: 'site1',
      workDate: DateTime(2026, 10, 31), attendance: [open, early, unrelated]);
    expect(roster.members.length, 2);
    expect(roster.canRequestBulkCorrection('worker2'), isTrue);
    expect(roster.canRequestBulkCorrection('worker3'), isFalse);
    final result = roster.proxyClockOut(actingWorkerId: 'worker2', actingActorId: 'user2', evidenceFor: (member) =>
      AttendanceJourneyEvidence(id: 'proxy-out', workerId: member.start.clockIn.workerId,
        actorId: 'user2', occurredAt: DateTime.parse('2026-11-01T06:00:00+09:00'),
        origin: AttendanceJourneyOrigin.teamProxy));
    expect(result.last, same(early));
    expect(result.first.end!.evidence.isProxy, isTrue);
    expect(result.first.workDate, DateTime(2026, 10, 31));
    expect(() => roster.proxyClockOut(actingWorkerId: 'worker3', actingActorId: 'user3',
      evidenceFor: (_) => throw StateError('must not run')), throwsStateError);
  });

  test('vehicle becomes available only after driver clock-out', () {
    final active = journey(place: AttendanceJourneyPlace.site);
    expect(attendanceJourneyVehicleAvailable(vehicleId: 'vehicle1', attendance: [active]), isFalse);
    final closed = active.clockOut(place: AttendanceJourneyPlace.site,
      evidence: event('out', '2026-11-01T06:00:00+09:00'));
    expect(attendanceJourneyVehicleAvailable(vehicleId: 'vehicle1', attendance: [closed]), isTrue);
  });

  test('single-site path does not offer or accept intermediate photo visits', () {
    final single = AttendanceJourney.begin(AttendanceJourneyStart(
      clockIn: event('single-in', '2026-10-31T22:00:00+09:00'), companyId: 'company1',
      workDate: DateTime(2026, 10, 31), place: AttendanceJourneyPlace.site, siteId: 'site1'));
    expect(single.nextChoices.any((choice) => choice.action == AttendanceJourneyAction.startVisit), isFalse);
    expect(() => single.startVisit(siteId: 'site2',
      evidence: event('visit', '2026-10-31T23:00:00+09:00')), throwsStateError);
  });

}
