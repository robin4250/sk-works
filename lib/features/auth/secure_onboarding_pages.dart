import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../branding/product_brand.dart';
import 'auth_error_message.dart';
import 'secure_onboarding_repository.dart';

class SecureAuthPage extends StatefulWidget {
  const SecureAuthPage({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<SecureAuthPage> createState() => _SecureAuthPageState();
}

class _SecureAuthPageState extends State<SecureAuthPage> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _otp = TextEditingController();

  bool _registerMode = false;
  bool _passwordResetMode = false;
  bool _passwordResetVerified = false;
  bool _awaitingSms = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _message;

  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final repository = _repository;
    if (repository == null) return;

    if (_awaitingSms) {
      final code = _otp.text.replaceAll(RegExp(r'\D'), '');
      if (code.length < 6) {
        setState(() => _message = 'SMSで届いた承認コードを入力してください。');
        return;
      }
      await _run(() async {
        if (_passwordResetMode) {
          await repository.verifyPasswordResetSms(
            phone: _phone.text,
            code: code,
          );
          if (!mounted) return;
          setState(() {
            _awaitingSms = false;
            _passwordResetVerified = true;
            _otp.clear();
            _password.clear();
            _passwordConfirm.clear();
            _message = '本人確認が完了しました。新しい本パスワードを設定してください。';
          });
        } else {
          await repository.verifySmsCode(phone: _phone.text, code: code);
          widget.onAuthenticated();
        }
      });
      return;
    }

    if (_passwordResetMode && _passwordResetVerified) {
      if (_password.text.length < 8) {
        setState(() => _message = '8文字以上の新しい本パスワードを入力してください。');
        return;
      }
      if (_password.text != _passwordConfirm.text) {
        setState(() => _message = '確認用パスワードが一致していません。');
        return;
      }
      await _run(() async {
        await repository.updatePrimaryPassword(_password.text);
        widget.onAuthenticated();
      });
      return;
    }

    if (_passwordResetMode) {
      if (!SecureOnboardingRepository.isSupportedJapaneseMobileValue(_phone.text)) {
        setState(() => _message = '070 / 080 / 090から始まる携帯電話番号を入力してください。');
        return;
      }
      await _run(() async {
        await repository.requestPasswordResetSms(phone: _phone.text);
        if (!mounted) return;
        setState(() {
          _awaitingSms = true;
          _message = 'SMSで本人確認コードを送信しました。';
        });
      });
      return;
    }

    if (!SecureOnboardingRepository.isSupportedJapaneseMobileValue(_phone.text)) {
      setState(() => _message = '070 / 080 / 090から始まる携帯電話番号を入力してください。');
      return;
    }

    if (_password.text.length < 8) {
      setState(() => _message = '8文字以上のパスワードを入力してください。');
      return;
    }

    if (_registerMode && _password.text != _passwordConfirm.text) {
      setState(() => _message = '確認用パスワードが一致していません。');
      return;
    }

    await _run(() async {
      if (_registerMode) {
        final signedIn = await repository.registerAdmin(
          phone: _phone.text,
          password: _password.text,
        );
        if (!mounted) return;
        if (signedIn) {
          widget.onAuthenticated();
        } else {
          setState(() {
            _awaitingSms = true;
            _message = 'SMSで承認コードを送信しました。';
          });
        }
      } else {
        await repository.signInWithPhone(
          phone: _phone.text,
          password: _password.text,
        );
        widget.onAuthenticated();
      }
    });
  }

