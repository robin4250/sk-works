import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qr_attendance/qr_attendance_transition.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27);
  QrAttendanceDecision decide({bool enabled = true, bool valid = true,
      bool active = true, bool authorized = true, bool consumed = false,
      bool sameReceipt = false, String company = 'a', String deviceCompany = 'a',
      QrAttendanceAction action = QrAttendanceAction.clockIn,
      QrAttendanceAction tokenAction = QrAttendanceAction.clockIn,
      String? activeClockIn, String? tokenClockIn, DateTime? expires}) =>
    QrAttendanceTransition.evaluate(enabled: enabled, tokenValid: valid,
      serverNow: now, expiresAt: expires ?? now.add(const Duration(seconds: 30)),
      action: action, tokenAction: tokenAction, tokenCompany: company,
      deviceCompany: deviceCompany, deviceActive: active, deviceAuthorized: authorized,
      activeClockInId: activeClockIn, tokenClockInId: tokenClockIn,
      tokenConsumed: consumed, requestMatchesReceipt: sameReceipt);

  test('QR OFF rejects even a retry', () {
    expect(decide(enabled: false, consumed: true, sameReceipt: true), QrAttendanceDecision.disabled);
  });
  test('company, device, purpose and expiration are checked', () {
    expect(decide(deviceCompany: 'b'), QrAttendanceDecision.wrongCompany);
    expect(decide(active: false), QrAttendanceDecision.deviceUnavailable);
    expect(decide(authorized: false), QrAttendanceDecision.deviceUnavailable);
    expect(decide(tokenAction: QrAttendanceAction.clockOut), QrAttendanceDecision.wrongAction);
    expect(decide(expires: now), QrAttendanceDecision.expired);
  });
  test('checkout must use the active attendance source', () {
    expect(decide(action: QrAttendanceAction.clockOut, tokenAction: QrAttendanceAction.clockOut), QrAttendanceDecision.missingClockIn);
    expect(decide(action: QrAttendanceAction.clockOut, tokenAction: QrAttendanceAction.clockOut, activeClockIn: 'one', tokenClockIn: 'two'), QrAttendanceDecision.wrongClockIn);
    expect(decide(action: QrAttendanceAction.clockOut, tokenAction: QrAttendanceAction.clockOut, activeClockIn: 'one', tokenClockIn: 'one'), QrAttendanceDecision.ready);
    expect(decide(activeClockIn: 'one'), QrAttendanceDecision.alreadyWorking);
  });
  test('a consumed token only returns its matching receipt', () {
    expect(decide(consumed: true, sameReceipt: true, expires: now), QrAttendanceDecision.retryExistingReceipt);
    expect(decide(consumed: true), QrAttendanceDecision.conflict);
  });
}
