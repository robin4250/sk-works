import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'apple_session_navigation_binding.dart';
import 'app_auth_logout_persistence.dart';
import 'sdk_session_replay_baseline.dart';

/// Serializes app-owned repository writes to an existing SDK client.
/// SDK deep links, OAuth callbacks, automatic refresh and storage remain outside
/// this boundary. It cannot prevent a transient SDK signedIn before logout.
enum AppLogoutQuarantineState { clear, pending, failed }

/// Read-only, in-memory UI signal. Contains no session or credential values.
abstract interface class AppLogoutQuarantineSignal {
  AppLogoutQuarantineState get state;
  Stream<AppLogoutQuarantineState> get changes;
}

class _LogoutSignal implements AppLogoutQuarantineSignal {
  AppLogoutQuarantineState _state = AppLogoutQuarantineState.clear;
  final _changes = StreamController<AppLogoutQuarantineState>.broadcast(sync: true);
  @override
  AppLogoutQuarantineState get state => _state;
  @override
  Stream<AppLogoutQuarantineState> get changes => _changes.stream;
  bool _notifying = false;
  bool _queued = false;
  void _set(AppLogoutQuarantineState value) {
    if (_state == value) return;
    _state = value;
    if (_notifying) {
      if (!_queued) {
        _queued = true;
        scheduleMicrotask(() { _queued = false; _emit(); });
      }
      return;
    }
    _emit();
  }
  void _emit() {
    _notifying = true;
    try { _changes.add(_state); } finally { _notifying = false; }
  }
}

/// Exclusive inspection of the captured existing SDK session. Contains no
/// credentials and never writes/adopts a session. Logout may retire it at once.
abstract interface class AppAuthSessionInspection {
  bool get isCurrent;
  Future<void> get invalidated;
  void release();
}

class _SessionInspection implements AppAuthSessionInspection {
  _SessionInspection(this._current, this._release);
  bool Function()? _current;
  void Function()? _release;
  final _invalidated = Completer<void>();
  @override
  bool get isCurrent {
    if (_current?.call() == true) return true;
    release();
    return false;
  }
  @override
  Future<void> get invalidated => _invalidated.future;
  @override
  void release() {
    final release = _release;
    _current = null;
    _release = null;
    release?.call();
    if (!_invalidated.isCompleted) _invalidated.complete();
  }
}

