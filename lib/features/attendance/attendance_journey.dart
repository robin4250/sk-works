/// Pure journey model. IDs/timestamps are supplied by the persistence boundary;
/// constructing a journey does not save attendance or authorize proxy actions.
enum AttendanceJourneyOrigin { selfGps, selfManual, teamProxy }
enum AttendanceJourneyPlace { company, site }
enum AttendanceJourneyPath { singleSite, multiSitePhoto }
enum AttendanceJourneyAction { startVisit, endVisit, directClockOut, companyClockOut }

class AttendanceJourneyGps {
  AttendanceJourneyGps({
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    this.accuracyM,
  }) {
    if (!latitude.isFinite || !longitude.isFinite || latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        (accuracyM != null && (!accuracyM!.isFinite || accuracyM! < 0))) {
      throw ArgumentError('Invalid GPS observation');
    }
  }

  final double latitude;
  final double longitude;
  final DateTime observedAt;
  final double? accuracyM;
}

class AttendanceJourneyEvidence {
  AttendanceJourneyEvidence({
    required this.id,
    required this.workerId,
    required this.actorId,
    required this.occurredAt,
    required this.origin,
    this.gps,
  }) {
    if (id.trim().isEmpty || workerId.trim().isEmpty || actorId.trim().isEmpty) {
      throw ArgumentError('Evidence requires event, worker and actor IDs');
    }
    if (gps != null && gps!.observedAt.isAfter(occurredAt)) {
      throw ArgumentError('A later GPS observation cannot fill historical evidence');
    }
  }

  final String id;
  final String workerId;
  final String actorId;
  final DateTime occurredAt;
  final AttendanceJourneyOrigin origin;
  final AttendanceJourneyGps? gps;

  // A proxy's location is not evidence of the employee's own GPS observation.
  bool get hasPersonalGps => origin == AttendanceJourneyOrigin.selfGps && gps != null;
  bool get isProxy => origin == AttendanceJourneyOrigin.teamProxy;
}

class AttendanceJourneyStart {
  AttendanceJourneyStart({
    required this.clockIn,
    required this.companyId,
    required DateTime workDate,
    required this.place,
    this.siteId,
    this.routeId,
    this.vehicleId,
    this.path = AttendanceJourneyPath.singleSite,
  }) : workDate = DateTime(workDate.year, workDate.month, workDate.day) {
    if (companyId.trim().isEmpty ||
        (place == AttendanceJourneyPlace.site && (siteId?.trim().isEmpty ?? true))) {
      throw ArgumentError('Clock-in requires a company and its selected place');
    }
  }

  final AttendanceJourneyEvidence clockIn;
  final String companyId;
  final DateTime workDate;
  final AttendanceJourneyPlace place;
  final String? siteId;
  final String? routeId;
  final String? vehicleId;
  final AttendanceJourneyPath path;
}

class AttendanceJourneyVisit {
  const AttendanceJourneyVisit({
    required this.shift, required this.siteId, required this.started, this.ended,
  });

  final AttendanceJourneyStart shift;
  String get sourceClockInId => shift.clockIn.id;
  DateTime get workDate => shift.workDate;

  final String siteId;
  final AttendanceJourneyEvidence started;
  final AttendanceJourneyEvidence? ended;
  bool get isOpen => ended == null;
}

class AttendanceJourneyEnd {
  const AttendanceJourneyEnd({
    required this.shift, required this.evidence, required this.place, this.siteId,
  });

  final AttendanceJourneyStart shift;
  String get sourceClockInId => shift.clockIn.id;
  DateTime get workDate => shift.workDate;

  final AttendanceJourneyEvidence evidence;
  final AttendanceJourneyPlace place;
  final String? siteId;
}

class AttendanceJourneyChoice {
  const AttendanceJourneyChoice(this.action, this.label);
  final AttendanceJourneyAction action;
  final String label;
}

class AttendanceJourney {
  AttendanceJourney._(this.start, Iterable<AttendanceJourneyVisit> visits, this.end)
    : visits = List.unmodifiable(visits);

  factory AttendanceJourney.begin(AttendanceJourneyStart start) =>
      AttendanceJourney._(start, const [], null);

  final AttendanceJourneyStart start;
  final List<AttendanceJourneyVisit> visits;
  final AttendanceJourneyEnd? end;

  String get sourceClockInId => start.clockIn.id;
  DateTime get workDate => start.workDate;
  bool get isWorking => end == null;
  AttendanceJourneyVisit? get openVisit =>
      visits.isNotEmpty && visits.last.isOpen ? visits.last : null;
  String? get lastSiteId => visits.isNotEmpty ? visits.last.siteId : start.siteId;

  List<AttendanceJourneyChoice> get nextChoices {
    if (!isWorking) return const [];
    if (openVisit != null) return const [
      AttendanceJourneyChoice(AttendanceJourneyAction.endVisit, 'この現場の訪問を終了'),
    ];
    return [
      if (start.path == AttendanceJourneyPath.multiSitePhoto)
        const AttendanceJourneyChoice(AttendanceJourneyAction.startVisit, '次の現場へ訪問開始'),
      if (lastSiteId != null)
        const AttendanceJourneyChoice(AttendanceJourneyAction.directClockOut, '最後の現場から直帰して退勤'),
      const AttendanceJourneyChoice(AttendanceJourneyAction.companyClockOut, '会社へ帰社して退勤'),
    ];
  }

