import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/secure_onboarding_repository.dart';
import 'master_device_repository.dart';
import 'master_emergency_recovery_page.dart';
import 'master_step_up_policy.dart';

/// Test seam for existing services; no new credential or server authorization.
abstract class MasterSecondaryAccess {
  String? get actor;
  String? get token;
  Future<bool> isMaster();
  Future<Map<String, dynamic>> status(String key);
  Future<bool> configured();
  Future<bool> biometricAvailable();
  Future<bool> biometric();
  Future<bool> verify(String password, String capturedToken);
  Future<void> bootstrap(String key, String name, String type, String platform, String capturedToken);
}
class _ExistingMasterAccess implements MasterSecondaryAccess {
  final _device = MasterDeviceRepository.maybeCreate();
  final _auth = SecureOnboardingRepository.maybeCreate();
  final _local = LocalAuthentication();
  @override String? get actor => _device?.currentUserId;
  @override String? get token => SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentSession?.accessToken : null;
  @override Future<bool> isMaster() async => await _device?.isMasterAdmin() ?? false;
  @override Future<Map<String, dynamic>> status(String key) async => await _device?.currentDeviceStatus(key) ?? const {};
  @override Future<bool> configured() async => await _auth?.secondaryPasswordConfigured() ?? false;
  @override Future<bool> biometricAvailable() async => await _local.isDeviceSupported() && await _local.canCheckBiometrics;
  @override Future<bool> biometric() => _local.authenticate(localizedReason: 'Master管理を開くため本人確認します', options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true));
  @override Future<bool> verify(String password, String capturedToken) async {
    if (!SupabaseBackend.isInitialized) return false;
    return verifyMasterSharedSecondaryWithCapturedSession(SupabaseBackend.client, password: password, capturedToken: capturedToken);
  }
  @override Future<void> bootstrap(String key, String name, String type, String platform, String capturedToken) async {
    if (!SupabaseBackend.isInitialized) throw StateError('Master認証を利用できません。');
    await bootstrapMasterDeviceWithCapturedSession(SupabaseBackend.client, key: key, name: name, type: type, platform: platform, capturedToken: capturedToken);
  }
}

/// Same shared secondary credential RPC, with per-request actor binding.
Future<bool> verifyMasterSharedSecondaryWithCapturedSession(SupabaseClient client, {
  required String password, required String capturedToken,
}) async {
  final result = await client.rpc('verify_secondary_password', params: {
    'p_password': password,
  }).setHeader('Authorization', 'Bearer $capturedToken');
  return result == true;
}

/// Existing bootstrap RPC, fixed to the session which approved this operation.
/// A request already sent for actor A is not server-cancelled by a later actor B.
Future<void> bootstrapMasterDeviceWithCapturedSession(SupabaseClient client, {
  required String key, required String name, required String type,
  required String platform, required String capturedToken,
}) async {
  await client.rpc('bootstrap_first_master_device', params: {
    'p_device_key': key, 'p_device_name': name, 'p_device_type': type, 'p_platform': platform,
  }).setHeader('Authorization', 'Bearer $capturedToken');
}

/// Local entry gate only. Important server operation proofs remain separate.
class MasterSecondaryEntryPolicy {
  static bool allows({required bool master, required bool trusted, required bool configured,
    required bool passwordVerified, required bool biometricVerified,
    required bool biometricEnabled, required bool bootstrap}) =>
      master && trusted && configured && (bootstrap
        ? passwordVerified && biometricVerified
        : passwordVerified || biometricEnabled && biometricVerified);
}

class MasterProtectedPage extends StatefulWidget {
  const MasterProtectedPage({
    super.key,
    required this.title,
    required this.child,
    this.access,
  });

  final String title;
  final Widget child;
  final MasterSecondaryAccess? access;

  @override
  State<MasterProtectedPage> createState() => _MasterProtectedPageState();
}

