import 'package:flutter_test/flutter_test.dart';
import '../lib/features/auth/first_use_auth_policy.dart';

void main() {
  const a = FirstUseSession(actorId: 'actor-a', sessionId: 'session-a');
  const b = FirstUseSession(actorId: 'actor-b', sessionId: 'session-b');
  const a2 = FirstUseSession(actorId: 'actor-a', sessionId: 'session-a2');
  FirstUseServerRecord record(
    FirstUseSession session, {
    FirstUseServerStatus status = FirstUseServerStatus.completed,
    bool primary = true,
    FirstUseAdditionalEvidence additional =
        FirstUseAdditionalEvidence.serverVerifiedFactor,
  }) => FirstUseServerRecord(session: session, status: status,
      primaryValidated: primary, additionalEvidence: additional);

  test('default OFF preserves existing entry with unavailable APIs', () {
    final policy = FirstUseAuthPolicy();
    expect(FirstUseAuthPolicy.defaultEnabled, isFalse);
    expect(policy.evaluate(policy.begin(a), null),
        FirstUseDecision.legacyUnchanged);
  });

  test('first use needs setup, without requiring two devices', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    expect(policy.evaluate(policy.begin(a),
        record(a, status: FirstUseServerStatus.needsSetup)),
        FirstUseDecision.initialSetup);
  });

  test('confirmed completed account continues after normal restart', () {
    final original = FirstUseAuthPolicy(enabled: true);
    expect(original.evaluate(original.begin(a), record(a)),
        FirstUseDecision.continueSession);
    final restarted = FirstUseAuthPolicy(enabled: true);
    expect(restarted.evaluate(restarted.begin(a), record(a)),
        FirstUseDecision.continueSession);
  });

  test('new session reads existing account completion, no second setup', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    expect(policy.evaluate(policy.begin(a2), record(a2)),
        FirstUseDecision.continueSession);
  });

  test('local Face or Touch alone never becomes server MFA proof', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    final attempt = policy.begin(a);
    expect(policy.canCompleteFromLocalBiometric, isFalse);
    for (final evidence in [FirstUseAdditionalEvidence.localBiometricOnly,
      FirstUseAdditionalEvidence.none]) {
      expect(policy.evaluate(attempt, record(a, additional: evidence)),
          FirstUseDecision.retry);
    }
  });

  test('missing primary confirmation and unavailable records cannot complete', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    final attempt = policy.begin(a);
    expect(policy.evaluate(attempt, record(a, primary: false)),
        FirstUseDecision.retry);
    expect(policy.evaluate(attempt, record(a,
        status: FirstUseServerStatus.unavailable)), FirstUseDecision.retry);
    expect(policy.evaluate(attempt, null), FirstUseDecision.retry);
  });

  test('actor swap rejects old response', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    final old = policy.begin(a);
    final current = policy.begin(b);
    expect(policy.evaluate(old, record(a)), FirstUseDecision.retry);
    expect(policy.evaluate(current, record(a)), FirstUseDecision.retry);
    expect(policy.evaluate(current, record(b)),
        FirstUseDecision.continueSession);
  });

  test('same actor changed session rejects previous session evidence', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    final old = policy.begin(a);
    final current = policy.begin(a2);
    expect(policy.evaluate(old, record(a)), FirstUseDecision.retry);
    expect(policy.evaluate(current, record(a)), FirstUseDecision.retry);
    expect(policy.evaluate(current, record(a2)),
        FirstUseDecision.continueSession);
  });

  test('late logout A cannot invalidate active B or same actor new session', () {
    for (final next in [b, a2]) {
      final policy = FirstUseAuthPolicy(enabled: true);
      policy.begin(a);
      final attempt = policy.begin(next);
      policy.invalidateSession(a);
      expect(policy.evaluate(attempt, record(next)),
          FirstUseDecision.continueSession);
    }
  });

  test('logout rejects in-flight completion and same session earlier read', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    final old = policy.begin(a);
    policy.invalidateSession(a);
    expect(policy.evaluate(old, record(a)), FirstUseDecision.retry);
    final current = policy.begin(a);
    expect(policy.evaluate(old, record(a)), FirstUseDecision.retry);
    expect(policy.evaluate(current, record(a)),
        FirstUseDecision.continueSession);
  });

  test('local evidence loss does not erase server completion or auto reissue', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    final attempt = policy.begin(a);
    expect(policy.evaluate(attempt, null), FirstUseDecision.retry);
    expect(policy.evaluate(attempt, record(a)),
        FirstUseDecision.continueSession);
  });

  test('unsupported additional factor is pending, not a new account', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    expect(policy.evaluate(policy.begin(a),
        record(a, additional: FirstUseAdditionalEvidence.none)),
        FirstUseDecision.retry);
  });

  test('empty identity cannot become authenticated completion', () {
    final policy = FirstUseAuthPolicy(enabled: true);
    const invalid = FirstUseSession(actorId: '', sessionId: 'session');
    expect(policy.evaluate(policy.begin(invalid), record(invalid)),
        FirstUseDecision.retry);
  });
}
