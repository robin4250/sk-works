import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/secure_onboarding_repository.dart';
import 'master_device_repository.dart';
import 'master_emergency_recovery_page.dart';
import 'master_step_up_policy.dart';

class MasterProtectedPage extends StatefulWidget {
  const MasterProtectedPage({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  State<MasterProtectedPage> createState() => _MasterProtectedPageState();
}

class _MasterProtectedPageState extends State<MasterProtectedPage>
    with WidgetsBindingObserver {
  final _deviceRepository = MasterDeviceRepository.maybeCreate();
  final _authRepository = SecureOnboardingRepository.maybeCreate();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final deviceRepository = _deviceRepository;
    final authRepository = _authRepository;
    final userId = deviceRepository?.currentUserId;
    if (deviceRepository == null || authRepository == null || userId == null) {
      setState(() {
        _loading = false;
        _error = 'Master認証を利用できません。';
      });
      return;
    }

    try {
      if (!await deviceRepository.isMasterAdmin()) {
        throw StateError('Master管理者権限が必要です。');
      }

      final prefs = await SharedPreferences.getInstance();
      var deviceKey = prefs.getString('sko_master_device_key_$userId');
      if (deviceKey == null || deviceKey.length < 32) {
        deviceKey = _newDeviceKey();
        await prefs.setString('sko_master_device_key_$userId', deviceKey);
      }

      final status = await deviceRepository.currentDeviceStatus(deviceKey);
      final secondaryConfigured =
          await authRepository.secondaryPasswordConfigured();
      final biometricAvailable = await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;

      if (!mounted) return;
      setState(() {
        _deviceKey = deviceKey;
        _trustedDevice = status['trusted'] == true;
        _canBootstrap = status['can_bootstrap'] == true;
        _secondaryConfigured = secondaryConfigured;
        _biometricAvailable = biometricAvailable;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
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

  Future<void> _authenticate() async {
    final deviceRepository = _deviceRepository;
    final authRepository = _authRepository;
    final deviceKey = _deviceKey;
    if (deviceRepository == null ||
        authRepository == null ||
        deviceKey == null ||
        _password.text.isEmpty) {
      return;
    }

    if (!_secondaryConfigured) {
      setState(() => _error = 'Master画面を開く前に第2パスワードの設定が必要です。');
      return;
    }
    if (!_biometricAvailable) {
      setState(() => _error = 'Master画面はFace ID / Touch ID対応端末でのみ利用できます。');
      return;
    }
    if (!_trustedDevice && !_canBootstrap) {
      setState(() => _error = 'この端末は信頼済みMaster端末ではありません。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final biometricVerified = await _localAuth.authenticate(
        localizedReason: '${widget.title}を開くため生体認証を確認します',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!biometricVerified) {
        throw StateError('生体認証を確認できませんでした。');
      }

      final secondPasswordVerified =
          await authRepository.verifySecondaryPassword(_password.text);
      if (!secondPasswordVerified) {
        throw StateError('第2パスワードが違います。');
      }

      if (!_trustedDevice && _canBootstrap) {
        await deviceRepository.bootstrapFirstDevice(
          deviceKey: deviceKey,
          deviceName: _deviceName(),
          deviceType: _deviceType(),
          platform: Platform.operatingSystem,
        );
        _trustedDevice = true;
        _canBootstrap = false;
      }

      final now = DateTime.now();
      final blocked = MasterStepUpPolicy.requiresFreshAuthentication(
        isMasterAdmin: true,
        trustedDevice: _trustedDevice,
        biometricVerified: biometricVerified,
        secondPasswordVerified: secondPasswordVerified,
        verifiedAt: now,
        now: now,
      );
      if (blocked) {
        throw StateError('Master認証を完了できませんでした。');
      }

      _password.clear();
      _expiryTimer?.cancel();
      _expiryTimer = Timer(MasterStepUpPolicy.sessionDuration, _lock);
      if (!mounted) return;
      setState(() {
        _unlocked = true;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unlocked = false;
        _error = error.toString();
      });
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
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lock();
    }
  }

  @override
  void dispose() {
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
