import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'secure_onboarding_repository.dart';
import 'secondary_password_primary_verifier.dart';

abstract class SecondaryPasswordResetAccess {
  String? get currentUserId;
  Future<bool> authenticate();
  Future<bool> authenticateWithPassword(String password);
  Future<void> save(String password);
}

class _DeviceResetAccess implements SecondaryPasswordResetAccess {
  final _auth = LocalAuthentication();
  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();
  @override
  String? get currentUserId => _repository?.currentUser?.id;
  @override
  Future<bool> authenticate() => _auth.authenticate(
    localizedReason: '第2パスワードを再設定するため本人確認します',
    options: const AuthenticationOptions(
      biometricOnly: true,
      stickyAuth: false,
    ),
  );
  @override
  Future<bool> authenticateWithPassword(String password) =>
      SecondaryPasswordPrimaryVerifier(
        currentUser: () => _repository?.currentUser,
      ).verify(password);

  @override
  Future<void> save(String password) async {
    final repository = _repository;
    if (repository == null) throw StateError('Authentication required');
    await repository.setSecondaryPassword(password);
  }
}

class SecondaryPasswordResetPage extends StatefulWidget {
  const SecondaryPasswordResetPage({
    super.key,
    this.access,
    this.biometricAvailable = true,
  });
  final bool biometricAvailable;
  final SecondaryPasswordResetAccess? access;
  @override
  State<SecondaryPasswordResetPage> createState() => _ResetState();
}

class _ResetState extends State<SecondaryPasswordResetPage>
    with WidgetsBindingObserver {
  late final _access = widget.access ?? _DeviceResetAccess();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _primaryPassword = TextEditingController();
  late bool _usePassword = !widget.biometricAvailable;
  bool _nativePrompt = false;
  String? _actor;
  String? _pendingActor;
  String? _message;
  bool _authenticating = false;
  bool _saving = false;
  int _generation = 0;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool get _busy => _authenticating || _saving;

  @override
  void initState() {
    super.initState();
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    _generation++;
    _actor = null;
    _pendingActor = null;
    _password.clear();
    _confirm.clear();
    _primaryPassword.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      if (_pendingActor != null) {
        setState(() {
          _actor = _pendingActor == _access.currentUserId
              ? _pendingActor
              : null;
          _pendingActor = null;
        });
      }
      return;
    }
    // iOS biometric prompts themselves make the app inactive. A real
    // background transition still invalidates that in-flight authentication.
    if (state == AppLifecycleState.inactive && _nativePrompt) return;
    setState(() {
      _clear();
      _message = _saving
          ? '保存結果を確認できません。新しい第2パスワードで認証をお試しください。再設定する場合は本人確認からやり直してください。'
          : '本人確認からやり直してください。';
    });
  }

  Future<void> _authenticate() async {
    if (_busy || _lifecycle != AppLifecycleState.resumed) return;
    final actor = _access.currentUserId;
    if (actor == null) {
      setState(() => _message = 'ログイン状態を確認してください。');
      return;
    }
    final primary = _usePassword;
    final password = _primaryPassword.text;
    if (primary && password.isEmpty) {
      setState(() => _message = '本パスワードを入力してください。');
      return;
    }
    setState(() {
      _clear();
      _nativePrompt = !primary;
      _authenticating = true;
      _message = null;
    });
    final generation = _generation;
    try {
      final ok = primary
          ? await _access.authenticateWithPassword(password)
          : await _access.authenticate();
      if (!mounted || generation != _generation) return;
      setState(() {
        if (ok && actor == _access.currentUserId) {
          if (_lifecycle == AppLifecycleState.resumed) {
            _actor = actor;
          } else if (_lifecycle == AppLifecycleState.inactive) {
            _pendingActor = actor;
          }
        } else {
          _message = '本人確認を完了できませんでした。もう一度お試しください。';
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _message = primary
              ? '本パスワードで本人確認できませんでした。入力内容を確認してもう一度お試しください。'
              : '生体認証を利用できません。もう一度お試しください。',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _authenticating = false;
          _nativePrompt = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _actor == null || _lifecycle != AppLifecycleState.resumed) {
      return;
    }
    final actor = _actor!;
    if (actor != _access.currentUserId) {
      setState(() {
        _clear();
        _message = 'ログイン状態が変わりました。本人確認をやり直してください。';
      });
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _message = '第2パスワードは8文字以上で設定してください。');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _message = '確認用の第2パスワードが一致していません。');
      return;
    }
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await _access.save(_password.text);
      if (!mounted || generation != _generation) return;
      if (actor != _access.currentUserId) {
        setState(() {
          _clear();
          _message = 'ログイン状態が変わりました。本人確認をやり直してください。';
        });
        return;
      }
      _clear();
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _clear();
          _message =
              '保存結果を確認できませんでした。新しい第2パスワードで認証をお試しください。再設定する場合は本人確認からやり直してください。';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    _password.dispose();
    _confirm.dispose();
    _primaryPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) _clear();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('第2パスワードを再設定')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('本人確認した後、新しい第2パスワードを設定します。'),
                const SizedBox(height: 16),
                if (_actor == null) ...[
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: const Text('Face ID / Touch ID'),
                        enabled: widget.biometricAvailable,
                      ),
                      const ButtonSegment(value: true, label: Text('本パスワード')),
                    ],
                    selected: {_usePassword},
                    onSelectionChanged: _busy
                        ? null
                        : (selection) => setState(() {
                            _clear();
                            _usePassword = selection.single;
                            _message = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  if (_usePassword)
                    TextField(
                      key: const Key('primary-password'),
                      controller: _primaryPassword,
                      enabled: !_busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'ログイン用の本パスワード',
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _authenticate,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('本人確認する'),
                  ),
                ],
                if (_actor != null) ...[
                  TextField(
                    key: const Key('reset-password'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '新しい第2パスワード（8文字以上）',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('reset-confirm'),
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '新しい第2パスワード（確認）',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('再設定する'),
                  ),
                ],
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message!),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
