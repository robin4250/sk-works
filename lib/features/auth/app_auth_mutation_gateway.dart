import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'apple_session_navigation_binding.dart';

/// Serializes app-owned repository writes to an existing SDK client.
/// SDK deep links, OAuth callbacks, automatic refresh and storage remain outside
/// this boundary. It cannot prevent a transient SDK signedIn before logout.
class AppAuthMutationGateway {
  AppAuthMutationGateway._(this._client);
  static final _owners = Expando<AppAuthMutationGateway>();
  static AppAuthMutationGateway forClient(SupabaseClient client) =>
      _owners[client] ??= AppAuthMutationGateway._(client);
  final SupabaseClient _client;
  Completer<void>? _active;
  Future<void>? _logout;
  int _generation = 0;

  AppleSessionNavigationBinding? _binding(Session? session) =>
      AppleSessionNavigationBinding.fromSession(session);

  Future<T> _run<T>(Future<_Result<T>> Function(AppleSessionNavigationBinding? before) action,
      {bool requiresSession = false}) async {
    if (_active != null || _logout != null) {
      throw StateError('Authentication operation already in progress.');
    }
    final initialSession = _client.auth.currentSession;
    final before = _binding(initialSession);
    if (requiresSession && before == null) throw StateError('Authentication required.');
    final generation = _generation;
    final completion = Completer<void>();
    _active = completion;
    final events = <AuthState>[];
    var failed = false;
    _Result<T>? accepted;
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      if (events.length >= 32) { failed = true; } else { events.add(event); }
    }, onError: (Object _) { failed = true; }, onDone: () { failed = true; });
    void validate(_Result<T> result) {
      if (generation != _generation || failed ||
          _binding(_client.auth.currentSession) != result.expected) {
        throw StateError('Authentication changed before completion.');
      }
      for (final event in events) {
        final binding = _binding(event.session);
        final sameSessionRefresh = binding != null && event.event == AuthChangeEvent.tokenRefreshed &&
            (binding == before || binding == result.expected);
        final ownEvent = event.event == result.event &&
            identical(event.session, result.eventSession);
        if (!sameSessionRefresh && !ownEvent) {
          throw StateError('Authentication history changed before completion.');
        }
      }
    }
    try {
      // GoTrue replays its last AuthState to a new listener. Drain exactly the
      // captured session object before dispatch; never discard a live transition.
      // Pinned ReplaySubject schedules one microtask, not a timer.
      await Future<void>.value();
      if (generation != _generation || failed || events.length > 1 ||
          !identical(_client.auth.currentSession, initialSession) ||
          events.any((event) => !identical(event.session, initialSession) ||
              (event.event == AuthChangeEvent.signedOut && initialSession != null))) {
        throw StateError('Authentication changed before dispatch.');
      }
      events.clear();
      final result = await action(before);
      // The SDK publishes AuthState asynchronously after saving its session.
      await Future<void>.value();
      validate(result);
      accepted = result;
      return result.value;
    } finally {
      try { await subscription.cancel(); }
      finally { _active = null; completion.complete(); }
      // Cancellation itself can yield: logout intent must still win until this
      // Future exposes its result. Never restore the earlier SDK session.
      if (accepted != null) validate(accepted);
    }
  }

  Future<User?> signInWithPassword({String? email, String? phone, required String password}) =>
      _run((_) async {
        final response = await _client.auth.signInWithPassword(email: email, phone: phone, password: password);
        if (response.session == null) throw StateError('Sign-in did not establish a session.');
        return _Result(response.user, _binding(response.session),
            event: AuthChangeEvent.signedIn, eventSession: response.session);
      });

  Future<bool> signUp({required String phone, required String password, required Map<String, dynamic> data}) =>
      _run((before) async {
        final response = await _client.auth.signUp(phone: phone, password: password,
            channel: OtpChannel.sms, data: data);
        return _Result(response.session != null, response.session == null ? before : _binding(response.session),
            event: response.session == null ? null : AuthChangeEvent.signedIn, eventSession: response.session);
      });

  Future<void> verifySmsCode({required String phone, required String token}) =>
      _run<void>((before) async {
        final response = await _client.auth.verifyOTP(type: OtpType.sms, phone: phone, token: token);
        return _Result(null, response.session == null ? before : _binding(response.session),
            event: response.session == null ? null : AuthChangeEvent.signedIn, eventSession: response.session);
      });

  Future<void> updateUser(UserAttributes attributes) => _run<void>((before) async {
    await _client.auth.updateUser(attributes);
    return _Result(null, before, event: AuthChangeEvent.userUpdated,
        eventSession: _client.auth.currentSession);
  }, requiresSession: true);

  Future<void> verifyPhoneChange({required String phone, required String token}) =>
      _run<void>((before) async {
        final response = await _client.auth.verifyOTP(type: OtpType.phoneChange, phone: phone, token: token);
        final expected = response.session == null ? before : _binding(response.session);
        if (expected?.actorId != before?.actorId) {
          throw StateError('Phone verification changed account.');
        }
        return _Result(null, expected,
            event: response.session == null ? null : AuthChangeEvent.signedIn, eventSession: response.session);
      }, requiresSession: true);

  Future<void> signOut() {
    final existing = _logout;
    if (existing != null) return existing;
    // Invalidate pending callers immediately, before awaiting any SDK request.
    _generation++;
    final completion = Completer<void>();
    _logout = completion.future;
    final pending = _active?.future;
    unawaited(() async {
      try {
        if (pending != null) await pending;
        await _client.auth.signOut(); // Preserve the pinned SDK default logout scope (local).
        completion.complete();
      } catch (error, stack) { completion.completeError(error, stack); }
      finally { _logout = null; }
    }());
    return completion.future;
  }
}

class _Result<T> {
  const _Result(this.value, this.expected, {this.event, this.eventSession});
  final T value;
  final AuthChangeEvent? event;
  final Session? eventSession;
  final AppleSessionNavigationBinding? expected;
}
