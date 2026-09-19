import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_onboarding_repository.dart';

class SecondaryProtectedPage extends StatefulWidget {
  const SecondaryProtectedPage({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  State<SecondaryProtectedPage> createState() => _SecondaryProtectedPageState();
}

class _SecondaryProtectedPageState extends State<SecondaryProtectedPage> {
  final _password = TextEditingController();
  final _localAuth = LocalAuthentication();

  bool _unlocked = false;
  bool _busy = false;
  bool _obscure = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String? _message;

  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final repository = _repository;
    final userId = repository?.currentUser?.id;
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled =
          prefs.getBool('sko_secondary_biometric_enabled_$userId') ?? false;
      final available =
          await _localAuth.isDeviceSupported() && await _localAuth.canCheckBiometrics;
      if (!mounted) return;
      setState(() {
        _biometricEnabled = enabled;
        _biometricAvailable = available;
      });
    } catch (_) {
      // Password unlock remains available.
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlockWithPassword() async {
    final repository = _repository;
    if (repository == null || _password.text.isEmpty) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final ok = await repository.verifySecondaryPassword(_password.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _message = 'パスワードが違います。';
        });
        return;
      }

      setState(() {
        _busy = false;
        _unlocked = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.toString().contains('temporarily locked')
            ? '入力回数が多いため、5分後にもう一度お試しください。'
            : '認証できませんでした: $error';
      });
    }
  }

  Future<void> _unlockWithBiometric() async {
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final ok = await _localAuth.authenticate(
        localizedReason: '${widget.title}を開くため本人確認します',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unlocked = ok;
        if (!ok) _message = '生体認証を確認できませんでした。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '生体認証を利用できません: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_person_outlined, size: 54),
                      const SizedBox(height: 14),
                      Text(
                        '追加認証が必要です',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.title}には重要な情報が含まれるため、第2パスワードで確認します。',
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        onSubmitted: (_) =>
                            _busy ? null : _unlockWithPassword(),
                        decoration: InputDecoration(
                          labelText: '重要情報用パスワード',
                          prefixIcon: const Icon(Icons.password_outlined),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _unlockWithPassword,
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('パスワードで開く'),
                      ),
                      if (_biometricEnabled && _biometricAvailable) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _unlockWithBiometric,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Face ID / Touch IDで開く'),
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
