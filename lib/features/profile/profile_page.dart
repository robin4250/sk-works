import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_error_message.dart';
import '../notifications/notification_bell.dart';
import 'profile_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _repository = ProfileRepository.maybeCreate();
  final _picker = ImagePicker();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  ProfileData? _data;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'プロフィールを利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await repository.load();
      if (!mounted) return;
      _name.text = data.displayName;
      _phone.text = data.phone;
      setState(() {
        _data = data;
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

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('氏名を入力してください')),
      );
      return;
    }

    final rawPhone = _phone.text.trim();
    final currentAuthPhone = repository.currentAuthPhone ?? '';

    if (rawPhone.isEmpty && currentAuthPhone.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインIDの電話番号は空にできません')),
      );
      return;
    }

    if (rawPhone.isNotEmpty &&
        !ProfileRepository.isSupportedJapaneseMobileValue(rawPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('070 / 080 / 090から始まる携帯電話番号を入力してください')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final normalizedInput = rawPhone.isEmpty
          ? ''
          : ProfileRepository.normalizeJapanesePhoneValue(rawPhone);
      final normalizedCurrent = currentAuthPhone.isEmpty
          ? ''
          : ProfileRepository.normalizeJapanesePhoneValue(currentAuthPhone);

      if (normalizedInput.isNotEmpty && normalizedInput != normalizedCurrent) {
        final requestedPhone = await repository.requestPhoneChange(rawPhone);
        if (!mounted) return;

        final code = await _requestPhoneOtp(requestedPhone);
        if (code == null) {
          if (!mounted) return;
          setState(() => _saving = false);
          return;
        }

        await repository.verifyPhoneChange(
          phone: requestedPhone,
          code: code,
        );
      }

      await repository.save(
        displayName: _name.text,
        phone: normalizedInput,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィールを保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is Exception
          ? friendlyAuthErrorMessage(error.toString())
          : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $message')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _requestPhoneOtp(String phone) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('電話番号のSMS確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('新しい電話番号 $phone に届いた6桁コードを入力してください。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '承認コード',
                prefixIcon: Icon(Icons.sms_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await _repository?.resendPhoneChange(phone);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('SMSを再送しました')),
                );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      friendlyAuthErrorMessage(error.toString()),
                    ),
                  ),
                );
              }
            },
            child: const Text('SMS再送'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final code = controller.text.replaceAll(RegExp(r'\D'), '');
              if (code.length != 6) return;
              Navigator.of(dialogContext).pop(code);
            },
            child: const Text('確認'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _pickPhoto() async {
    final repository = _repository;
    if (repository == null) return;

    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1200,
    );
    if (photo == null) return;

    setState(() => _saving = true);
    try {
      await repository.uploadAvatar(
        bytes: await photo.readAsBytes(),
        filename: photo.name,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィール写真を更新しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写真を登録できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'プロフィール',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 58,
                              backgroundImage:
                                  data?.avatarUrl == null
                                      ? null
                                      : NetworkImage(data!.avatarUrl!),
                              child: data?.avatarUrl == null
                                  ? const Icon(Icons.person, size: 58)
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: IconButton.filled(
                                tooltip: '写真を変更',
                                onPressed: _saving ? null : _pickPhoto,
                                icon: const Icon(Icons.camera_alt_outlined),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TextField(
                                controller: _name,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: '本人氏名',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _phone,
                                enabled: !_saving,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: '電話番号',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                              ),
                              if ((data?.email ?? '').isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.email_outlined),
                                  title: const Text('メールアドレス'),
                                  subtitle: Text(data!.email),
                                ),
                              ],
                              if ((data?.companyName ?? '').isNotEmpty) ...[
                                const Divider(),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.business_outlined),
                                  title: const Text('所属会社'),
                                  subtitle: Text(data!.companyName),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? '保存中...' : 'プロフィールを保存'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
