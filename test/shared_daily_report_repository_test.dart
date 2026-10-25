import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/shared_daily_report_repository.dart';

void main() {
  const actor = '00000000-0000-0000-0000-000000000010';
  const company = '00000000-0000-0000-0000-000000000001';
  const worker = '00000000-0000-0000-0000-000000000020';
  const source = '00000000-0000-0000-0000-000000000030';
  const report = '00000000-0000-0000-0000-000000000040';
  Map<String, dynamic> row() => {
    'schema': 1, 'actor_id': actor, 'company_id': company, 'worker_id': worker,
    'source_clock_in_id': source, 'report_id': report, 'work_date': '2026-10-25',
    'state': 'reporter_saved_waiting_supervisor', 'enabled': true,
    'can_manage_attendance': false, 'reporter_saved': true,
    'supervisor_saved': false, 'source_attached': true, 'supervisor_ready': true,
    'first_reporter_covers_work_only': true, 'management_hold': false, 'management_hold_reason': null,
    'pending_members': <dynamic>[], 'supervisor_pending_reasons': <String>[],
    'reporter_name': '報告者', 'report_status': 'draft',
    'report_updated_at': '2026-10-25T08:00:00.123456Z',
    'signature_scope_fingerprint': List.filled(64,'a').join(), 'hours_annex': null,
    'work_basis': {'contract_version': 2, 'report': {'id': report, 'company_id': company,
      'work_date': '2026-10-25', 'site_id': source, 'route_assignment_id': null,
      'work_description': '保存済みの作業内容'}, 'roster': [{'worker_id': worker}]},
  };
  Map<String, dynamic> input({bool confirmed = true}) => {
    'worker_id': worker, 'work_date': '2026-10-25', 'hours': confirmed ? 7.25 : null,
    'hours_required': true, 'revision': confirmed ? 1 : 0,
    'confirmation_id': confirmed ? 1 : null, 'confirmed_by': confirmed ? actor : null,
    'confirmed_at': confirmed ? '2026-10-25T08:00:00Z' : null,
    'source_fingerprint': List.filled(64, 'c').join(), 'source_current': confirmed,
    'required': true, 'confirmed': confirmed, 'facts_confirmed': confirmed, 'facts_current': confirmed,
    'reason': <String>[], 'worker_facts': confirmed ? {
      'schema': 1, 'overtime_hours': 0, 'early_hours': 0, 'night_hours': 0,
      'work_category': 'day', 'allowance_amount': 0, 'allowance_label': null,
      'company_allowance_selections': {'contract_version': 1, 'items': <dynamic>[]},
      'company_allowance_legacy_labels': null, 'vehicle_id': null, 'route_assignment_id': null,
      'odometer_km': null,
    } : null,
  };
  SharedDailyReportContext parse(Map<String, dynamic> value) =>
      SharedDailyReportContext.parse(value, actorId: actor,
        companyId: company, workerId: worker, sourceClockInId: source,
        reportId: report, workDate: DateTime(2026, 10, 25));
  test('reporter saved means readonly facts and supervisor collection', () {
    final value = parse(row());
    expect(value.signedFactsReadOnly, isTrue);
    expect(value.canCollectSupervisor, isTrue);
    expect(value.expectedUpdatedAt!.microsecond, 456);
  });
  test('supervisor saved does not expose overwrite action', () {
    final value = parse(row()..addAll({'state': 'supervisor_saved', 'supervisor_saved': true}));
    expect(value.canCollectSupervisor, isFalse);
    expect(value.signedFactsReadOnly, isTrue);
  });
  test('explicit disabled differs from unknown response', () {
    final value = parse(row()..addAll({'enabled': false, 'state': 'disabled'}));
    expect(value.enabled, isFalse);
    expect(value.canCollectSupervisor, isFalse);
    expect(() => SharedDailyReportContext.parse(null, actorId: actor), throwsStateError);
  });
  test('disabled must be explicitly false', () {
    expect(() => parse(row()..['state'] = 'disabled'), throwsStateError);
  });
  for (final key in ['enabled', 'can_manage_attendance', 'reporter_saved', 'supervisor_saved', 'source_attached', 'supervisor_ready']) {
    test('missing $key cannot unlock or grant authority', () {
      expect(() => parse(row()..remove(key)), throwsStateError);
    });
  }
  for (final key in ['actor_id', 'company_id', 'worker_id', 'report_id', 'source_clock_in_id']) {
    test('different $key cannot replace selected report identity', () {
      expect(() => parse(row()..[key] = '00000000-0000-0000-0000-000000000099'), throwsStateError);
    });
  }
  test('other day rejected', () {
    expect(() => parse(row()..['work_date'] = '2026-10-24'), throwsStateError);
  });
  test('invalid calendar date rejected', () {
    expect(() => parse(row()..['work_date'] = '2026-02-30'), throwsStateError);
  });
  test('unknown registration state rejected', () {
    expect(() => parse(row()..['state'] = 'complete_without_signature'), throwsStateError);
  });
  test('management is explicit server capability', () {
    final value = parse(row()..['can_manage_attendance'] = true);
    expect(value.canManageAttendance, isTrue);
  });
  test('hours-basis correction is not a silent complete state', () {
    final value = parse(row()..['state'] = 'recorded_hours_basis_requires_approved_edit');
    expect(value.needsApprovedEdit, isTrue);
  });
  test('signature context requires complete scope fingerprint', () {
    expect(() => parse(row()..remove('signature_scope_fingerprint')), throwsStateError);
    expect(() => parse(row()..['signature_scope_fingerprint'] = 'old'), throwsStateError);
  });
  test('pending hours annex blocks final supervisor capture', () {
    final value = parse(row()..['hours_annex'] = {
      'schema': 2, 'enabled': true, 'required': true, 'ready': false,
      'fingerprint': List.filled(64, 'b').join(), 'inputs': [input(confirmed: false)],
    });
    expect(value.canCollectSupervisor, isFalse);
  });
  test('ready hours annex remains bound to fingerprint', () {
    final value = parse(row()..['hours_annex'] = {
      'schema': 2, 'enabled': true, 'required': true, 'ready': true,
      'fingerprint': List.filled(64, 'b').join(), 'inputs': [input()],
    });
    expect(value.canCollectSupervisor, isTrue);
  });
  test('unknown annex shape is not ready or absent', () {
    expect(() => parse(row()..['hours_annex'] = {'schema': 2}), throwsStateError);
  });
  test('invalid hours or missing actual fields cannot be previewed as signed', () {
    final value = input()..['hours'] = double.nan;
    expect(() => parse(row()..['hours_annex'] = {'schema': 2, 'enabled': true,
      'required': true, 'ready': true, 'fingerprint': List.filled(64, 'b').join(),
      'inputs': [value]}), throwsStateError);
  });
  test('frozen common work preview is the same immutable server snapshot', () {
    final value = parse(row());
    expect(value.workDescription, '保存済みの作業内容');
    expect(value.workRosterIds, [worker]);
    expect(() => (value.workBasis!['report'] as Map)['work_description'] = '変更', throwsUnsupportedError);
  });
  test('pending members allow explanation but no signature capture', () {
    final value = parse(row()..addAll({'supervisor_ready': false,
      'pending_members': [{'worker_id': worker, 'reason': 'clock_out_missing_or_conflicting'}],
      'supervisor_pending_reasons': ['personal_checkout_pending']}));
    expect(value.canAccessSupervisorCollection, isTrue);
    expect(value.canCollectSupervisor, isFalse);
    expect(value.pendingWorkerIds, [worker]);
  });
  test('managed financial hold preserves scoped management permission and never allows signatures', () {
    final value = row()..['state'] = 'managed_financial_hold'
      ..['management_hold'] = true
      ..['management_hold_reason'] = 'managed_attendance_financial_vector_changed_pending'
      ..['can_manage_attendance'] = true
      ..['signature_scope_fingerprint'] = null
      ..['supervisor_ready'] = false;
    final result = parse(value);
    expect(result.isManagementHold, isTrue);
    expect(result.canManageAttendance, isTrue);
    expect(result.canCollectSupervisor, isFalse);
    expect(const SharedReportManagementHold().retryAllowed, isFalse);
  });

  test('manual source ambiguity remains a persistent management hold', () {
    final value = row()..['state'] = 'managed_financial_hold'
      ..['management_hold'] = true
      ..['management_hold_reason'] = 'managed_roster_manual_source_ambiguous'
      ..['signature_scope_fingerprint'] = null
      ..['supervisor_ready'] = false;
    expect(parse(value).isManagementHold, isTrue);
    expect(const SharedReportManagementHold(reasonCode: 'managed_roster_manual_source_ambiguous').message,
      contains('重複'));
  });

  test('exact approved editor can collect without a management or own-source grant', () {
    final value = row()..['worker_id'] = null..['source_clock_in_id'] = null
      ..['approved_edit_request_id'] = '00000000-0000-0000-0000-000000000050';
    final context = SharedDailyReportContext.parse(value, actorId: actor, companyId: company, reportId: report);
    expect(context.approvedEditRequestId, '00000000-0000-0000-0000-000000000050');
    expect(context.canManageAttendance, isFalse);
    expect(context.canCollectSupervisor, isTrue);
    value['supervisor_saved'] = true;
    expect(SharedDailyReportContext.parse(value, actorId: actor).canCollectSupervisor, isFalse);
    value['approved_edit_request_id'] = 'not-a-request-id';
    expect(() => SharedDailyReportContext.parse(value, actorId: actor), throwsStateError);
  });

}
