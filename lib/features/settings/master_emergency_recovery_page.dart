import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../auth/secure_onboarding_repository.dart';
import 'master_recovery_repository.dart';

class MasterEmergencyRecoveryPage extends StatefulWidget {
  const MasterEmergencyRecoveryPage({super.key});

  @override
  State<MasterEmergencyRecoveryPage> createState() =>
      _MasterEmergencyRecoveryPageState();
}

class _MasterEmergencyRecoveryPageState
    extends State<MasterEmergencyRecoveryPage> {
  final _repository = MasterRecoveryRepository.maybeCreate();
  final _authRepository = SecureOnboardingRepository.maybeCreate();
  final _localAuth = LocalAuthentication();
  final _secondaryPassword = TextEditingController();
  final _primaryCode = TextEditingController();
  final _secondaryCode = TextEditingController();

  bool _busy = false;
  String? _challengeId;
  DateTime? _expiresAt;
  String? _error;

  bool get _codesSent => _challengeId != null;

  Future<void> _startRecovery() async {
    final repository = _repository;
    final authRepository = _authRepository;
    if (repository == null || authRepository == null) {
      setState(() => _error = 'Master緊急復旧を利用できません。');
      return;
    }
    if (_secondaryPassword.text.isEmpty) {
      setState(() => _error = '第2パスワードを入力してください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (!await authRepository.secondaryPasswordConfigured()) {
        throw StateError('Master緊急復旧には第2パスワード設定が必要です。');
      }

      final biometricAvailable = await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
      if (!biometricAvailable) {
        throw StateError('Face ID / Touch ID対応端末でのみ復旧できます。');
      }

      final biometricVerified = await _localAuth.authenticate(
        localizedReason: 'Master緊急復旧を開始するため生体認証を確認します',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!biometricVerified) {
        throw StateError('生体認証を確認できませんでした。');
      }

      final passwordVerified =
          await authRepository.verifySecondaryPassword(_secondaryPassword.text);
      if (!passwordVerified) {
        throw StateError('第2パスワードが違います。');
      }

      final challenge = await repository.startEmergencyRecovery();
      if (!mounted) return;
      _secondaryPassword.clear();
      setState(() {
        _challengeId = challenge.challengeId;
        _expiresAt = challenge.expiresAt;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _verifyAndRegister() async {
    final repository = _repository;
    final challengeId = _challengeId;
    final primaryCode = _primaryCode.text.trim();
    final secondaryCode = _secondaryCode.text.trim();

    if (repository == null || challengeId == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(primaryCode) ||
        !RegExp(r'^\d{6}$').hasMatch(secondaryCode)) {
      setState(() => _error = '2つの6桁コードを入力してください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final primary = await repository.verifyRecoveryCode(
        challengeId: challengeId,
        channel: 'primary',
        code: primaryCode,
      );
      if (!primary.primaryVerified) {
        throw StateError('復旧用メール1のコードを確認できませんでした。');
      }

      final secondary = await repository.verifyRecoveryCode(
        challengeId: challengeId,
        channel: 'secondary',
        code: secondaryCode,
      );
      if (!secondary.complete) {
        throw StateError('2つの復旧コード確認が完了していません。');
      }

      await repository.consumeRecoveryChallenge(
        challengeId: challengeId,
        deviceName: _deviceName(),
        deviceType: _deviceType(),
        platform: Platform.operatingSystem,
      );

      if (!mounted) return;
      _primaryCode.clear();
      _secondaryCode.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この端末を信頼済みMaster端末として登録しました')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(error);
      });
    }
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

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('rate limit')) {
      return '復旧コードの送信回数が上限に達しました。少し時間をおいて再試行してください。';
    }
    if (text.contains('expired')) {
      return '復旧コードの有効期限が切れました。もう一度送信してください。';
    }
    if (text.contains('invalid recovery code')) {
      return '復旧コードが違います。メールを確認してください。';
    }
    if (text.contains('locked')) {
      return '復旧手続きが一時ロックされました。新しいコードを送信してください。';
    }
    return text.replaceFirst('Bad state: ', '');
  }

  @override
  void dispose() {
    _secondaryPassword.dispose();
    _primaryCode.dispose();
    _secondaryCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Master 緊急復旧')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '信頼済みMaster端末を使えない場合の復旧です。'
                  '生体認証と第2パスワードを確認後、登録済みの2つの復旧メールへ別々の6桁コードを送ります。'
                  '両方のコードが正しい場合だけ、この端末を新しい信頼済み端末として登録します。',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_codesSent) ...[
              TextField(
                controller: _secondaryPassword,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '第2パスワード',
                  prefixIcon: Icon(Icons.password_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _startRecovery,
                icon: const Icon(Icons.mark_email_unread_outlined),
                label: Text(_busy ? '本人確認中...' : '本人確認して2通の復旧コードを送る'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ] else ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('復旧コードを送信しました'),
                  subtitle: Text(
                    _expiresAt == null
                        ? '2つの復旧メールを確認してください。'
                        : '有効期限: ${_expiresAt!.toLocal()}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _primaryCode,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '復旧用メール1の6桁コード',
                  prefixIcon: Icon(Icons.looks_one_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _secondaryCode,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '復旧用メール2の6桁コード',
                  prefixIcon: Icon(Icons.looks_two_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _verifyAndRegister,
                icon: const Icon(Icons.verified_user_outlined),
                label: Text(_busy ? '確認中...' : '2つのコードを確認してこの端末を登録'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _challengeId = null;
                          _expiresAt = null;
                          _primaryCode.clear();
                          _secondaryCode.clear();
                          _error = null;
                        }),
                child: const Text('コードを送り直す'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
