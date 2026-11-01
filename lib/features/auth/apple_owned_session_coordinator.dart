part of 'apple_successor_client_preparation.dart';

enum AppleOwnedSessionPhase {
  disabled, signedOut, signingIn, active, preparing, adopting,
  adoptedAwaitingAck, adopted, signingOut, fenced, disposed,
}

/// OFF candidate which owns a NEW in-memory SDK client, never the application's
/// existing global client. No SDK/client/session/refresh-token getter escapes.
/// Integration with existing Google/Face ID/deep-link/persistence is incomplete.
class AppleOwnedSessionCoordinator with WidgetsBindingObserver {
  AppleOwnedSessionCoordinator({required this.projectUrl, required this.publicKey,
    this.enabled = false,
    this.operationTimeout = const Duration(seconds: 45),
    this.ackTimeout = const Duration(seconds: 10),
    Future<Map<String, dynamic>> Function(String requestId, String bearer)? acknowledgePossession,
    http.Client Function()? applicationHttpFactory,
    http.Client Function()? isolatedHttpFactory,
    Stream<AuthState>? additionalAuthHistory,
  }) : _acknowledge = acknowledgePossession,
       _applicationHttpFactory = applicationHttpFactory ?? http.Client.new,
       _isolatedHttpFactory = isolatedHttpFactory ?? http.Client.new,
       _additionalAuthHistory = additionalAuthHistory,
       _phase = enabled ? AppleOwnedSessionPhase.signedOut : AppleOwnedSessionPhase.disabled;

  final String projectUrl, publicKey;
  final bool enabled;
  final Duration operationTimeout, ackTimeout;
  final Future<Map<String, dynamic>> Function(String, String)? _acknowledge;
  final http.Client Function() _applicationHttpFactory, _isolatedHttpFactory;
  final Stream<AuthState>? _additionalAuthHistory;
  AppleOwnedSessionPhase _phase;
  SupabaseClient? _client;
  http.Client? _applicationHttp, _isolatedHttp;
  StreamSubscription<AuthState>? _authSubscription, _extraSubscription;
  AppleSuccessorClientPreparation? _preparation;
  AppleSuccessorClientPreparation? _evidence;
  Object? _lease;
  Completer<void>? _leaseCancellation;
  StreamController<AuthState>? _preparationHistory;
  int _epoch = 0;
  bool _collectLoginEvents = false, _enrollmentAttempted = false;
  final List<AuthState> _loginEvents = [];
  String? _actor, _token, _pendingRequest, _pendingSid;
  String? _expectedGoogle, _expectedApple, _expectedMemberships;

  static StateError _failure() => StateError('ログイン切替の状態を確認してください。自動再送や元の資格情報への復元は行いません。');
  AppleOwnedSessionPhase get phase => _phase;
  bool get _retired => _phase == AppleOwnedSessionPhase.fenced || _phase == AppleOwnedSessionPhase.disposed;
  bool get _stable => _lease == null && [AppleOwnedSessionPhase.active,
    AppleOwnedSessionPhase.adoptedAwaitingAck, AppleOwnedSessionPhase.adopted].contains(_phase);
  String? get actorId {
    if (!_stable) { return null; }
    if (!_currentMatches()) { _fence(); return null; }
    return _actor;
  }
  bool get ownedSessionAdopted => actorId != null &&
    (_phase == AppleOwnedSessionPhase.adopted || _phase == AppleOwnedSessionPhase.adoptedAwaitingAck);
  bool get possessionAcknowledged => actorId != null && _phase == AppleOwnedSessionPhase.adopted;