  Future<void> _resendSms() async {
    final repository = _repository;
    if (repository == null) return;

    await _run(() async {
      if (_passwordResetMode) {
        await repository.requestPasswordResetSms(phone: _phone.text);
      } else {
        await repository.resendSmsCode(phone: _phone.text);
      }
      if (!mounted) return;
      setState(() => _message = 'SMSを再送しました。最新の6桁コードを入力してください。');
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = friendlyAuthErrorMessage(error.message));
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '処理に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(ProductBrand.displayName)),
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
                      Text(
                        _awaitingSms
                            ? (_passwordResetMode ? '本人確認コード' : '承認コード')
                            : _passwordResetVerified
                                ? '新しい本パスワード'
                                : _passwordResetMode
                                    ? '本パスワード再設定'
                                    : _registerMode
                                        ? '管理者の初回登録'
                                        : 'ログイン',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _awaitingSms
                            ? 'SMSで届いた6桁のコードを入力してください。'
                            : _passwordResetVerified
                                ? 'SMS本人確認済みです。新しい本パスワードを8文字以上で設定してください。'
                                : _passwordResetMode
                                    ? '登録済みの携帯電話番号へ本人確認SMSを送信します。'
                                    : _registerMode
                                        ? '携帯電話番号をIDとして登録します。'
                                        : '登録した携帯電話番号とパスワードでログインします。',
                      ),
                      const SizedBox(height: 20),
                      if (_awaitingSms) ...[
                        TextField(
                          controller: _otp,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: '承認コード',
                            prefixIcon: Icon(Icons.sms_outlined),
                          ),
                          onSubmitted: (_) => _busy ? null : _submit(),
                        ),
                      ] else if (_passwordResetVerified) ...[
                        _PasswordField(
                          controller: _password,
                          label: '新しい本パスワード',
                          obscure: _obscurePassword,
                          onToggle: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        const SizedBox(height: 12),
                        _PasswordField(
                          controller: _passwordConfirm,
                          label: '新しい本パスワード（確認）',
                          obscure: _obscureConfirm,
                          onToggle: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                          onSubmitted: (_) => _busy ? null : _submit(),
                        ),
                      ] else ...[
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(
                            labelText: '携帯電話番号（ID）',
                            hintText: '09012345678',
                            prefixIcon: Icon(Icons.phone_iphone_outlined),
                          ),
                        ),
                        if (!_passwordResetMode) ...[
                          const SizedBox(height: 12),
                          _PasswordField(
                          controller: _password,
                          label: _registerMode ? '本パスワード' : 'パスワード',
                          obscure: _obscurePassword,
                          onToggle: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                          onSubmitted: (_) =>
                              _registerMode || _busy ? null : _submit(),
                        ),
                        ],
                        if (_registerMode && !_passwordResetMode) ...[
                          const SizedBox(height: 12),
                          _PasswordField(
                            controller: _passwordConfirm,
                            label: '本パスワード（確認）',
                            obscure: _obscureConfirm,
                            onToggle: () =>
                                setState(() => _obscureConfirm = !_obscureConfirm),
                            onSubmitted: (_) => _busy ? null : _submit(),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '8文字以上で設定してください。次の画面で重要情報用の別パスワードも設定します。',
                          ),
                        ],
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: _awaitingSms
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _awaitingSms
                                    ? Icons.verified_outlined
                                    : _registerMode
                                        ? Icons.person_add_alt_1
                                        : Icons.login,
                              ),
                        label: Text(
                          _awaitingSms
                              ? '承認する'
                              : _passwordResetVerified
                                  ? '新しい本パスワードを設定'
                                  : _passwordResetMode
                                      ? '本人確認SMSを送信'
                                      : _registerMode
                                          ? '登録してSMS認証へ'
                                          : 'ログイン',
                        ),
                      ),
                      if (_awaitingSms) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _busy ? null : _resendSms,
                          icon: const Icon(Icons.refresh),
                          label: const Text('SMSを再送'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _awaitingSms = false;
                                    _message = null;
                                  }),
                          child: const Text('電話番号を修正'),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        if (!_passwordResetMode)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _registerMode = !_registerMode;
                                      _message = null;
                                    }),
                            child: Text(
                              _registerMode
                                  ? 'すでに登録済みの方'
                                  : '管理者として初めて登録する',
                            ),
                          ),
                        if (!_registerMode)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    if (_passwordResetVerified) {
                                      await _repository?.signOut();
                                    }
                                    if (!mounted) return;
                                    setState(() {
                                      _passwordResetMode = !_passwordResetMode;
                                      _passwordResetVerified = false;
                                      _awaitingSms = false;
                                      _otp.clear();
                                      _password.clear();
                                      _passwordConfirm.clear();
                                      _message = null;
                                    });
                                  },
                            child: Text(
                              _passwordResetMode
                                  ? '通常ログインへ戻る'
                                  : '本パスワードを忘れた方',
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

class SecondaryPasswordSetupPage extends StatefulWidget {
  const SecondaryPasswordSetupPage({
    super.key,
    required this.onContinue,
    required this.onDeferred,
    required this.onSignOut,
  });

  final VoidCallback onContinue;
  final VoidCallback onDeferred;
  final Future<void> Function() onSignOut;

  @override
  State<SecondaryPasswordSetupPage> createState() =>
      _SecondaryPasswordSetupPageState();
}

class _SecondaryPasswordSetupPageState
    extends State<SecondaryPasswordSetupPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _localAuth = LocalAuthentication();

  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  bool _saved = false;
  bool _biometricSupported = false;
  bool _useBiometric = false;
  String? _message;

  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!mounted) return;
      setState(() => _biometricSupported = supported && canCheck);
    } catch (_) {
      // Password-only setup remains available.
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _message = '重要情報用パスワードは8文字以上で設定してください。');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _message = '確認用パスワードが一致していません。');
      return;
    }

    final repository = _repository;
    if (repository == null) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      if (_useBiometric) {
        final ok = await _localAuth.authenticate(
          localizedReason: '重要情報のロック解除に生体認証を使用します',
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

      final userId = repository.currentUser?.id;
      if (userId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(
          'sko_secondary_biometric_enabled_$userId',
          _useBiometric,
        );
      }

      if (!mounted) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '設定できませんでした: $error';
      });
    }
  }

  Future<void> _deferCompanySetup() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _busy = true);
    try {
      await repository.setCompanySetupDeferred(true);
      widget.onDeferred();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '後で登録の設定に失敗しました: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_saved) {
      return Scaffold(
        appBar: AppBar(title: const Text('アプリ案内')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.verified_user_outlined, size: 56),
                        const SizedBox(height: 16),
                        Text(
                          'セキュリティ設定が完了しました',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '請求書・管理者用現場データなどの重要情報を開くときは、通常ログインとは別の追加認証を使用します。',
                        ),
                        const SizedBox(height: 16),
                        const _InfoTile(
                          icon: Icons.lock_outline,
                          title: '通常ログイン',
                          body: '携帯電話番号＋本パスワード',
                        ),
                        const _InfoTile(
                          icon: Icons.shield_outlined,
                          title: '重要情報',
                          body: '第2パスワード。対応端末ではFace ID / Touch IDも利用できます。',
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _busy ? null : widget.onContinue,
                          icon: const Icon(Icons.business_outlined),
                          label: const Text('ユーザー・会社情報登録へ'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _busy ? null : _deferCompanySetup,
                          child: const Text('会社情報は後で登録する'),
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
      appBar: AppBar(
        title: const Text('重要情報用パスワード'),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onSignOut,
            child: const Text('ログアウト'),
          ),
        ],
      ),
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
                      const Icon(Icons.admin_panel_settings_outlined, size: 52),
                      const SizedBox(height: 14),
                      Text(
                        '第2パスワードを設定',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '請求書・給与・管理者用現場データなどを守るため、通常ログインとは別のパスワードを設定します。',
                      ),
                      const SizedBox(height: 20),
                      _PasswordField(
                        controller: _password,
                        label: '重要情報用パスワード',
                        obscure: _obscure,
                        onToggle: () => setState(() => _obscure = !_obscure),
                      ),
                      const SizedBox(height: 12),
                      _PasswordField(
                        controller: _confirm,
                        label: '重要情報用パスワード（確認）',
                        obscure: _obscureConfirm,
                        onToggle: () => setState(
                          () => _obscureConfirm = !_obscureConfirm,
                        ),
                        onSubmitted: (_) => _busy ? null : _save(),
                      ),
                      if (_biometricSupported) ...[
                        const SizedBox(height: 14),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Face ID / Touch IDも使用する'),
                          subtitle: const Text(
                            '端末側の生体認証を重要情報のロック解除に利用します。',
                          ),
                          value: _useBiometric,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _useBiometric = value),
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
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.lock_reset_outlined),
                        label: const Text('第2パスワードを登録'),
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
}

