/// Staged first-use policy. Not connected to AuthGate or deployed APIs.
/// These values are transport-boundary inputs, not authentication proofs.
enum FirstUseServerStatus { needsSetup, completed, unavailable }
enum FirstUseDecision { legacyUnchanged, initialSetup, continueSession, retry }
enum FirstUseAdditionalEvidence { serverVerifiedFactor, localBiometricOnly, none }

class FirstUseSession {
  const FirstUseSession({required this.actorId, required this.sessionId});
  final String actorId;
  final String sessionId;

  bool get valid => actorId.isNotEmpty && sessionId.isNotEmpty;
  bool matches(FirstUseSession other) =>
      actorId == other.actorId && sessionId == other.sessionId;
}

/// A correlated response from the future authenticated server endpoint.
/// completed MUST mean server-verified primary and independent additional
/// evidence, not a bool supplied by the local_auth plugin or user_metadata.
class FirstUseServerRecord {
  const FirstUseServerRecord({
    required this.session,
    required this.status,
    required this.primaryValidated,
    required this.additionalEvidence,
  });
  final FirstUseSession session;
  final FirstUseServerStatus status;
  final bool primaryValidated;
  final FirstUseAdditionalEvidence additionalEvidence;
}

class FirstUseAttempt {
  const FirstUseAttempt._(this.generation, this.session);
  final int generation;
  final FirstUseSession session;
}

/// An account's first-use completion is persistent server state. A new session
/// reads that state; this policy never infers completion from local storage,
/// creates credentials, changes company roles, or performs sign-out.
class FirstUseAuthPolicy {
  FirstUseAuthPolicy({this.enabled = defaultEnabled});

  static const bool defaultEnabled =
      bool.fromEnvironment('SKO_FIRST_USE_AUTH_V1', defaultValue: false);

  final bool enabled;
  int _generation = 0;
  FirstUseSession? _current;

  FirstUseAttempt begin(FirstUseSession session) {
    _current = session.valid ? session : null;
    return FirstUseAttempt._(++_generation, session);
  }

  FirstUseDecision evaluate(
    FirstUseAttempt attempt,
    FirstUseServerRecord? record,
  ) {
    if (!enabled) return FirstUseDecision.legacyUnchanged;
    final current = _current;
    if (current == null ||
        attempt.generation != _generation ||
        !current.matches(attempt.session) ||
        record == null ||
        !current.matches(record.session) ||
        !record.primaryValidated) {
      return FirstUseDecision.retry;
    }
    return switch (record.status) {
      FirstUseServerStatus.unavailable => FirstUseDecision.retry,
      FirstUseServerStatus.needsSetup => FirstUseDecision.initialSetup,
      FirstUseServerStatus.completed =>
        record.additionalEvidence ==
                FirstUseAdditionalEvidence.serverVerifiedFactor
            ? FirstUseDecision.continueSession
            : FirstUseDecision.retry,
    };
  }

  /// Capture the session being logged out BEFORE awaiting the SDK call.
  /// A delayed logout for session A must not erase an already active session B.
  void invalidateSession(FirstUseSession capturedSession) {
    if (_current?.matches(capturedSession) != true) return;
    _current = null;
    _generation++;
  }

  /// Local Face/Touch success deliberately cannot mark first-use complete.
  bool get canCompleteFromLocalBiometric => false;
}
