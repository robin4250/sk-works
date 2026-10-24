import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_report_gate.dart';

import 'attendance_unrecorded_punches_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final action in ['upsert', 'delete']) {
    test('successful management $action rechecks only the current actor scope', () async {
      final f = fixture.Fixture();
      await f.start();
      addTearDown(f.client.dispose);
      final gate = CheckoutReportGateController.instance;
      final activation = gate.activate(fixture.actor, () async {});
      addTearDown(() => gate.deactivate(fixture.actor, activation));
      final before = gate.revision;
      await f.repository.apply(action: action, workerIds: [fixture.worker],
        dates: [DateTime(2026, 10, 21)], mode: 'work', siteId: fixture.site,
        clockIn: '08:00', clockOut: '17:00');
      expect(gate.actorId, fixture.actor);
      expect(gate.revision, before + 1);
      expect(f.calls.where((request) => request.url.path.endsWith('/force_manage_attendance')), hasLength(1));
      // The affected worker differs from the actor. The request merely asks
      // the backend to read actor obligations; it never assigns this worker.
      expect(fixture.worker, isNot(fixture.actor));
    });
  }
  test('a write response cannot request a check for a different activated actor', () async {
    final f = fixture.Fixture();
    await f.start();
    addTearDown(f.client.dispose);
    final gate = CheckoutReportGateController.instance;
    const other = '99999999-9999-9999-9999-999999999999';
    final activation = gate.activate(other, () async {});
    addTearDown(() => gate.deactivate(other, activation));
    final before = gate.revision;
    await f.repository.apply(action: 'upsert', workerIds: [fixture.worker],
      dates: [DateTime(2026, 10, 21)], mode: 'work', siteId: fixture.site);
    expect(gate.actorId, other);
    expect(gate.revision, before);
  });
}
