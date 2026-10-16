import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../international/language_controller.dart';
import 'employee_onboarding_repository.dart';
import 'secure_onboarding_repository.dart';

Future<void> _showOnboardingHelp(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(SkoLanguageController.tr('閉じる')),
        ),
      ],
    ),
  );
}

Widget _onboardingHelpButton(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return IconButton(
    tooltip: SkoLanguageController.tr('この画面の使い方'),
    icon: const Icon(Icons.help_outline),
    onPressed: () => _showOnboardingHelp(
      context,
      title: title,
      message: message,
    ),
  );
}

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
      setState(() => _message = SkoLanguageController.tr('本パスワードは8文字以上で設定してください。'));
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _message = SkoLanguageController.tr('確認用の本パスワードが一致していません。'));
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
        _message = '${SkoLanguageController.tr('本パスワードを設定できませんでした')}: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('本パスワード設定')),
        actions: [
          _onboardingHelpButton(
            context,
            title: SkoLanguageController.tr('本パスワード設定'),
            message: SkoLanguageController.tr(
              '初期パスワードでのログイン後、これから使う本パスワードを8文字以上で2回入力します。',
            ),
          ),
          TextButton(
            onPressed: _busy ? null : widget.onSignOut,
            child: Text(SkoLanguageController.tr('ログアウト')),
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
                        SkoLanguageController.isEnglish
                            ? 'Welcome, ${widget.name}. Initial sign-in is complete.'
                            : '${widget.name}さん、初期ログインできました',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        SkoLanguageController.tr(
                          '初期パスワードはここで終了です。これから使う本パスワードを2回入力してください。',
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: SkoLanguageController.tr('本パスワード'),
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
                          labelText: SkoLanguageController.tr('本パスワード（確認）'),
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
                        label: Text(SkoLanguageController.tr('本パスワードを設定して次へ')),
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
    this.repository,
    this.imagePicker,
  });

  final String name;
  final VoidCallback onSubmitted;
  final Future<void> Function() onSignOut;
  final EmployeeOnboardingRepository? repository;
  final Future<XFile?> Function(ImageSource source)? imagePicker;

  @override
  State<EmployeeProfileOnboardingPage> createState() =>
      _EmployeeProfileOnboardingPageState();
}