class CompanyProfileSetupPage extends StatefulWidget {
  const CompanyProfileSetupPage({
    super.key,
    required this.onCompleted,
    required this.onDeferred,
    required this.onSignOut,
  });

  final VoidCallback onCompleted;
  final VoidCallback onDeferred;
  final Future<void> Function() onSignOut;

  @override
  State<CompanyProfileSetupPage> createState() =>
      _CompanyProfileSetupPageState();
}

class _CompanyProfileSetupPageState extends State<CompanyProfileSetupPage> {
  final _displayName = TextEditingController();
  final _companyName = TextEditingController();
  final _postalCode = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _fax = TextEditingController();
  final _email = TextEditingController();
  final _bankName = TextEditingController();
  final _bankBranch = TextEditingController();
  final _bankAccountNumber = TextEditingController();
  final _bankAccountHolder = TextEditingController();

  String _accountType = '普通';
  bool _busy = false;
  String? _message;

  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();

  @override
  void initState() {
    super.initState();
    final user = _repository?.currentUser;
    _phone.text = user?.phone ?? '';
    _email.text = user?.email ?? '';
  }

  @override
  void dispose() {
    _displayName.dispose();
    _companyName.dispose();
    _postalCode.dispose();
    _address.dispose();
    _phone.dispose();
    _fax.dispose();
    _email.dispose();
    _bankName.dispose();
    _bankBranch.dispose();
    _bankAccountNumber.dispose();
    _bankAccountHolder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_displayName.text.trim().isEmpty || _companyName.text.trim().isEmpty) {
      setState(() => _message = '本人氏名と会社名（屋号）は入力してください。');
      return;
    }

