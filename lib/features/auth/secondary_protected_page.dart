import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/supabase_backend.dart';

import 'secure_onboarding_repository.dart';
import 'secondary_password_reset_page.dart';
import 'secondary_entry_access.dart';

class SecondaryProtectedPage extends StatefulWidget {
  const SecondaryProtectedPage({
    super.key,
    required this.title,
    required this.child,
    this.entryAccess,
  });

  final String title;
  final Widget child;
  final SecondaryEntryAccess Function()? entryAccess;

  @override
  State<SecondaryProtectedPage> createState() => _SecondaryProtectedPageState();
}

class _SecondaryProtectedPageState extends State<SecondaryProtectedPage>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _localAuth = LocalAuthentication();

  bool _configuredLoading = true;
  bool _configurationKnown = false;
  bool _secondaryConfigured = false;
  bool _unlocked = false;
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _enableBiometricOnSetup = false;
  String? _message;
  int _generation = 0;
  bool _nativePrompt = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Completer<void>? _resumeWaiter;
  SecondaryEntryAccess? _entryAccess;

  void _entryInvalidated() {
    if (mounted && _unlocked && _entryAccess?.isOpen == false) {
      _generation++;
      setState(() {
        _unlocked = false;
        _busy = false;
        _password.clear();
        _message = '勤怠管理を開くため、もう一度本人確認してください。';
      });
    }
  }

  bool _sameAttempt(int generation, String actor, String token) {
    if (!mounted || generation != _generation || !SupabaseBackend.isInitialized) return false;
    final session = SupabaseBackend.client.auth.currentSession;
    return session?.user.id == actor && session?.accessToken == token && session?.isExpired == false;
  }

  bool _acceptAttempt(int generation, String actor, String token) {
    if (_sameAttempt(generation, actor, token)) return true;
    // Only the invalidated operation owns this reset. A newer retry's epoch is
    // never touched by an old completion, including its busy/loading state.
    if (mounted && generation == _generation) {
      _generation++;
      _entryAccess?.invalidate();
      _resumeWaiter?.complete();
      _resumeWaiter = null;
      setState(() {
        _nativePrompt = false;
        _busy = false;
        _configuredLoading = false;
        _configurationKnown = false;
        _secondaryConfigured = false;
        _unlocked = false;
        _biometricEnabled = false;
        _biometricAvailable = false;
        _password.clear();
        _confirm.clear();
        _message = 'ログイン状態が変わりました。再読み込みしてください。';
      });
    }
    return false;
  }

  Future<bool> _finishNativePrompt(int generation, String actor, String token) async {
    if (!_acceptAttempt(generation, actor, token)) return false;
    if (_lifecycle == AppLifecycleState.inactive) {
      _resumeWaiter = Completer<void>();
      await _resumeWaiter!.future;
    }
    if (!_acceptAttempt(generation, actor, token) || _lifecycle != AppLifecycleState.resumed) return false;
    _nativePrompt = false;
    return true;
  }

  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _loadState();
  }

  Future<void> _loadState() async {
    if (mounted) setState(() { _configuredLoading = true; _configurationKnown = false; _message = null; });
    final repository = _repository;
    final userId = repository?.currentUser?.id;
    final session = SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentSession : null;
    if (repository == null || userId == null || session == null || session.isExpired) {
      if (!mounted) return;
      setState(() {
        _configuredLoading = false;
        _message = 'ログイン状態を確認できません。ログイン後に再読み込みしてください。';
      });
      return;
    }
    final generation = ++_generation, token = session.accessToken;
    try {
      if (_entryAccess == null && widget.entryAccess != null) {
        _entryAccess = widget.entryAccess!();
        _entryAccess!.addListener(_entryInvalidated);
      }
      await _entryAccess?.prepare();
      if (!_acceptAttempt(generation, userId, token)) return;
      final configured = await repository.secondaryPasswordConfigured(accessToken: token);
      if (!_acceptAttempt(generation, userId, token)) return;
      final prefs = await SharedPreferences.getInstance();
      if (!_acceptAttempt(generation, userId, token)) return;
      final enabled =
          prefs.getBool('sko_secondary_biometric_enabled_$userId') ?? false;
      final supported = await _localAuth.isDeviceSupported();
      if (!_acceptAttempt(generation, userId, token)) return;
      final available = supported && await _localAuth.canCheckBiometrics;
      if (!_acceptAttempt(generation, userId, token)) return;
      setState(() {
        _secondaryConfigured = configured;
        _configurationKnown = true;
        _biometricEnabled = enabled;
        _biometricAvailable = available;
        _configuredLoading = false;
      });
    } catch (error) {
      if (!_acceptAttempt(generation, userId, token)) return;
      setState(() {
        _configuredLoading = false;
        _message = '第2認証の状態を確認できませんでした: $error';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      _resumeWaiter?.complete();
      _resumeWaiter = null;
      if (_configuredLoading) _loadState();
      return;
    }
    // A native prompt may make iOS inactive; never expose content until resumed.
    if (state == AppLifecycleState.inactive && _nativePrompt) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _generation++;
      _entryAccess?.invalidate();
      _resumeWaiter?.complete();
      _resumeWaiter = null;
      _nativePrompt = false;
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
    _generation++;
    _entryAccess?.removeListener(_entryInvalidated);
    unawaited(_entryAccess?.close() ?? Future<void>.value());
    _resumeWaiter?.complete();
    _resumeWaiter = null;
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _saveSecondaryPassword() async {
    final repository = _repository;
    final userId = repository?.currentUser?.id;
    final session = SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentSession : null;
    if (_busy || _lifecycle != AppLifecycleState.resumed || repository == null ||
        userId == null || session == null || session.isExpired) {
      return;
    }
    final password = _password.text;
    final enableBiometric = _enableBiometricOnSetup;
    final generation = ++_generation, token = session.accessToken;

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
      if (enableBiometric) {
        _nativePrompt = true;
        final ok = await _localAuth.authenticate(
          localizedReason: '${widget.title}の第2認証にFace ID / Touch IDを使用します',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );
        if (!await _finishNativePrompt(generation, userId, token)) return;
        if (!ok) {
          throw StateError('生体認証を確認できませんでした。');
        }
      }
      if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
      // The native prompt exception ends before server or preferences work.
      // Later inactive events must invalidate the pending save normally.
      _nativePrompt = false;
      await repository.setSecondaryPassword(password);
      if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
      if (_entryAccess?.requiredByServer == true &&
          !await _entryAccess!.unlock(password)) {
        throw StateError('勤怠管理の入口認証を完了できませんでした。');
      }
      if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
      final prefs = await SharedPreferences.getInstance();
      if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
      await prefs.setBool(
        'sko_secondary_biometric_enabled_$userId',
        enableBiometric,
      );

      if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
      setState(() {
        _secondaryConfigured = true;
        _biometricEnabled = enableBiometric;
        _unlocked = true;
        _busy = false;
        _password.clear();
        _confirm.clear();
      });
    } catch (error) {
      if (_nativePrompt && !await _finishNativePrompt(generation, userId, token)) return;
      if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
      setState(() {
        _busy = false;
        _message = '第2パスワードを設定できませんでした: $error';
      });
    } finally {
      if (mounted && generation == _generation) _nativePrompt = false;
    }
  }

  Future<void> _unlockWithPassword() async {
    final repository = _repository;
    final session = SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentSession : null;
    if (_busy || _lifecycle != AppLifecycleState.resumed || repository == null ||
        session == null || session.isExpired || _password.text.isEmpty) {
      return;
    }
    final actor = session.user.id, token = session.accessToken;
    final generation = ++_generation;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final ok = _entryAccess?.requiredByServer == true
          ? await _entryAccess!.unlock(_password.text)
          : await repository.verifySecondaryPassword(_password.text, accessToken: token);
      if (!_acceptAttempt(generation, actor, token) || _lifecycle != AppLifecycleState.resumed) return;
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
      if (!_acceptAttempt(generation, actor, token) || _lifecycle != AppLifecycleState.resumed) return;
      setState(() {
        _busy = false;
        _message = error.toString().contains('temporarily locked')
            ? '入力回数が多いため、5分後にもう一度お試しください。'
            : '認証できませんでした: $error';
      });
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (_entryAccess?.requiredByServer == true) return;
    final repository = _repository;
    final userId = repository?.currentUser?.id;
    final session = SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentSession : null;
    if (_busy || _lifecycle != AppLifecycleState.resumed || session == null ||
        session.isExpired || userId == null) {
      return;
    }
    final token = session.accessToken;
    final generation = ++_generation;
    _nativePrompt = true;
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
      if (!await _finishNativePrompt(generation, userId, token)) return;

      if (ok && !_biometricEnabled) {
        final prefs = await SharedPreferences.getInstance();
        if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
        await prefs.setBool('sko_secondary_biometric_enabled_$userId', true);
      }

      if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
      setState(() {
        _busy = false;
        _unlocked = ok;
        if (ok) {
          _biometricEnabled = true;
        } else {
          _message = '生体認証を確認できませんでした。';
        }
      });
    } catch (error) {
      if (_nativePrompt && !await _finishNativePrompt(generation, userId, token)) return;
      if (!_acceptAttempt(generation, userId, token) || _lifecycle != AppLifecycleState.resumed) return;
      setState(() {
        _busy = false;
        _message = '生体認証を利用できません: $error';
      });
    } finally {
      if (mounted && generation == _generation) _nativePrompt = false;
    }
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    final userId = _repository?.currentUser?.id;
    _entryAccess?.invalidate();
    setState(() => _busy = true);
    _password.clear();
    _confirm.clear();
    final reset = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SecondaryPasswordResetPage(biometricAvailable: _biometricAvailable),
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _unlocked = false;
      _password.clear();
      _confirm.clear();
      _message = reset == true && userId == _repository?.currentUser?.id
          ? '第2パスワードを再設定しました。新しいパスワードで認証してください。'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_configuredLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Never present password setup when authentication state was not loaded.
    if (_message != null && !_configurationKnown) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_message!, textAlign: TextAlign.center),
              ),
              OutlinedButton.icon(
                onPressed: _loadState,
                icon: const Icon(Icons.refresh),
                label: const Text('再読み込み'),
              ),
            ],
          ),
        ),
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
                          style: Theme.of(context).textTheme.headlineSmall
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
                        if (_biometricAvailable && _entryAccess?.requiredByServer != true) ...[
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Face ID / Touch IDも使う'),
                            value: _enableBiometricOnSetup,
                            onChanged: (value) =>
                                setState(() => _enableBiometricOnSetup = value),
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text('${widget.title}を開くため、第2パスワードで確認します。'),
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
                      TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('第2パスワードを再設定'),
                      ),
                      if (_biometricAvailable && _entryAccess?.requiredByServer != true) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _unlockWithBiometric,
                          icon: const Icon(Icons.fingerprint),
                          label: Text(
                            _biometricEnabled
                                ? 'Face ID / Touch IDで開く'
                                : 'Face ID / Touch IDを使って開く',
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