class _EmployeeProfileOnboardingPageState
    extends State<EmployeeProfileOnboardingPage> with WidgetsBindingObserver {
  final _address = TextEditingController();
  final _family = TextEditingController();
  final _emergencyRelation = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _emergencyAddress = TextEditingController();
  final _picker = ImagePicker();
  late final EmployeeOnboardingRepository? _repository;
  StreamSubscription<dynamic>? _authSubscription;
  String? _actorId;
  bool _identityChanged = false;
  bool _foreground = true;
  int _epoch = 0;
  EmployeeOnboardingPhotoCapability? _photoCapability;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository = widget.repository ?? EmployeeOnboardingRepository.maybeCreate();
    _actorId = _repository?.currentUserId;
    _authSubscription = _repository?.authChanges.listen((state) {
      if (state.session?.user.id != _actorId) {
        _identityChanged = true;
        _epoch++;
        if (mounted) setState(() => _message = 'ログイン状態が変わったため送信を中断しました。入力内容は保持しています。');
      }
    });
    unawaited(_loadPhotoCapability());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _epoch++;
    } else if (!_busy && !_identityChanged) {
      unawaited(_loadPhotoCapability());
    }
  }

  EmployeeOnboardingRequest _request() {
    final epoch = _epoch;
    return _repository!.beginRequest(() => mounted && _foreground && !_identityChanged &&
        _actorId != null && _repository!.currentUserId == _actorId && _epoch == epoch);
  }

  Future<void> _loadPhotoCapability() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final request = _request();
      final capability = await repository.loadPhotoCapability(request: request);
      request.check();
      setState(() => _photoCapability = capability);
    } catch (_) {
      if (mounted) setState(() => _message = '写真登録の状態を確認できませんでした。入力内容を保持しています。送信時に再確認します。');
    }
  }

  String _bloodType = 'A';
  XFile? _portrait;
  XFile? _myNumberFront;
  XFile? _myNumberBack;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSubscription?.cancel());
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
              title: Text(SkoLanguageController.isEnglish ? 'Take $label with camera' : '$labelをカメラで撮影'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(SkoLanguageController.isEnglish ? 'Choose $label from photos' : '$labelを写真から選ぶ'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    if (widget.imagePicker != null) return widget.imagePicker!(source);
    return _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2400,
    );
  }

  bool get _textComplete =>
      _address.text.trim().isNotEmpty &&
      _family.text.trim().isNotEmpty &&
      _emergencyRelation.text.trim().isNotEmpty &&
      _emergencyName.text.trim().isNotEmpty &&
      _emergencyPhone.text.trim().isNotEmpty &&
      _emergencyAddress.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final repository = _repository;
    if (repository == null || _busy) return;
    if (!_textComplete) {
      setState(() => _message = SkoLanguageController.tr('未入力または未撮影の項目があります。'));
      return;
    }
    final fields = <String, String>{
      'address': _address.text, 'blood_type': _bloodType,
      'family_composition': _family.text, 'emergency_relation': _emergencyRelation.text,
      'emergency_name': _emergencyName.text, 'emergency_phone': _emergencyPhone.text,
      'emergency_address': _emergencyAddress.text,
    };
    final portrait = _portrait, front = _myNumberFront, back = _myNumberBack;
    setState(() { _busy = true; _message = null; });
    try {
      final request = _request();
      final capability = await repository.loadPhotoCapability(request: request);
      request.check();
      setState(() => _photoCapability = capability);
      final omitPhotos = capability?.photoUploadAllowed == false;
      String? portraitPath, frontPath, backPath;
      Future<String> upload(String kind, XFile file) async {
        final bytes = await file.readAsBytes();
        request.check();
        return repository.uploadImage(kind: kind, bytes: bytes,
            filename: file.name, request: request);
      }
      if (!omitPhotos) {
        if (portrait == null || front == null || back == null) {
          throw StateError('未入力または未撮影の項目があります。');
        }
        portraitPath = await upload('portrait', portrait);
        request.check();
        frontPath = await upload('my-number-front', front);
        request.check();
        backPath = await upload('my-number-back', back);
        request.check();
      }
      // Recheck immediately before dispatch. Never silently switch routes mid-submit.
      final confirmed = await repository.loadPhotoCapability(request: request);
      request.check();
      if ((confirmed?.photoUploadAllowed == false) != omitPhotos) {
        throw StateError('写真登録の状態が変わりました。入力内容を確認して再度お試しください。');
      }
      if (omitPhotos) {
        await repository.submitProfileWithoutPhotos(fields: fields, request: request);
      } else {
        await repository.submitProfile(
          address: fields['address']!, bloodType: fields['blood_type']!,
          familyComposition: fields['family_composition']!,
          emergencyRelation: fields['emergency_relation']!,
          emergencyName: fields['emergency_name']!, emergencyPhone: fields['emergency_phone']!,
          emergencyAddress: fields['emergency_address']!,
          portraitPath: portraitPath!, myNumberFrontPath: frontPath!,
          myNumberBackPath: backPath!, request: request,
        );
      }
      request.check();
      widget.onSubmitted();
    } catch (_) {
      // A failed response may follow a committed save. Never delete possibly-linked
      // uploads or act as another account; keep text and photo selections for review.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '本人情報を送信できませんでした。入力内容は保持しています。ログイン状態と写真登録の状態を確認して再度お試しください。';
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
        subtitle: Text(file == null ? SkoLanguageController.tr('未登録') : SkoLanguageController.tr('登録済み')),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('本人情報登録')),
        actions: [
          _onboardingHelpButton(
            context,
            title: SkoLanguageController.tr('本人情報登録'),
            message: SkoLanguageController.tr(
              '本登録に必要な本人情報と写真を登録します。必須項目をすべて入力・撮影すると本登録申請を送れます。',
            ),
          ),
          TextButton(
            onPressed: _busy ? null : widget.onSignOut,
            child: Text(SkoLanguageController.tr('ログアウト')),
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
                  SkoLanguageController.isEnglish
                      ? 'Enter the information required to complete ${widget.name}\'s registration. After submission, admins and approvers will be notified.'
                      : '${widget.name}さんの本登録に必要な情報を入力してください。入力完了後、管理者と承認担当者へ本登録通知が届きます。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                labelText: '${SkoLanguageController.tr('住所')} *',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _bloodType,
              decoration: InputDecoration(
                labelText: '${SkoLanguageController.tr('血液型')} *',
                prefixIcon: Icon(Icons.bloodtype_outlined),
              ),
              items: [
                DropdownMenuItem(value: 'A', child: Text(SkoLanguageController.isEnglish ? 'A' : 'A型')),
                DropdownMenuItem(value: 'B', child: Text(SkoLanguageController.isEnglish ? 'B' : 'B型')),
                DropdownMenuItem(value: 'O', child: Text(SkoLanguageController.isEnglish ? 'O' : 'O型')),
                DropdownMenuItem(value: 'AB', child: Text(SkoLanguageController.isEnglish ? 'AB' : 'AB型')),
                DropdownMenuItem(value: '不明', child: Text(SkoLanguageController.tr('不明'))),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _bloodType = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _family,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: '${SkoLanguageController.tr('家族構成')} *',
                hintText: SkoLanguageController.tr('例：妻、子供2人'),
                prefixIcon: Icon(Icons.family_restroom_outlined),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              SkoLanguageController.tr('緊急連絡先'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyRelation,
              decoration: InputDecoration(labelText: '${SkoLanguageController.tr('続柄')} *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyName,
              decoration: InputDecoration(labelText: '${SkoLanguageController.tr('緊急連絡先氏名')} *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyPhone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: '${SkoLanguageController.tr('電話番号')} *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emergencyAddress,
              decoration: InputDecoration(labelText: '${SkoLanguageController.tr('緊急住所')} *'),
            ),
            const SizedBox(height: 18),
            Text(
              SkoLanguageController.tr('写真登録'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            if (_photoCapability?.photoUploadAllowed == false)
              Text(_photoCapability!.hasExistingImages
                  ? '写真の新規送信は停止中です。登録済み写真を保持し、本人情報のみ申請します。選択中の写真は送信されません。'
                  : '写真の新規送信は停止中です。写真の選択なしで本人情報を申請できます。選択中の写真は送信されません。'),
            _imageTile(
              label: '${SkoLanguageController.tr('本人の写真')} *',
              file: _portrait,
              onTap: () async {
                final file = await _pick(SkoLanguageController.tr('本人写真'));
                if (mounted && !_identityChanged && file != null) setState(() => _portrait = file);
              },
            ),
            _imageTile(
              label: '${SkoLanguageController.tr('マイナンバーカード 表面')} *',
              file: _myNumberFront,
              onTap: () async {
                final file = await _pick(SkoLanguageController.tr('マイナンバーカード表面'));
                if (mounted && !_identityChanged && file != null) setState(() => _myNumberFront = file);
              },
            ),
            _imageTile(
              label: '${SkoLanguageController.tr('マイナンバーカード 裏面')} *',
              file: _myNumberBack,
              onTap: () async {
                final file = await _pick(SkoLanguageController.tr('マイナンバーカード裏面'));
                if (mounted && !_identityChanged && file != null) setState(() => _myNumberBack = file);
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
              label: Text(SkoLanguageController.tr('本登録を申請')),
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
        title: Text(SkoLanguageController.tr('本登録承認待ち')),
        actions: [
          _onboardingHelpButton(
            context,
            title: SkoLanguageController.tr('本登録承認待ち'),
            message: SkoLanguageController.tr(
              '本人情報は送信済みです。管理者または承認担当者が承認するとSKOを利用できるようになります。',
            ),
          ),
          TextButton(
            onPressed: onSignOut,
            child: Text(SkoLanguageController.tr('ログアウト')),
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
                        SkoLanguageController.isEnglish
                            ? '$name: registration information submitted'
                            : '$nameさんの本人情報を送信しました',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        SkoLanguageController.tr(
                          '管理者と承認担当者へ通知しました。どちらか1人が本登録を承認するとSKOを利用できるようになります。',
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(SkoLanguageController.tr('承認状況を更新')),
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
      appBar: AppBar(title: Text(SkoLanguageController.tr('従業員登録'))),
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
                      Text(
                        SkoLanguageController.tr('この従業員登録は期限切れです'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        SkoLanguageController.tr(
                          '登録した会社のSKO利用者に、従業員登録をもう一度作成してもらってください。',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: onSignOut,
                        child: Text(SkoLanguageController.tr('ログアウト')),
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
