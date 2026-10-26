/// Pure preflight model. This is not an authorization or a server write.
/// The server must independently validate session, signature, site membership,
/// token expiry and single-use consumption within the clock-in/out transaction.
enum QrAttendanceAction { clockIn, clockOut }

enum QrAttendanceDecision {
  ready,
  disabled,
  invalidToken,
  expired,
  wrongAction,
  wrongCompany,
  deviceUnavailable,
  alreadyWorking,
  missingClockIn,
  wrongClockIn,
  retryExistingReceipt,
  conflict,
}

class QrAttendanceTransition {
  const QrAttendanceTransition._();

  /// Trusted values here must come from server records, not QR contents.
  static QrAttendanceDecision evaluate({
    required bool enabled,
    required bool tokenValid,
    required DateTime serverNow,
    required DateTime expiresAt,
    required QrAttendanceAction action,
    required QrAttendanceAction tokenAction,
    required String tokenCompany,
    required String deviceCompany,
    required bool deviceActive,
    required bool deviceAuthorized,
    required String? activeClockInId,
    required String? tokenClockInId,
    required bool tokenConsumed,
    required bool requestMatchesReceipt,
  }) {
    if (!enabled) {
      return QrAttendanceDecision.disabled;
    }
    if (!tokenValid || tokenCompany.isEmpty || deviceCompany.isEmpty) {
      return QrAttendanceDecision.invalidToken;
    }
    if (tokenCompany != deviceCompany) {
      return QrAttendanceDecision.wrongCompany;
    }
    if (!deviceActive || !deviceAuthorized) {
      return QrAttendanceDecision.deviceUnavailable;
    }
    if (tokenAction != action) {
      return QrAttendanceDecision.wrongAction;
    }
    if (tokenConsumed) {
      return requestMatchesReceipt
          ? QrAttendanceDecision.retryExistingReceipt
          : QrAttendanceDecision.conflict;
    }
    if (!serverNow.isBefore(expiresAt)) {
      return QrAttendanceDecision.expired;
    }
    if (action == QrAttendanceAction.clockIn) {
      if (activeClockInId != null) {
        return QrAttendanceDecision.alreadyWorking;
      }
      if (tokenClockInId != null) {
        return QrAttendanceDecision.invalidToken;
      }
    } else {
      if (activeClockInId == null || tokenClockInId == null) {
        return QrAttendanceDecision.missingClockIn;
      }
      if (activeClockInId != tokenClockInId) {
        return QrAttendanceDecision.wrongClockIn;
      }
    }
    return QrAttendanceDecision.ready;
  }
}