    final repository = _repository;
    if (repository == null) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await repository.completeCompanyProfile(
        displayName: _displayName.text,
        companyName: _companyName.text,
        postalCode: _postalCode.text,
        address: _address.text,
        phone: _phone.text,
        fax: _fax.text,
        email: _email.text,
        bankName: _bankName.text,
        bankBranch: _bankBranch.text,
        bankAccountType: _accountType,
        bankAccountNumber: _bankAccountNumber.text,
        bankAccountHolder: _bankAccountHolder.text,
      );
      await repository.setCompanySetupDeferred(false);
      widget.onCompleted();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '登録できませんでした: $error';
      });
    }
  }

  Future<void> _defer() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _busy = true);
    try {
      await repository.setCompanySetupDeferred(true);
      widget.onDeferred();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '後で登録の設定に失敗しました: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザー・会社登録'),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onSignOut,
            child: const Text('ログアウト'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '基本情報',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '請求書や会社情報に使用します。会社情報は後から登録・修正できます。',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: '本人情報',
              children: [
                TextField(
                  controller: _displayName,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '本人氏名',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: '会社情報（請求書に記載）',
              children: [
                TextField(
                  controller: _companyName,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '会社名（屋号）',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _postalCode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '郵便番号',
                    prefixIcon: Icon(Icons.local_post_office_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _address,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '住所',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '電話番号',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _fax,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'FAX（任意）',
                    prefixIcon: Icon(Icons.print_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: '振込先金融機関（請求書に記載）',
              children: [
                TextField(
                  controller: _bankName,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '銀行・郵便局名',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankBranch,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '支店名',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _accountType,
                  decoration: const InputDecoration(
                    labelText: '預金種別',
                  ),
                  items: const [
                    DropdownMenuItem(value: '普通', child: Text('普通')),
                    DropdownMenuItem(value: '当座', child: Text('当座')),
                    DropdownMenuItem(value: '貯蓄', child: Text('貯蓄')),
                    DropdownMenuItem(value: 'その他', child: Text('その他')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) =>
                          setState(() => _accountType = value ?? '普通'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankAccountNumber,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '口座番号',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankAccountHolder,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '口座名義（カナ）',
                  ),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(_busy ? '登録中...' : '登録してSKOを開始'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _defer,
              child: const Text('会社情報は後で登録する'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class DeferredCompanySetupPage extends StatelessWidget {
  const DeferredCompanySetupPage({
    super.key,
    required this.onResume,
    required this.onSignOut,
  });

  final VoidCallback onResume;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(ProductBrand.displayName),
        actions: [
          TextButton(
            onPressed: onSignOut,
            child: const Text('ログアウト'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.business_center_outlined, size: 54),
                      const SizedBox(height: 14),
                      Text(
                        'ログインは完了しています',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '会社情報を登録すると、現場・出勤・請求書などの会社機能を利用できます。',
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onResume,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('ユーザー・会社登録を続ける'),
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
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofillHints: const [AutofillHints.password],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: obscure ? '表示' : '非表示',
          onPressed: onToggle,
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(body),
    );
  }
}