class AppAuthMutationGateway {
  AppAuthMutationGateway._(this._client) {
    final baseline = SdkSessionReplayBaseline(_client.auth.currentSession);
    _externalHistory = _client.auth.onAuthStateChange.listen((event) {
      // A recovered initialSession may be a distinct, byte-equivalent SDK
      // object. Every subsequent live event still advances the revision.
      final cached = baseline.consume(event, _client.auth.currentSession);
      if (!cached) {
        _externalRevision++;
        _inspection?.release();
      }
    }, onError: (Object _) => _closeExternalHistory(), onDone: _closeExternalHistory);
    _externalReady = Future<void>.value().then((_) { baseline.close(); });
  }
  StreamSubscription<AuthState>? _externalHistory;
  late final Future<void> _externalReady;
  int _externalRevision = 0;
  bool _externalClosed = false;
  void _closeExternalHistory() {
    _externalClosed = true;
    _externalRevision++;
    _inspection?.release();
    final subscription = _externalHistory;
    _externalHistory = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) { _externalClosed = true; }));
    }
  }
  static final _owners = Expando<AppAuthMutationGateway>();
  static AppAuthMutationGateway forClient(SupabaseClient client) =>
      _owners[client] ??= AppAuthMutationGateway._(client);
  static AppAuthMutationGateway bindPersistence(SupabaseClient client, AppLogoutPersistenceFence persistence) {
    final owner = forClient(client);
    if (owner._active != null || owner._logout != null ||
        (owner._persistence != null && !identical(owner._persistence, persistence))) {
      throw StateError('Auth persistence owner cannot be replaced.');
    }
    owner._persistence = persistence;
    if (persistence.blocked) owner._quarantine._set(AppLogoutQuarantineState.failed);
    return owner;
  }
  final SupabaseClient _client;
  AppLogoutPersistenceFence? _persistence;
  Completer<void>? _active;
  _SessionInspection? _inspection;
  Future<void>? _logout;
  int _generation = 0;
  final _quarantine = _LogoutSignal();
  AppLogoutQuarantineSignal get logoutQuarantine => _quarantine;

  /// Read-only external flow admission, not SDK mutation ownership/CAS.
  /// Stream failure closes this view until a new client is created.
  int? get _externalFlowEpoch => !_externalClosed && _active == null && _logout == null &&
      _quarantine.state == AppLogoutQuarantineState.clear ? _externalRevision : null;
  Future<int?> externalFlowAdmission() async {
    final initial = _client.auth.currentSession;
    final revision = _externalRevision;
    await _externalReady;
    if (!identical(initial, _client.auth.currentSession) || revision != _externalRevision) return null;
    return _externalFlowEpoch;
  }
  bool isExternalFlowCurrent(int epoch) => _externalFlowEpoch == epoch;

  /// Reserve app-owned Auth writes during isolated successor inspection.
  /// Existing SDK callbacks/refresh are observed rather than owned: any live
  /// event retires this lease. This is not global SDK compare-and-swap/adoption.
  Future<AppAuthSessionInspection> inspectCurrentSession() async {
    if (_active != null || _logout != null || _externalClosed ||
        _quarantine.state != AppLogoutQuarantineState.clear) {
      throw StateError('Authentication operation already in progress.');
    }
    final captured = _client.auth.currentSession;
    if (captured == null || captured.isExpired || _binding(captured) == null) {
      throw StateError('Authentication required.');
    }
    final generation = _generation, revision = _externalRevision;
    final completion = Completer<void>();
    late final _SessionInspection inspection;
    inspection = _SessionInspection(() =>
      identical(_inspection, inspection) && identical(_active, completion) &&
      generation == _generation && revision == _externalRevision && !_externalClosed &&
      _logout == null && _quarantine.state == AppLogoutQuarantineState.clear &&
      identical(captured, _client.auth.currentSession) && !captured.isExpired,
      () {
        if (identical(_inspection, inspection)) _inspection = null;
        if (identical(_active, completion)) _active = null;
        if (!completion.isCompleted) completion.complete();
      });
    _active = completion;
    _inspection = inspection;
    await _externalReady;
    if (!inspection.isCurrent) {
      throw StateError('Authentication changed before inspection.');
    }
    return inspection;
  }

  AppleSessionNavigationBinding? _binding(Session? session) =>
      AppleSessionNavigationBinding.fromSession(session);

  Future<T> _run<T>(Future<_Result<T>> Function(AppleSessionNavigationBinding? before) action,
      {bool requiresSession = false}) async {
    if (_active != null || _logout != null ||
        _quarantine.state != AppLogoutQuarantineState.clear) {
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

  Future<User?> signInWithPassword({String? email, String? phone, required String password, String? captchaToken}) =>
      _run((_) async {
        final response = await _client.auth.signInWithPassword(email: email, phone: phone, password: password, captchaToken: captchaToken);
        if (response.session == null) throw StateError('Sign-in did not establish a session.');
        return _Result(response.user, _binding(response.session),
            event: AuthChangeEvent.signedIn, eventSession: response.session);
      });

  Future<bool> signUp({required String phone, required String password, required Map<String, dynamic> data, String? captchaToken}) =>
      _run((before) async {
        final response = await _client.auth.signUp(phone: phone, password: password,
            channel: OtpChannel.sms, data: data, captchaToken: captchaToken);
        return _Result(response.session != null, response.session == null ? before : _binding(response.session),
            event: response.session == null ? null : AuthChangeEvent.signedIn, eventSession: response.session);
      });

  Future<void> verifySmsCode({required String phone, required String token, String? captchaToken}) =>
      _run<void>((before) async {
        final response = await _client.auth.verifyOTP(type: OtpType.sms, phone: phone, token: token, captchaToken: captchaToken);
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
    // Invalidate pending callers and quarantine UI before awaiting any SDK work.
    _generation++;
    _externalRevision++;
    _inspection?.release();
    final completion = Completer<void>();
    _logout = completion.future;
    _quarantine._set(AppLogoutQuarantineState.pending);
    final pending = _active?.future;
    unawaited(() async {
      StreamSubscription<AuthState>? confirmation;
      var released = false;
      try {
        await _persistence?.persistIntent();
        if (pending != null) await pending;
        final events = <AuthState>[];
        var failed = false;
        confirmation = _client.auth.onAuthStateChange.listen((event) {
          if (events.length >= 32) { failed = true; } else { events.add(event); }
        }, onError: (Object _) { failed = true; }, onDone: () { failed = true; });
        // Ignore only events preceding this SDK logout invocation. UI stays
        // quarantined throughout; a cached signedOut is never confirmation.
        await Future<void>.value();
        events.clear();
        failed = false;
        await _client.auth.signOut(); // Preserve pinned SDK default local scope.
        await Future<void>.value();
        bool confirmed() => !failed && _client.auth.currentSession == null &&
            events.any((event) => event.event == AuthChangeEvent.signedOut && event.session == null) &&
            !events.any((event) => event.session != null);
        if (!confirmed()) throw StateError('SDK logout could not be confirmed.');
        await _persistence?.confirmLocalRemoval();
        await _persistence?.releaseFence(confirmed);
        released = _persistence != null;
        await confirmation.cancel();
        confirmation = null;
        if (!confirmed()) throw StateError('SDK logout could not be confirmed.');
        // No await between confirmation and releasing the in-memory UI fence.
        _logout = null;
        _quarantine._set(AppLogoutQuarantineState.clear);
        completion.complete();
      } catch (error, stack) {
        if (released) {
          try { await _persistence?.persistIntent(); } catch (_) { /* UI remains blocked. */ }
        }
        _logout = null;
        _quarantine._set(AppLogoutQuarantineState.failed);
        completion.completeError(error, stack);
      } finally {
        try { await confirmation?.cancel(); } catch (_) { /* Already quarantined. */ }
      }
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