class _MasterProtectedPageState extends State<MasterProtectedPage>
    with WidgetsBindingObserver {
  late final MasterSecondaryAccess _access;
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
  bool _biometricEnabled = false;
  bool _nativePrompt = false;
  Completer<bool>? _resumeWait;
  int _generation = 0;
  String? _loadedActor;
  String? _loadedToken;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    _access = widget.access ?? _ExistingMasterAccess();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final userId = _access.actor;
    final token = _access.token;
    final generation = ++_generation;
    if (userId == null || token == null) {
      setState(() { _loading = false; _error = 'Master認証を利用できません。'; });
      return;
    }

    try {
      if (!await _access.isMaster()) {
        throw StateError('Master管理者権限が必要です。');
      }

      final prefs = await SharedPreferences.getInstance();
      var deviceKey = prefs.getString('sko_master_device_key_$userId');
      if (deviceKey == null || deviceKey.length < 32) {
        deviceKey = _newDeviceKey();
        await prefs.setString('sko_master_device_key_$userId', deviceKey);
      }

      final status = await _access.status(deviceKey);
      final secondaryConfigured =
          await _access.configured();
      final biometricAvailable = await _access.biometricAvailable();

      if (!mounted || generation != _generation) return;
      if (_access.actor != userId || _access.token != token) {
        setState(() { _loading = false; _loadedActor = null; _loadedToken = null; _error = 'ログイン状態が変わりました。再読み込みしてください。'; });
        return;
      }
      setState(() {
        _loadedActor = userId;
        _loadedToken = token;
        _biometricEnabled = prefs.getBool('sko_secondary_biometric_enabled_$userId') ?? false;
        _deviceKey = deviceKey;
        _trustedDevice = status['trusted'] == true;
        _canBootstrap = status['can_bootstrap'] == true;
        _secondaryConfigured = secondaryConfigured;
        _biometricAvailable = biometricAvailable;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _newDeviceKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  bool _valid(int generation, String actor, String token, {bool allowInactivePrompt = false}) =>
      mounted && generation == _generation && _access.actor == actor && _access.token == token &&
      (_lifecycle == AppLifecycleState.resumed || allowInactivePrompt && _nativePrompt && _lifecycle == AppLifecycleState.inactive) &&
      ModalRoute.of(context)?.isCurrent == true;

  Future<void> _authenticate({bool face = false}) async {
    if (_busy || _loading) return;
    final actor = _access.actor;
    final token = _access.token;
    final key = _deviceKey;
    if (_lifecycle != AppLifecycleState.resumed) return;
    if (actor == null || token == null || actor != _loadedActor || token != _loadedToken || key == null) { setState(() => _error = 'ログイン状態が変わりました。再読み込みしてください。'); return; }
    final bootstrap = !_trustedDevice && _canBootstrap;
    String password = _password.text;
    _password.clear();
    if (!_secondaryConfigured) { setState(() => _error = '第2パスワードの設定が必要です。'); return; }
    if (!face && password.isEmpty) return;
    if (face && (!_biometricAvailable || !_biometricEnabled)) { setState(() => _error = '請求書などの第2認証でFace ID / Touch IDを有効にしてください。'); return; }
    if (bootstrap && !_biometricAvailable) { setState(() => _error = '最初のMaster端末登録には生体認証が必要です。'); return; }
    final generation = ++_generation;
    var passwordVerified = false;
    var biometricVerified = false;
    setState(() { _busy = true; _error = null; });
    try {
      if (!await _access.isMaster()) throw StateError('Master管理者権限が必要です。');
      if (!_valid(generation, actor, token)) return;
      final before = await _access.status(key);
      if (!_valid(generation, actor, token)) return;
      if (bootstrap ? before['can_bootstrap'] != true || before['trusted'] == true : before['trusted'] != true) throw StateError('信頼済みMaster端末を確認できません。');
      if (face || bootstrap) {
        _nativePrompt = true;
        final ok = await _access.biometric();
        // Native Face may briefly report inactive. Real background invalidates.
        if (!_valid(generation, actor, token, allowInactivePrompt: true)) return;
        if (!ok) throw StateError('生体認証を確認できませんでした。');
        biometricVerified = ok;
        if (_lifecycle == AppLifecycleState.inactive) {
          final wait = Completer<bool>();
          _resumeWait = wait;
          final resumed = await wait.future;
          if (identical(_resumeWait, wait)) _resumeWait = null;
          if (!resumed || !_valid(generation, actor, token)) return;
        }
        _nativePrompt = false;
      }
      if (!face || bootstrap) {
        final ok = await _access.verify(password, token);
        password = '';
        if (!_valid(generation, actor, token)) return;
        if (!ok) throw StateError('第2パスワードが違います。');
        passwordVerified = ok;
      }
      if (!await _access.isMaster()) throw StateError('Master管理者権限が必要です。');
      if (!_valid(generation, actor, token)) return;
      final after = await _access.status(key);
      if (!_valid(generation, actor, token)) return;
      var trusted = after['trusted'] == true;
      if (bootstrap) {
        if (after['can_bootstrap'] != true || after['trusted'] == true) throw StateError('端末の登録状態が変わりました。');
        await _access.bootstrap(key, _deviceName(), _deviceType(), Platform.operatingSystem, token);
        if (!_valid(generation, actor, token)) return;
        final registered = await _access.status(key);
        trusted = registered['trusted'] == true;
        if (!_valid(generation, actor, token) || !trusted) throw StateError('信頼済みMaster端末を確認できません。');
      } else if (after['trusted'] != true) { throw StateError('信頼済みMaster端末を確認できません。'); }
      final master = await _access.isMaster();
      if (!_valid(generation, actor, token)) return;
      if (!MasterSecondaryEntryPolicy.allows(master: master, trusted: trusted, configured: _secondaryConfigured,
          passwordVerified: passwordVerified, biometricVerified: biometricVerified,
          biometricEnabled: _biometricEnabled, bootstrap: bootstrap)) {
        throw StateError('Master認証を完了できませんでした。');
      }
      _expiryTimer?.cancel();
      _expiryTimer = Timer(MasterStepUpPolicy.sessionDuration, _lock);
      if (!_valid(generation, actor, token)) return;
      setState(() { _trustedDevice = true; _canBootstrap = false; _unlocked = true; });
    } catch (error) {
      if (mounted && generation == _generation) setState(() { _unlocked = false; _error = error.toString(); });
    } finally {
      password = '';
      if (generation == _generation) {
        _nativePrompt = false;
        if (mounted) {
          setState(() {
          _busy = false;
          if (_access.actor != actor || _access.token != token) _error = 'ログイン状態が変わりました。再読み込みしてください。';
          });
        }
      }
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

  String _deviceName() => Platform.isIOS
      ? 'SKO Master iOS'
      : Platform.isMacOS
          ? 'SKO Master Mac'
          : 'SKO Master Device';

  String _deviceType() => Platform.isIOS
      ? 'iphone'
      : Platform.isMacOS
          ? 'mac'
          : 'other';

  void _lock() {
    final wait = _resumeWait;
    _resumeWait = null;
    if (wait != null && !wait.isCompleted) wait.complete(false);
    final interruptedLoad = _loading;
    _generation++;
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
      if (interruptedLoad) {
        _loading = false;
        _error = '本人確認の読み込みを中断しました。再読み込みしてください。';
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      final wait = _resumeWait;
      if (wait != null && !wait.isCompleted) wait.complete(true);
    }
    if (state == AppLifecycleState.inactive && _nativePrompt) {
      _password.clear();
      return;
    }
    if (state != AppLifecycleState.resumed) _lock();
  }

  @override
  void dispose() {
    _generation++;
    final wait = _resumeWait;
    if (wait != null && !wait.isCompleted) wait.complete(false);
    _resumeWait = null;
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                            : '信頼済みMaster端末で、請求書などと共通の第2パスワードまたはFace ID / Touch IDで確認します。',
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
                              : '第2パスワードで開く',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                      if (_trustedDevice && _biometricAvailable && _biometricEnabled) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(onPressed: _busy ? null : () => _authenticate(face: true), icon: const Icon(Icons.fingerprint), label: const Text('Face ID / Touch IDで開く')),
                      ],
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
