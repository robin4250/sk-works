import 'package:flutter/material.dart';

import 'login_method_enrollment_repository.dart';

class LoginMethodEnrollmentCard extends StatefulWidget {
  const LoginMethodEnrollmentCard({super.key, this.source, this.onChanged,
    this.onPrimaryPasswordSaved});
  final LoginMethodEnrollmentSource? source;
  final VoidCallback? onChanged;
  /// Emitted only after the password update and same-account verification.
  final VoidCallback? onPrimaryPasswordSaved;
  @override
  State<LoginMethodEnrollmentCard> createState() => _LoginMethodEnrollmentCardState();
}

class _LoginMethodEnrollmentCardState extends State<LoginMethodEnrollmentCard> {
  LoginMethodEnrollmentSource? _source;
  LoginMethodEnrollmentState? _state;
  bool _busy = false, _loading = true, _awaitingPhone = false;
  bool _passwordNeedsCode = false, _passwordCodeSent = false;
  String? _message, _loadError;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? LoginMethodEnrollmentRepository.maybeCreate();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _state = null; _loadError = null; });
    try {
      final source = _source;
      if (source == null) throw StateError('login_enrollment_unavailable');
      final state = await source.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = state; _loading = false;
        _awaitingPhone = state.phoneConfirmationPending;
        _passwordNeedsCode = state.primaryPasswordCodeRequired;
        _passwordCodeSent = state.primaryPasswordCodeSent;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = null; _loading = false;
        _loadError = error is LoginEnrollmentReadFailure ? error.message
            : '登録状況と提供状態を確認できませんでした。再読み込みしてください。';
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String success,
      {bool phoneRequested = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      await action();
      if (!mounted) return;
      setState(() { _message = success; _awaitingPhone = phoneRequested; });
      await _load();
      if (mounted && !phoneRequested) widget.onChanged?.call();
    } on PrimaryPasswordReauthenticationRequired {
      if (mounted) {
        setState(() {
        _passwordNeedsCode = true;
        _message = '登録済みの連絡先への確認コードが必要です。確認コードを送信してから保存してください。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error is StateError
          ? error.message.toString() : '登録を完了できませんでした。再読み込みして確認してください。');
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<String?> _input(String title, String label, {bool password = false,
      TextInputType? keyboard, String? explanation}) async {
    return showDialog<String>(context: context, barrierDismissible: false,
      builder: (_) => _EnrollmentInputDialog(title: title, label: label,
        password: password, keyboard: keyboard, explanation: explanation));
  }

  Future<void> _password() async {
    final value = await _input('第一パスワードを設定・変更', '8文字以上のパスワード',
      password: true, explanation: '確認済みのメール・電話番号でログインするためのパスワードです。'
        '既に設定がある場合は変更します。第二パスワードとGoogle連携は保持します。');
    if (value == null || !mounted) return;
    String? nonce;
    if (_passwordNeedsCode) {
      if (!_passwordCodeSent) return;
      nonce = await _input('第一パスワードの本人確認', '届いた確認コード', keyboard: TextInputType.number);
      if (nonce == null || !mounted) return;
    }
    await _run(() async {
      await _source!.setPrimaryPassword(value, nonce: nonce);
      _passwordNeedsCode = false; _passwordCodeSent = false;
      if (mounted) widget.onPrimaryPasswordSaved?.call();
    },
      '第一パスワードの保存と同じアカウントを確認しました。第二パスワードは変更していません。');
  }

  Future<void> _phone() async {
    if (_state?.canRegisterPhone != true || _busy) return;
    final value = await _input('電話番号を登録', '携帯電話番号',
      keyboard: TextInputType.phone,
      explanation: '入力した番号へSMSの確認コードを送ります。番号の確認後、第一パスワードと組み合わせてログインできます。');
    if (value == null || !mounted) return;
    await _run(() => _source!.requestPhone(value),
      'SMSの確認コードを送信しました。まだ電話番号の登録は完了していません。', phoneRequested: true);
  }

  Future<void> _confirmPhone() async {
    if (_state?.canRegisterPhone != true || _busy) return;
    final value = await _input('SMSコードを確認', '6桁の確認コード', keyboard: TextInputType.number);
    if (value == null || !mounted) return;
    await _run(() => _source!.confirmPhone(value), '電話番号の所有確認と登録を確認しました。');
  }

  Future<void> _email() async {
    final value = await _input('メールアドレスを登録', 'メールアドレス',
      keyboard: TextInputType.emailAddress,
      explanation: '届いた確認メールの案内に従い、この画面を再読み込みしてください。確認後に第一パスワードを設定できます。');
    if (value == null || !mounted) return;
    await _run(() => _source!.requestEmail(value),
      '確認メールを送信しました。メールの確認後に最新の状態を確認してください。');
  }

  @override
  void dispose() {
    _generation++;
    if (widget.source == null) { _source?.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('ログイン方法を登録', style: TextStyle(fontWeight: FontWeight.bold)),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && state != null) ...[
          OutlinedButton(onPressed: _busy || !state.canSetPassword || (_passwordNeedsCode && !_passwordCodeSent) ? null : _password,
            child: const Text('第一パスワードを設定・変更')),
          if (_passwordNeedsCode) TextButton(onPressed: _busy ? null : () async {
            await _run(() async {
              await _source!.requestPrimaryPasswordCode();
              _passwordCodeSent = true;
            }, '登録済みの連絡先へ確認コードを送信しました。第一パスワードをもう一度入力して保存してください。');
          }, child: const Text('第一パスワードの確認コードを送信')),
          if (!state.canSetPassword) const Text('先に利用可能なメール・電話番号の確認を完了してください。'),
          OutlinedButton(onPressed: _busy || !state.canRegisterPhone || state.phoneConfirmed || _awaitingPhone ? null : _phone,
            child: Text(state.canRegisterPhone ? '電話番号を登録' : '電話番号登録（準備中）')),
          if (state.phoneConfirmed) const Text('電話番号は登録確認済みです。'),
          if (!state.phoneConfirmed && !_awaitingPhone && state.phone.isEmpty)
            const Text('電話番号は未登録です。'),
          if (!state.phoneConfirmed && !_awaitingPhone && state.phone.isNotEmpty)
            const Text('電話番号の登録確認は未完了です。'),
          if (_awaitingPhone) const Text('電話番号はSMSの確認待ちです。'),
          if (!state.canRegisterPhone) const Text('電話番号の新規登録は準備中です。SMS認証の準備が完了するまで、新しい電話番号は登録できません。'),
          if (_awaitingPhone) ...[
            FilledButton(onPressed: _busy || !state.canRegisterPhone ? null : _confirmPhone, child: const Text('SMSコードを入力')),
            TextButton(onPressed: _busy ? null : () {
              _source?.cancelPhone();
              setState(() { _awaitingPhone = false; _message = 'SMS確認を中止しました。電話番号は未確認のままです。'; });
            }, child: const Text('SMS確認を中止')),
          ],
          if (state.email.isEmpty) OutlinedButton(
            onPressed: _busy || !state.emailAvailable ? null : _email,
            child: const Text('メールアドレスを登録')),
          if (!state.emailAvailable) const Text('メールログインは提供準備中です。'),
        ],
        if (_loadError != null) Text(_loadError!, key: const ValueKey('login-enrollment-load-error')),
        if (_message != null) Text(_message!, key: const ValueKey('login-enrollment-message')),
        const ExpansionTile(title: Text('？ 登録状況の見方'), children: [
          Padding(padding: EdgeInsets.all(8), child: Text(
            '電話番号の登録状況と、SMSを送れる提供状態は別です。'
            '新規登録はSMS認証の準備が完了するまで利用できません。'
            '連絡先として保存した電話番号だけでは、ログイン用の番号所有確認にはなりません。'
            'SMS送信後はコードの確認が完了するまで登録確認済みになりません。'
            '電話番号が未登録でも、利用可能な確認済みメールがあれば第一パスワードを設定できます。'
            '取得に失敗した場合は登録状況を推測せず、再読み込みしてください。'
            'エラー案内で、ログイン状態・本人情報・提供状態のどこを確認できなかったかを表示します。')),
        ]),
        if (_busy) const LinearProgressIndicator(),
        TextButton(onPressed: _busy ? null : _load, child: const Text('登録方法を再読み込み')),
      ])));
  }
}

