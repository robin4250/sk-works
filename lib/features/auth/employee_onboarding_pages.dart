import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'employee_onboarding_repository.dart';
import 'secure_onboarding_repository.dart';

class EmployeePrimaryPasswordPage extends StatefulWidget {
  const EmployeePrimaryPasswordPage({
    super.key,
    required this.name,
    required this.onCompleted,
    required this.onSignOut,
  });

  final String name;
  final VoidCallback onCompleted;
  final Future<void> Function() onSignOut;

  @override
  State<EmployeePrimaryPasswordPage> createState() =>
      _EmployeePrimaryPasswordPageState();
}

class _EmployeePrimaryPasswordPageState
    extends State<EmployeePrimaryPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _message;

  SecureOnboardingRepository? get _repository =>
      SecureOnboardingRepository.maybeCreate();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null) return;
    if (_password.text.length < 8) {
      setState(() => _message = '本パスワードは8文字以上で設定してください。');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _message = '確認用の本パスワードが一致していません。');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await repository.setEmployeePrimaryPassword(_password.text);
      widget.onCompleted();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '本パスワードを設定できませんでした: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本パスワード設定'),
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
                      const Icon(Icons.lock_reset_outlined, size: 54),
                      const SizedBox(height: 14),
                      Text(
                        '${widget.name}さん、初期ログインできました',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '初期パスワードはここで終了です。'
                        'これから使う本パスワードを2回入力してください。',
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: '本パスワード',
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
                          labelText: '本パスワード（確認）',
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
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('本パスワードを設定して次へ'),
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

class EmployeeProfileOnboardingPage extends StatefulWidget {
  const EmployeeProfileOnboardingPage({
    super.key,
    required this.name,
    required this.onSubmitted,
    required this.onSignOut,
  });

  final String name;
  final VoidCallback onSubmitted;
  final Future<void> Function() onSignOut;

  @override
  State<EmployeeProfileOnboardingPage> createState() =>
      _EmployeeProfileOnboardingPageState();
}

class _EmployeeProfileOnboardingPageState
    extends State<EmployeeProfileOnboardingPage> {
  final _address = TextEditingController();
  final _family = TextEditingController();
  final _emergencyRelation = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _emergencyAddress = TextEditingController();
  final _picker = ImagePicker();
  final _repository = EmployeeOnboardingRepository.maybeCreate();

  String _bloodType = 'A';
  XFile? _portrait;
  XFile? _myNumberFront;
  XFile? _myNumberBack;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _address.dispose();
    _family.dispose();
    _emergencyRelation.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _emergencyAddress.dispose();
    super.dispose();
  }

  Future<XFile?> _pick(String label) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('$labelをカメラで撮影'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('$labelを写真から選ぶ'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    return _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2400,
    );
  }

  bool get _complete =>
      _address.text.trim().isNotEmpty &&
      _family.text.trim().isNotEmpty &&
      _emergencyRelation.text.trim().isNotEmpty &&
      _emergencyName.text.trim().isNotEmpty &&
      _emergencyPhone.text.trim().isNotEmpty &&
      _emergencyAddress.text.trim().isNotEmpty &&
      _portrait != null &&
      _myNumberFront != null &&
      _myNumberBack != null;

  Future<void> _submit() async {
    final repository = _repository;
    if (repository == null) return;
    if (!_complete) {
      setState(() => _message = '未入力または未撮影の項目があります。');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    String? portraitPath;
    String? frontPath;
    String? backPath;
    try {
      portraitPath = await repository.uploadImage(
        kind: 'portrait',
        bytes: await _portrait!.readAsBytes(),
        filename: _portrait!.name,
      );
      frontPath = await repository.uploadImage(
        kind: 'my-number-front',
        bytes: await _myNumberFront!.readAsBytes(),
        filename: _myNumberFront!.name,
      );
      backPath = await repository.uploadImage(
        kind: 'my-number-back',
        bytes: await _myNumberBack!.readAsBytes(),
        filename: _myNumberBack!.name,
      );

      await repository.submitProfile(
        address: _address.text,
        bloodType: _bloodType,
        familyComposition: _family.text,
        emergencyRelation: _emergencyRelation.text,
        emergencyName: _emergencyName.text,
        emergencyPhone: _emergencyPhone.text,
        emergencyAddress: _emergencyAddress.text,
        portraitPath: portraitPath,
        myNumberFrontPath: frontPath,
        myNumberBackPath: backPath,
      );
      widget.onSubmitted();
    } catch (error) {
      await Future.wait([
        repository.removeImage(portraitPath),
        repository.removeImage(frontPath),
        repository.removeImage(backPath),
      ]);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '本人情報を送信できませんでした: $error';
      });
    }
  }

  Widget _imageTile({
    required String label,
    required XFile? file,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(
          file == null ? Icons.add_a_photo_outlined : Icons.check_circle,
          color: file == null ? null : Colors.green,
        ),
        title: Text(label),
        subtitle: Text(file == null ? '未登録' : '登録済み'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本人情報登録'),
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
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${widget.name}さんの本登録に必要な情報を入力してください。'
                  '入力完了後、管理者と承認担当者へ本登録通知が届きます。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: '住所 *',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _bloodType,
              decoration: const InputDecoration(
                labelText: '血液型 *',
                prefixIcon: Icon(Icons.bloodtype_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'A', child: Text('A型')),
                DropdownMenuItem(value: 'B', child: Text('B型')),
                DropdownMenuItem(value: 'O', child: Text('O型')),
                DropdownMenuItem(value: 'AB', child: Text('AB型')),
                DropdownMenuItem(value: '不明', child: Text('不明')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _bloodType = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _family,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '家族構成 *',
                hintText: '例：妻、子供2人',
                prefixIcon: Icon(Icons.family_restroom_outlined),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '緊急連絡先',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyRelation,
              decoration: const InputDecoration(labelText: '関係 *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyName,
              decoration: const InputDecoration(labelText: '名前 *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '電話番号 *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyAddress,
              decoration: const InputDecoration(labelText: '住所 *'),
            ),
            const SizedBox(height: 18),
            Text(
              '写真登録',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            _imageTile(
              label: '本人の写真 *',
              file: _portrait,
              onTap: () async {
                final file = await _pick('本人写真');
                if (file != null) setState(() => _portrait = file);
              },
            ),
            _imageTile(
              label: 'マイナンバーカード 表面 *',
              file: _myNumberFront,
              onTap: () async {
                final file = await _pick('マイナンバーカード表面');
                if (file != null) setState(() => _myNumberFront = file);
              },
            ),
            _imageTile(
              label: 'マイナンバーカード 裏面 *',
              file: _myNumberBack,
              onTap: () async {
                final file = await _pick('マイナンバーカード裏面');
                if (file != null) setState(() => _myNumberBack = file);
              },
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('本登録を申請'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmployeeApprovalWaitingPage extends StatelessWidget {
  const EmployeeApprovalWaitingPage({
    super.key,
    required this.name,
    required this.onRefresh,
    required this.onSignOut,
  });

  final String name;
  final VoidCallback onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本登録承認待ち'),
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
                      const Icon(Icons.hourglass_top_outlined, size: 58),
                      const SizedBox(height: 16),
                      Text(
                        '$nameさんの本人情報を送信しました',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '管理者と承認担当者へ通知しました。'
                        'どちらか1人が「本登録」を承認するとSKOを利用できるようになります。',
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('承認状況を更新'),
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


class EmployeeInviteInvalidPage extends StatelessWidget {
  const EmployeeInviteInvalidPage({
    super.key,
    required this.onSignOut,
  });

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('従業員登録')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_off_outlined, size: 58),
                      const SizedBox(height: 16),
                      const Text(
                        'この従業員登録は期限切れです',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '登録した会社のSKO利用者に、従業員登録をもう一度作成してもらってください。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: onSignOut,
                        child: const Text('ログアウト'),
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
