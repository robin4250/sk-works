import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/supabase_backend.dart';
import '../auth/secure_onboarding_repository.dart';
import 'master_device_repository.dart';
import 'master_device_platform.dart';
import 'master_password_protected_page.dart';
import 'master_password_entry_repository.dart';
import 'master_emergency_recovery_page.dart';
import 'master_step_up_policy.dart';

class MasterProtectedPage extends StatefulWidget {
  const MasterProtectedPage({
    super.key,
    required this.title,
    required this.child,
    this.dedicatedMode = const bool.fromEnvironment('SKO_MASTER_PASSWORD_V1', defaultValue: false),
    this.dedicatedAccess,
    this.legacyDeviceRepository,
    this.legacyAuthRepository,
    this.legacySessionToken,
    this.legacyChanges,
  });

  final String title;
  final Widget child;
  final bool dedicatedMode;
  final MasterPasswordEntryAccess? dedicatedAccess;
  final MasterDeviceRepository? legacyDeviceRepository;
  final SecureOnboardingRepository? legacyAuthRepository;
  final String? Function()? legacySessionToken;
  final Stream<void>? legacyChanges;

  @override
  State<MasterProtectedPage> createState() => _MasterProtectedPageState();
}

class _MasterProtectedPageState extends State<MasterProtectedPage>
    with WidgetsBindingObserver {
  late final MasterDeviceRepository? _deviceRepository;
  late final SecureOnboardingRepository? _authRepository;
  final _localAuth = LocalAuthentication();
  final _password = TextEditingController();

  Timer? _expiryTimer;
  String? _deviceKey;
  bool _loading = true;
  bool _busy = false;
  bool _trustedDevice = false;
  bool _canBootstrap = false;
  bool _biometricAvailable = false;
  bool _secondaryConfigured = false;
  bool _unlocked = false;
  String? _error;
  String? _loadedActor;
  String? _loadedToken;
  StreamSubscription<void>? _authChanges;
  int _generation = 0;
  bool _nativePrompt = false;
  Completer<bool>? _resume;
  VoidCallback? _clearCaptured;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  String? get _currentToken => widget.legacySessionToken != null
      ? widget.legacySessionToken!()
      : SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentSession?.accessToken : null;

  bool _same(int generation, String actor, String token, {bool nativeInactive = false}) =>
      mounted && generation == _generation && _deviceRepository?.currentUserId == actor &&
      _authRepository?.currentUser?.id == actor && _currentToken == token &&
      ModalRoute.of(context)?.isCurrent == true &&
      (_lifecycle == AppLifecycleState.resumed || nativeInactive && _nativePrompt && _lifecycle == AppLifecycleState.inactive);

  @override
  void initState() {
    super.initState();
    _deviceRepository = widget.legacyDeviceRepository ?? MasterDeviceRepository.maybeCreate();
    _authRepository = widget.legacyAuthRepository ?? SecureOnboardingRepository.maybeCreate();
    if (widget.dedicatedMode) return;
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    final changes = widget.legacyChanges ?? (SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.onAuthStateChange.map((_) {}) : null);
    _authChanges = changes?.listen((_) {
      if (_loadedActor != null && (_deviceRepository?.currentUserId != _loadedActor || _currentToken != _loadedToken)) _lock();
    }, onError: (Object _) => _lock());
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.dedicatedMode && !_unlocked && (_busy || _loading) && ModalRoute.of(context)?.isCurrent == false) _lock();
  }

  Future<void> _load() async {
    final deviceRepository = _deviceRepository;
    final authRepository = _authRepository;
    final userId = deviceRepository?.currentUserId;
    final token = _currentToken;
    if (deviceRepository == null || authRepository == null || userId == null || token == null) {
      setState(() { _loading = false; _error = 'Master認証を利用できません。'; });
      return;
    }
    final generation = ++_generation;
    try {
      if (!await deviceRepository.isMasterAdmin(accessToken: token)) throw StateError('Master管理者権限が必要です。');
      if (!_same(generation, userId, token)) return;
      final prefs = await SharedPreferences.getInstance();
      if (!_same(generation, userId, token)) return;
      var deviceKey = prefs.getString('sko_master_device_key_$userId');
      if (deviceKey == null || deviceKey.length < 32) {
        deviceKey = _newDeviceKey();
        await prefs.setString('sko_master_device_key_$userId', deviceKey);
        if (!_same(generation, userId, token)) return;
      }
      final status = await deviceRepository.currentDeviceStatus(deviceKey, accessToken: token);
      if (!_same(generation, userId, token)) return;
      final secondaryConfigured = await authRepository.secondaryPasswordConfigured(accessToken: token);
      if (!_same(generation, userId, token)) return;
      final supported = await _localAuth.isDeviceSupported();
      if (!_same(generation, userId, token)) return;
      final biometricAvailable = supported && await _localAuth.canCheckBiometrics;
      if (!_same(generation, userId, token)) return;
      setState(() {
        _deviceKey = deviceKey;
        _trustedDevice = status['trusted'] == true;
        _canBootstrap = status['can_bootstrap'] == true;
        _secondaryConfigured = secondaryConfigured;
        _biometricAvailable = biometricAvailable;
        _loadedActor = userId;
        _loadedToken = token;
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() { _loading = false; _error = error.toString(); });
    } finally {
      if (mounted && generation == _generation && _loading) {
        setState(() { _loading = false; _error = 'ログイン状態が変わりました。再読み込みしてください。'; });
      }
    }
  }

  String _newDeviceKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<void> _authenticate() async {
    if (_busy || _loading || _lifecycle != AppLifecycleState.resumed) return;
    final deviceRepository = _deviceRepository;
    final authRepository = _authRepository;
    final actor = deviceRepository?.currentUserId;
    final token = _currentToken;
    final deviceKey = _deviceKey;
    if (deviceRepository == null || authRepository == null || actor == null || token == null || deviceKey == null || actor != _loadedActor || token != _loadedToken) {
      setState(() => _error = 'ログイン状態を再読み込みしてください。'); return;
    }
    String password = _password.text;
    _password.clear();
    if (password.isEmpty) return;
    if (!_secondaryConfigured) { setState(() => _error = 'Master画面を開く前に第2パスワードの設定が必要です。'); return; }
    if (!_biometricAvailable) { setState(() => _error = 'Master画面はFace ID / Touch ID対応端末でのみ利用できます。'); return; }
    if (!_trustedDevice && !_canBootstrap) { setState(() => _error = 'この端末は信頼済みMaster端末ではありません。'); return; }
    final generation = ++_generation;
    void clearCaptured() { password = ''; }
    _clearCaptured = clearCaptured;
    setState(() { _busy = true; _error = null; });
    try {
      if (!await deviceRepository.isMasterAdmin(accessToken: token)) throw StateError('Master管理者権限が必要です。');
      if (!_same(generation, actor, token)) return;
      final before = await deviceRepository.currentDeviceStatus(deviceKey, accessToken: token);
      if (!_same(generation, actor, token)) return;
      if (before['trusted'] != true && before['can_bootstrap'] != true) throw StateError('この端末は信頼済みMaster端末ではありません。');
      _nativePrompt = true;
      final biometricVerified = await _localAuth.authenticate(
        localizedReason: '${widget.title}を開くため生体認証を確認します',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!_same(generation, actor, token, nativeInactive: true)) return;
      if (!biometricVerified) throw StateError('生体認証を確認できませんでした。');
      if (_lifecycle == AppLifecycleState.inactive) {
        final wait = Completer<bool>(); _resume = wait;
        final resumed = await wait.future;
        if (identical(_resume, wait)) _resume = null;
        if (!resumed || !_same(generation, actor, token)) return;
      }
      _nativePrompt = false;
      final secondPasswordVerified = await authRepository.verifySecondaryPassword(password, accessToken: token);
      password = '';
      if (!_same(generation, actor, token)) return;
      if (!secondPasswordVerified) throw StateError('第2パスワードが違います。');
      final isMasterAdmin = await deviceRepository.isMasterAdmin(accessToken: token);
      if (!_same(generation, actor, token)) return;
      if (!isMasterAdmin) throw StateError('Master管理者権限が必要です。');
      final current = await deviceRepository.currentDeviceStatus(deviceKey, accessToken: token);
      if (!_same(generation, actor, token)) return;
      if (current['trusted'] != true) {
        if (before['can_bootstrap'] != true || current['can_bootstrap'] != true) throw StateError('信頼済み端末の状態が変わりました。');
        final device = await MasterDevicePlatform.detect();
        if (!_same(generation, actor, token)) return;
        await deviceRepository.bootstrapFirstDevice(deviceKey: deviceKey, deviceName: device.name, deviceType: device.type, platform: Platform.operatingSystem, accessToken: token);
        if (!_same(generation, actor, token)) return;
        final registered = await deviceRepository.currentDeviceStatus(deviceKey, accessToken: token);
        if (!_same(generation, actor, token)) return;
        if (registered['trusted'] != true) throw StateError('信頼済みMaster端末を確認できませんでした。');
      }
      _trustedDevice = true;
      _canBootstrap = false;
      final finalMaster = await deviceRepository.isMasterAdmin(accessToken: token);
      if (!_same(generation, actor, token)) return;
      final now = DateTime.now();
      final blocked = MasterStepUpPolicy.requiresFreshAuthentication(
        isMasterAdmin: finalMaster,
        trustedDevice: _trustedDevice,
        biometricVerified: biometricVerified,
        secondPasswordVerified: secondPasswordVerified,
        verifiedAt: now,
        now: now,
      );
      if (blocked) throw StateError('Master認証を完了できませんでした。');
      _expiryTimer?.cancel(); _expiryTimer = Timer(MasterStepUpPolicy.sessionDuration, _lock);
      if (!_same(generation, actor, token)) return;
      setState(() { _unlocked = true; _busy = false; });
    } catch (error) {
      if (mounted && generation == _generation) setState(() { _busy = false; _unlocked = false; _error = error.toString(); });
    } finally {
      password = '';
      if (identical(_clearCaptured, clearCaptured)) _clearCaptured = null;
      if (mounted && generation == _generation) setState(() { _busy = false; _nativePrompt = false; });
    }
  }

  Future<void> _openEmergencyRecovery() async {
    final recovered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const MasterEmergencyRecoveryPage(),
      ),
    );
    if (recovered != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _unlocked = false;
    });
    await _load();
  }

  void _lock() {
    _generation++;
    _clearCaptured?.call();
    final wait = _resume; _resume = null;
    if (wait != null && !wait.isCompleted) wait.complete(false);
    _nativePrompt = false;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _password.clear();
    if (!mounted) {
      _unlocked = false;
      return;
    }
    setState(() {
      _unlocked = false;
      _busy = false;
      if (_loading) { _loading = false; _error = '本人確認の読み込みを中断しました。再読み込みしてください。'; }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      final wait = _resume;
      if (wait != null && !wait.isCompleted) wait.complete(true);
    }
    if (state == AppLifecycleState.inactive && _nativePrompt) { _password.clear(); return; }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lock();
    }
  }

  @override
  void dispose() {
    _generation++; _clearCaptured?.call();
    final wait = _resume; if (wait != null && !wait.isCompleted) wait.complete(false);
    _authChanges?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dedicatedMode) return MasterPasswordProtectedPage(title: widget.title, access: widget.dedicatedAccess, child: widget.child);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_unlocked) return widget.child;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.security_outlined, size: 54),
                      const SizedBox(height: 12),
                      const Text(
                        'Master本人確認',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _canBootstrap && !_trustedDevice
                            ? 'この端末を最初の信頼済みMaster端末として登録します。'
                            : '信頼済み端末・生体認証・第2パスワードをすべて確認します。',
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        enabled: !_busy,
                        onSubmitted: (_) => _busy ? null : _authenticate(),
                        decoration: const InputDecoration(
                          labelText: '第2パスワード',
                          prefixIcon: Icon(Icons.password_outlined),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_error != null) TextButton(onPressed: _busy ? null : () { setState(() { _loading = true; _error = null; }); _load(); }, child: const Text('再読み込み')),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _authenticate,
                        icon: const Icon(Icons.fingerprint),
                        label: Text(
                          _canBootstrap && !_trustedDevice
                              ? '本人確認してこの端末を登録'
                              : 'Face ID / Touch ID＋第2パスで開く',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                      if (!_trustedDevice && !_canBootstrap) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _openEmergencyRecovery,
                          icon: const Icon(Icons.emergency_outlined),
                          label: const Text('信頼済み端末を使えない場合は緊急復旧'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