class _EnrollmentInputDialog extends StatefulWidget {
  const _EnrollmentInputDialog({required this.title, required this.label,
    required this.password, this.keyboard, this.explanation});
  final String title, label;
  final bool password;
  final TextInputType? keyboard;
  final String? explanation;
  @override
  State<_EnrollmentInputDialog> createState() => _EnrollmentInputDialogState();
}

class _EnrollmentInputDialogState extends State<_EnrollmentInputDialog> {
  final _value = TextEditingController(), _confirm = TextEditingController();
  @override
  void dispose() { _value.dispose(); _confirm.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final valid = widget.password ? _value.text.length >= 8 && _value.text == _confirm.text
        : _value.text.trim().isNotEmpty;
    return AlertDialog(title: Text(widget.title), content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.explanation != null) Text(widget.explanation!),
        TextField(controller: _value, obscureText: widget.password, autocorrect: false,
          enableSuggestions: !widget.password, keyboardType: widget.keyboard,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: widget.label)),
        if (widget.password) TextField(controller: _confirm, obscureText: true,
          autocorrect: false, enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: '確認のためもう一度')),
      ])), actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(onPressed: valid ? () => Navigator.pop(context, _value.text) : null,
          child: Text(widget.password ? '保存' : '確認へ')),
      ]);
  }
}
