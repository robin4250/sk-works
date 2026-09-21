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

class _SecondaryProtectedPageState extends State<SecondaryProtectedPage>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _localAuth = LocalAuthentication();

  bool _configuredLoading = true;
  bool _secondaryConfigured = false;
  bool _unlocked = false;
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _enableBiometricOnSetup = false;
  String? _message;

  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
  }

  Future<void> _loadState() async {
    final repository = _repository;
    final userId = repository?.currentUser?.id;
    if (repository == null || userId == null) return;

    try {
      final configured = await repository.secondaryPasswordConfigured();
      final prefs = await SharedPreferences.getInstance();
      final enabled =
          prefs.getBool('sko_secondary_biometric_enabled_$userId') ?? false;
      final available =
          await _localAuth.isDeviceSupported() &&
              await _localAuth.canCheckBiometrics;
      if (!mounted) return;
      setState(() {
        _secondaryConfigured = configured;
        _biometricEnabled = enabled;
        _biometricAvailable = available;
        _configuredLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _configuredLoading = false;
        _message = '第2認証の状態を確認できませんでした: $error';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _password.clear();
      _confirm.clear();
      if (mounted) {
        setState(() {
          _unlocked = false;
          _busy = false;
          _message = null;
        });
      } else {
        _unlocked = false;
        _busy = false;
        _message = null;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _saveSecondaryPassword() async {
    final repository = _repository;
    final userId = repository?.currentUser?.id;
    if (repository == null || userId == null) return;

    if (_password.text.length < 8) {
      setState(() => _message = '第2パスワードは8文字以上で設定してください。');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _message = '確認用の第2パスワードが一致していません。');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      if (_enableBiometricOnSetup) {
        final ok = await _localAuth.authenticate(
          localizedReason: '${widget.title}の第2認証にFace ID / Touch IDを使用します',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );
        if (!ok) {
          throw StateError('生体認証を確認できませんでした。');
        }
      }

      await repository.setSecondaryPassword(_password.text);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'sko_secondary_biometric_enabled_$userId',
        _enableBiometricOnSetup,
      );

      if (!mounted) return;
      setState(() {
        _secondaryConfigured = true;
        _biometricEnabled = _enableBiometricOnSetup;
        _unlocked = true;
        _busy = false;
        _password.clear();
        _confirm.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '第2パスワードを設定できませんでした: $error';
      });
    }
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
          _message = '第2パスワードが違います。';
        });
        return;
      }

      setState(() {
        _busy = false;
        _unlocked = true;
        _password.clear();
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
    if (_configuredLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_unlocked) return widget.child;

    if (!_secondaryConfigured) {
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
                        const Icon(Icons.password_outlined, size: 54),
                        const SizedBox(height: 14),
                        Text(
                          '第2パスワードを設定',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.title}を開くための第2パスワードを初回だけ設定します。'
                          '通常ログイン用の本パスワードとは別にしてください。',
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: '第2パスワード',
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
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirm,
                          obscureText: _obscureConfirm,
                          decoration: InputDecoration(
                            labelText: '第2パスワード（確認）',
                            prefixIcon: const Icon(Icons.password_outlined),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (_biometricAvailable) ...[
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Face ID / Touch IDも使う'),
                            value: _enableBiometricOnSetup,
                            onChanged: (value) => setState(
                              () => _enableBiometricOnSetup = value,
                            ),
                          ),
                        ],
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
                          onPressed: _busy ? null : _saveSecondaryPassword,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('設定して開く'),
                        ),
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
                        '第2認証が必要です',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.title}を開くため、第2パスワードで確認します。',
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        onSubmitted: (_) =>
                            _busy ? null : _unlockWithPassword(),
                        decoration: InputDecoration(
                          labelText: '第2パスワード',
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
                        label: const Text('第2パスワードで開く'),
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