  bool _currentMatches() {
    final session = _client?.auth.currentSession;
    return session != null && !session.isExpired && session.user.id == _actor && session.accessToken == _token;
  }
  bool _eventMatches(AuthState event) =>
    [AuthChangeEvent.initialSession, AuthChangeEvent.signedIn].contains(event.event) &&
    event.session?.user.id == _actor && event.session?.accessToken == _token;
  String _appleBinding(User user) {
    final rows = (user.identities ?? <UserIdentity>[])
      .where((identity) => identity.provider == 'apple' && identity.userId == user.id).toList();
    if (rows.length != 1 || rows.single.identityData?['sub'] is! String) { throw _failure(); }
    final row = rows.single;
    return jsonEncode([row.id, row.identityId, row.userId, row.identityData!['sub']]);
  }
  void _observe(AuthState event) {
    if (_retired) { return; }
    _preparationHistory?.add(event);
    if (_collectLoginEvents) {
      if (_loginEvents.length >= 16) { _fence(); } else { _loginEvents.add(event); }
      return;
    }
    if (_phase == AppleOwnedSessionPhase.signingOut && event.event == AuthChangeEvent.signedOut && event.session == null) { return; }
    if (!_eventMatches(event)) { _fence(); }
  }
  void _guard() {
    final url = Uri.tryParse(projectUrl);
    if (!enabled || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || _retired ||
        url == null || url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty ||
        url.hasQuery || url.hasFragment || (url.path.isNotEmpty && url.path != '/') || publicKey.isEmpty ||
        operationTimeout <= Duration.zero || operationTimeout > const Duration(minutes: 3) ||
        ackTimeout <= Duration.zero || ackTimeout > const Duration(seconds: 30)) { throw _failure(); }
  }
  SupabaseClient _owned() {
    _guard();
    if (_client != null) { return _client!; }
    _applicationHttp = _applicationHttpFactory();
    final client = SupabaseClient(projectUrl, publicKey, httpClient: _applicationHttp,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    _client = client;
    _authSubscription = client.auth.onAuthStateChange.listen(_observe,
      onError: (Object _) => _fence(), onDone: _fence);
    _extraSubscription = _additionalAuthHistory?.listen(_observe,
      onError: (Object _) => _fence(), onDone: _fence);
    WidgetsBinding.instance.addObserver(this);
    return client;
  }
  Object _acquire() {
    _guard();
    if (_lease != null) { throw _failure(); }
    final lease = Object(); _lease = lease; _leaseCancellation = Completer<void>(); _epoch++; return lease;
  }
  Future<T> _race<T>(Future<T> work) => Future.any<T>([work,
    _leaseCancellation!.future.then<T>((_) => throw _failure())]).timeout(operationTimeout);
  void _check(Object lease, int epoch, {bool session = true}) {
    if (_retired || !identical(_lease, lease) || _epoch != epoch || session && !_currentMatches()) { throw _failure(); }
  }
  void _release(Object lease) {
    if (identical(_lease, lease)) { _lease = null; _leaseCancellation = null; }
  }
  void _fence() {
    if (_retired) { return; }
    _phase = AppleOwnedSessionPhase.fenced; _epoch++;
    final cancelled = _leaseCancellation;
    if (cancelled != null && !cancelled.isCompleted) { cancelled.complete(); }
    _actor = _token = _pendingRequest = _pendingSid = null;
    _expectedGoogle = _expectedApple = _expectedMemberships = null; _evidence = null;
    _collectLoginEvents = false; _loginEvents.clear();
    _preparation?.invalidate();
    _applicationHttp?.close(); _isolatedHttp?.close();
    final client = _client;
    if (client != null) { unawaited(client.dispose().catchError((Object _) {})); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lease != null && (state == AppLifecycleState.paused || state == AppLifecycleState.detached)) { _fence(); }
  }

  /// Interactive bootstrap for this NEW candidate client only. It does not
  /// replace/migrate an existing app session or bypass Google enrollment checks.
  Future<void> signInWithPassword({required String email, required String password, String? captchaToken}) async {
    _guard();
    if (_phase != AppleOwnedSessionPhase.signedOut || _lease != null) { throw _failure(); }
    final lease = _acquire(), epoch = _epoch;
    _phase = AppleOwnedSessionPhase.signingIn; _collectLoginEvents = true; _loginEvents.clear();
    try {
      final client = _owned();
      final response = await _race(client.auth.signInWithPassword(email: email, password: password, captchaToken: captchaToken));
      _check(lease, epoch, session: false);
      final session = response.session;
      if (session == null || session.isExpired || response.user?.id != session.user.id) { throw _failure(); }
      _actor = session.user.id; _token = session.accessToken;
      await Future<void>.delayed(Duration.zero);
      _check(lease, epoch);
      if (_loginEvents.any((event) => !_eventMatches(event))) { throw _failure(); }
      _collectLoginEvents = false; _loginEvents.clear(); _phase = AppleOwnedSessionPhase.active;
    } catch (_) { _fence(); throw _failure(); }
    finally { _release(lease); }
  }

  Future<void> enrollAndAdopt({required String requestId, required AppleSuccessorHttpsDelivery delivery,
    required String password, required String idToken, required String rawNonce}) async {
    _guard();
    if (_phase != AppleOwnedSessionPhase.active || _enrollmentAttempted || _acknowledge == null) { throw _failure(); }
    final lease = _acquire(), epoch = _epoch;
    _enrollmentAttempted = true; _phase = AppleOwnedSessionPhase.preparing;
    var adopted = false;
    Future<void> work() async {
      final client = _owned(); _check(lease, epoch);
      _preparationHistory = StreamController<AuthState>.broadcast();
      final preparation = AppleSuccessorClientPreparation(client, projectUrl: projectUrl, publicKey: publicKey,
        enabled: true, authChanges: _preparationHistory!.stream, isolatedClientFactory: () {
          _isolatedHttp = _isolatedHttpFactory();
          return SupabaseClient(projectUrl, publicKey, httpClient: _isolatedHttp,
            authOptions: const AuthClientOptions(autoRefreshToken: false));
        });
      _preparation = preparation;
      await preparation.prepareFromHttps(requestId: requestId, delivery: delivery,
        password: password, idToken: idToken, rawNonce: rawNonce);
      _check(lease, epoch);
      if (!preparation.ready) { throw _failure(); }
      final successor = preparation._preparedClient!.auth.currentSession!;
      final actor = successor.user.id, access = successor.accessToken, refresh = successor.refreshToken!;
      final sid = preparation._sessionId(access, actor), google = preparation._google(successor.user);
      final apple = _appleBinding(successor.user);
      final memberships = await preparation._memberships(preparation._preparedClient!, actor, access);
      _check(lease, epoch);
      if (!preparation.ready) { throw _failure(); }
      // Release the preparation's original-token watcher before this owned
      // SDK's intentional transition. The coordinator watcher remains active.
      await preparation.dispose(); _preparation = null; _isolatedHttp?.close(); _isolatedHttp = null;
      await Future<void>.delayed(Duration.zero); _check(lease, epoch);
      _phase = AppleOwnedSessionPhase.adopting;
      _actor = actor; _token = access;
      final result = await client.auth.setSession(refresh, accessToken: access);
      await Future<void>.delayed(Duration.zero); _check(lease, epoch);
      if (result.session?.accessToken != access || result.session?.refreshToken != refresh ||
          result.user?.id != actor || preparation._google(result.user!) != google ||
          _appleBinding(result.user!) != apple ||
          preparation._sessionId(client.auth.currentSession!.accessToken, actor) != sid ||
          await preparation._memberships(client, actor, access) != memberships) { throw _failure(); }
      await Future<void>.delayed(Duration.zero); _check(lease, epoch);
      adopted = true; _pendingRequest = requestId; _pendingSid = sid;
      _evidence = preparation; _expectedGoogle = google; _expectedApple = apple; _expectedMemberships = memberships;
      _phase = AppleOwnedSessionPhase.adoptedAwaitingAck;
      await _ack(lease, epoch);
    }
    try { await _race(work()); }
    catch (_) {
      if (!adopted || _retired || !_currentMatches()) { _fence(); }
      else { _phase = AppleOwnedSessionPhase.adoptedAwaitingAck; }
      throw _failure();
    } finally {
      final preparation = _preparation; _preparation = null;
      if (preparation != null) { await preparation.dispose(); }
      final history = _preparationHistory; _preparationHistory = null;
      if (history != null) { await history.close(); }
      _isolatedHttp?.close(); _isolatedHttp = null; _release(lease);
    }
  }

  Future<void> _ack(Object lease, int epoch) async {
    _check(lease, epoch);
    final request = _pendingRequest, sid = _pendingSid, token = _token, actor = _actor, evidence = _evidence;
    final acknowledge = _acknowledge;
    if (request == null || sid == null || token == null || actor == null || evidence == null || acknowledge == null) { throw _failure(); }
    try {
      final verified = await _client!.auth.getUser(token).timeout(ackTimeout);
      _check(lease, epoch);
      if (verified.user?.id != actor || evidence._sessionId(token, actor) != sid ||
          evidence._google(verified.user!) != _expectedGoogle || _appleBinding(verified.user!) != _expectedApple ||
          await evidence._memberships(_client!, actor, token) != _expectedMemberships) { throw _failure(); }
      _check(lease, epoch);
    } catch (_) { _fence(); throw _failure(); }
    final raw = Map<String, dynamic>.from(await acknowledge(request, token).timeout(ackTimeout));
    await Future<void>.delayed(Duration.zero); _check(lease, epoch);
    const fields = {'schema', 'request_id', 'status', 'retry_allowed', 'application_adoption_confirmed'};
    if (raw.length != fields.length || raw.keys.any((key) => !fields.contains(key)) || raw['schema'] != 1 ||
        raw['request_id'] != request || raw['status'] != 'successor_possession_recorded' ||
        raw['retry_allowed'] != false || raw['application_adoption_confirmed'] != false) { throw _failure(); }
    _pendingRequest = _pendingSid = null; _phase = AppleOwnedSessionPhase.adopted;
  }
  /// Repeats only the idempotent possession ACK. Never calls enrollment/setSession.
  Future<void> retryPossessionAck() async {
    _guard();
    if (_phase != AppleOwnedSessionPhase.adoptedAwaitingAck) { throw _failure(); }
    final lease = _acquire(), epoch = _epoch;
    try { await _race(_ack(lease, epoch)); }
    catch (_) { if (!_currentMatches()) { _fence(); } throw _failure(); }
    finally { _release(lease); }
  }

  Future<void> signOut() async {
    _guard();
    if (_lease != null) { _fence(); throw _failure(); }
    final lease = _acquire(), epoch = _epoch;
    _phase = AppleOwnedSessionPhase.signingOut;
    try {
      await _race(_owned().auth.signOut(scope: SignOutScope.local));
      await Future<void>.delayed(Duration.zero); _check(lease, epoch, session: false);
      if (_client!.auth.currentSession != null) { throw _failure(); }
      _actor = _token = _pendingRequest = _pendingSid = null; _phase = AppleOwnedSessionPhase.signedOut;
      _expectedGoogle = _expectedApple = _expectedMemberships = null; _evidence = null;
    } catch (_) { _fence(); throw _failure(); }
    finally { _release(lease); }
  }
  Future<void> dispose() async {
    if (_phase == AppleOwnedSessionPhase.disposed) { return; }
    _fence(); _phase = AppleOwnedSessionPhase.disposed;
    WidgetsBinding.instance.removeObserver(this);
    await _authSubscription?.cancel(); await _extraSubscription?.cancel();
    _authSubscription = _extraSubscription = null;
  }
}
