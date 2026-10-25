const notificationActor = '10000000-0000-0000-0000-000000000001';
const notificationCompany = '10000000-0000-0000-0000-000000000002';
const notificationWorker = '10000000-0000-0000-0000-000000000003';
const notificationReport = '10000000-0000-0000-0000-000000000004';
const notificationSite = '10000000-0000-0000-0000-000000000005';
const notificationClockIn = '10000000-0000-0000-0000-000000000006';
const notificationClockOut = '10000000-0000-0000-0000-000000000007';
Map<String, dynamic> registrationNotification({String state = 'reporter_signature_missing',
    bool resolved = false, bool enabled = true}) => {
  'schema': 1, 'actor_id': notificationActor, 'report_id': notificationReport,
  'enforcement_enabled': enabled, 'effective_from': enabled ? '2026-10-01' : null,
  'resolved': resolved, 'items': resolved || !enabled ? [] : [
    {'company_id': notificationCompany, 'worker_id': notificationWorker,
      'work_date': '2026-10-25', 'site_id': notificationSite, 'route_assignment_id': null,
      'report_id': notificationReport, 'source_clock_in_id': notificationClockIn,
      'clock_out_id': notificationClockOut, 'registration_state': state,
      'blocking': !{'reporter_saved_waiting_supervisor','signed_projection_unverified'}.contains(state),
      'scope_fingerprint': 'a' * 32},
  ],
};