  DateTime get _lastAt => visits.isEmpty ? start.clockIn.occurredAt
      : (visits.last.ended ?? visits.last.started).occurredAt;

  void _validateNext(AttendanceJourneyEvidence evidence) {
    if (!isWorking) throw StateError('勤務は退勤済みです');
    if (evidence.workerId != start.clockIn.workerId) {
      throw StateError('別の従業員の証拠は連携できません');
    }
    if (evidence.occurredAt.isBefore(_lastAt)) {
      throw StateError('実際の記録時刻の順序を確認してください');
    }
    final ids = {start.clockIn.id, for (final visit in visits) visit.started.id,
      for (final visit in visits) if (visit.ended != null) visit.ended!.id};
    if (ids.contains(evidence.id)) throw StateError('同じ証拠を二重登録できません');
  }

  AttendanceJourney startVisit({required String siteId, required AttendanceJourneyEvidence evidence}) {
    _validateNext(evidence);
    if (start.path != AttendanceJourneyPath.multiSitePhoto) {
      throw StateError('途中写真は複数現場の勤務で選択してください');
    }
    if (siteId.trim().isEmpty) throw ArgumentError('訪問先の現場を選択してください');
    if (openVisit != null) throw StateError('現在の訪問を終了してから次を開始してください');
    return AttendanceJourney._(start, [...visits,
      AttendanceJourneyVisit(shift: start, siteId: siteId, started: evidence)], null);
  }

  AttendanceJourney endVisit(AttendanceJourneyEvidence evidence) {
    _validateNext(evidence);
    final visit = openVisit;
    if (visit == null) throw StateError('終了する訪問がありません');
    return AttendanceJourney._(start, [...visits.take(visits.length - 1),
      AttendanceJourneyVisit(shift: start, siteId: visit.siteId, started: visit.started, ended: evidence)], null);
  }

  AttendanceJourney clockOut({
    required AttendanceJourneyPlace place,
    required AttendanceJourneyEvidence evidence,
  }) {
    _validateNext(evidence);
    if (openVisit != null) throw StateError('訪問終了と勤務退勤を分けて記録してください');
    if (place == AttendanceJourneyPlace.site && lastSiteId == null) {
      throw StateError('直帰する現場がありません');
    }
    return AttendanceJourney._(start, visits, AttendanceJourneyEnd(
      shift: start, evidence: evidence, place: place,
      siteId: place == AttendanceJourneyPlace.site ? lastSiteId : null,
    ));
  }
}

/// A report roster is scoped to actual attendance, never a fixed team leader.
/// The caller must obtain these records through the existing authorization boundary.
class AttendanceJourneyRoster {
  AttendanceJourneyRoster({
    required this.companyId,
    required this.siteId,
    required DateTime workDate,
    required Iterable<AttendanceJourney> attendance,
  }) : workDate = DateTime(workDate.year, workDate.month, workDate.day),
       members = List.unmodifiable(attendance.where((journey) =>
         journey.start.companyId == companyId &&
         journey.start.siteId == siteId &&
         journey.workDate == DateTime(workDate.year, workDate.month, workDate.day))) {
    final workers = members.map((member) => member.start.clockIn.workerId).toSet();
    if (workers.length != members.length) {
      throw StateError('複数の勤務候補から対象勤務を選択してください');
    }
  }

  final String companyId;
  final String siteId;
  final DateTime workDate;
  final List<AttendanceJourney> members;

  bool containsWorker(String workerId) => members.any(
    (member) => member.start.clockIn.workerId == workerId);

  /// Already closed members (including early leave) are untouched.
  /// No persistence occurs here: save the resulting group transaction atomically.
  List<AttendanceJourney> proxyClockOut({
    required String actingWorkerId,
    required AttendanceJourneyEvidence Function(AttendanceJourney member) evidenceFor,
  }) {
    if (!containsWorker(actingWorkerId)) {
      throw StateError('この勤務のメンバーが退勤を登録してください');
    }
    return List.unmodifiable(members.map((member) {
      if (!member.isWorking) return member;
      final evidence = evidenceFor(member);
      if (!evidence.isProxy || evidence.actorId != actingWorkerId) {
        throw StateError('代理退勤の入力者と対象者を記録してください');
      }
      return member.clockOut(place: AttendanceJourneyPlace.site, evidence: evidence);
    }));
  }

  /// Membership permits requesting a change, not applying it without approval.
  bool canRequestBulkCorrection(String workerId) => containsWorker(workerId);
}

/// Vehicle exclusivity follows the driver's open shift, ending at clock-out.
/// This guard must also be enforced atomically by the persistence boundary.
bool attendanceJourneyVehicleAvailable({
  required String vehicleId,
  required Iterable<AttendanceJourney> attendance,
}) => !attendance.any((journey) =>
  journey.isWorking && journey.start.vehicleId == vehicleId);
