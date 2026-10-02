// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_error_message.dart';
import '../help/manual_content.dart';
import '../help/manual_library_page.dart';
import '../notifications/notification_bell.dart';
import '../people/personnel_family_member.dart';
import 'profile_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.role,
  });

  final ManualRole role;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _repository = ProfileRepository.maybeCreate();
  final _picker = ImagePicker();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _personalSkoId = TextEditingController();
  final _personnelName = TextEditingController();
  final _personnelRole = TextEditingController();
  final _personnelPhone = TextEditingController();
  final _personnelAddress = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyRelation = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _emergencyAddress = TextEditingController();
  final _familyComposition = TextEditingController();
  List<EditableFamilyMember> _familyMembers = <EditableFamilyMember>[];
  String _bloodType = '';
  String? _workerId;

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
    _personalSkoId.dispose();
    _personnelName.dispose();
    _personnelRole.dispose();
    _personnelPhone.dispose();
    _personnelAddress.dispose();
    _emergencyName.dispose();
    _emergencyRelation.dispose();
    _emergencyPhone.dispose();
    _emergencyAddress.dispose();
    _familyComposition.dispose();
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
      final values = await Future.wait([
        repository.load(),
        repository.loadPersonnelProfile(),
      ]);
      final data = values[0] as ProfileData;
      final personnel = values[1] as Map<String, dynamic>?;
      if (!mounted) return;
      _name.text = data.displayName;
      _phone.text = ProfileRepository.domesticJapanesePhoneValue(data.phone);
      _personalSkoId.text = data.personalSkoId;
      _workerId = personnel?['worker_id']?.toString();
      _personnelName.text =
          personnel?['name']?.toString() ?? data.displayName;
      _personnelRole.text = personnel?['role']?.toString() ?? '';
      _personnelPhone.text = ProfileRepository.domesticJapanesePhoneValue(
        personnel?['phone']?.toString() ?? data.phone,
      );
      _personnelAddress.text = personnel?['address']?.toString() ?? '';
      _bloodType = personnel?['blood_type']?.toString() ?? '';
      _emergencyName.text =
          personnel?['emergency_name']?.toString() ?? '';
      _emergencyRelation.text =
          personnel?['emergency_relation']?.toString() ?? '';
      _emergencyPhone.text = ProfileRepository.domesticJapanesePhoneValue(
        personnel?['emergency_phone']?.toString() ?? '',
      );
      _emergencyAddress.text =
          personnel?['emergency_address']?.toString() ?? '';
      _familyComposition.text =
          personnel?['family_composition']?.toString() ?? '';
      final familyRaw = personnel?['family_members'];
      _familyMembers = familyRaw is List
          ? [
              for (final item in familyRaw)
                if (item is Map)
                  EditableFamilyMember.fromValue(
                    PersonnelFamilyMember.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  ),
            ]
          : <EditableFamilyMember>[];
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

  Future<void> _changePersonalSkoId() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _saving = true);
    try {
      final id = await repository.changePersonalSkoId(_personalSkoId.text);
      if (!mounted) return;
      _personalSkoId.text = id;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('個人SKO IDを変更しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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

  Future<void> _savePersonnel() async {
    final repository = _repository;
    final workerId = _workerId;
    if (repository == null || workerId == null || workerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('社員情報を確認できません')),
      );
      return;
    }
    if (_personnelName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名前を入力してください')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('社員個人情報を保存しますか？'),
        content: const Text(
          '未登録の個人情報はそのまま登録されます。登録済み情報の変更は承認者2名の承認後に反映されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定して保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final result = await repository.savePersonnelProfile(
        workerId: workerId,
        payload: {
          'name': _personnelName.text.trim(),
          'kind': 'employee',
          'blood_type': _bloodType,
          'role': _personnelRole.text.trim(),
          'phone': _personnelPhone.text.trim(),
          'address': _personnelAddress.text.trim(),
          'emergency_name': _emergencyName.text.trim(),
          'emergency_relation': _emergencyRelation.text.trim(),
          'emergency_phone': _emergencyPhone.text.trim(),
          'emergency_address': _emergencyAddress.text.trim(),
          'family_composition': _familyComposition.text.trim(),
          'family_members': [
            for (final member in _familyMembers) member.toValue().toJson(),
          ],
        },
      );
      if (!mounted) return;
      final pending = result['requires_approval'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending
                ? '変更申請を送信しました。2名の承認後に反映されます。'
                : '社員個人情報を保存しました',
          ),
        ),
      );
      if (!pending) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('社員個人情報を保存できませんでした: $error')),
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

  Future<void> _openGoogleMap(String address) async {
    final query = address.trim();
    if (query.isEmpty) return;
    final uri = Uri.https(
      'www.google.com',
      '/maps/search/',
      {'api': '1', 'query': query},
    );
    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Googleマップを開けませんでした')),
      );
    }
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

  Widget _profileFamilyMemberCard(int index) {
    final member = _familyMembers[index];
    final birth = member.birthDate;
    final age = member.toValue().ageOn();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: member.name,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '氏名',
                    ),
                    onChanged: (value) => member.name = value,
                  ),
                ),
                IconButton(
                  tooltip: '家族情報を削除',
                  onPressed: _saving
                      ? null
                      : () => setState(
                            () => _familyMembers.removeAt(index),
                          ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: member.relation,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: '続柄（夫・妻・子・扶養家族など）',
              ),
              onChanged: (value) => member.relation = value,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cake_outlined),
              title: const Text('誕生日'),
              subtitle: Text(
                birth == null
                    ? '未登録'
                    : birth.year.toString() +
                        '/' +
                        birth.month.toString().padLeft(2, '0') +
                        '/' +
                        birth.day.toString().padLeft(2, '0') +
                        (age == null
                            ? ''
                            : '　現在 ' + age.toString() + '歳'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final selected = await showDatePicker(
                        context: context,
                        initialDate:
                            birth ?? DateTime(now.year - 30),
                        firstDate: DateTime(1900),
                        lastDate: now,
                      );
                      if (selected == null || !mounted) return;
                      setState(() => member.birthDate = selected);
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('扶養家族として登録'),
              subtitle: const Text(
                '社会保険等で扶養対象として扱う場合にON',
              ),
              value: member.isDependent,
              onChanged: _saving
                  ? null
                  : (value) => setState(
                        () => member.isDependent = value,
                      ),
            ),
          ],
        ),
      ),
    );
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
                              const Divider(),
                              TextField(
                                controller: _personalSkoId,
                                enabled: !_saving,
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: '個人SKO ID',
                                  helperText:
                                      'プロフィールから変更できます。SKO-に続けて英数字4〜20文字。',
                                  prefixIcon:
                                      const Icon(Icons.alternate_email),
                                  suffixIcon: IconButton(
                                    tooltip: '個人SKO IDを変更',
                                    onPressed:
                                        _saving ? null : _changePersonalSkoId,
                                    icon: const Icon(Icons.check_circle_outline),
                                  ),
                                ),
                              ),
                              if ((data?.companyId ?? '').isNotEmpty) ...[
                                const Divider(),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.badge_outlined),
                                  title: const Text('SKO会社ID'),
                                  subtitle: SelectableText(data!.companyId),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '社員個人情報',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '未登録は直接保存できます。登録済み情報の変更は承認者2名の承認後に反映されます。',
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _personnelName,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: '名前',
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: _bloodType.isEmpty ? null : _bloodType,
                                decoration: const InputDecoration(
                                  labelText: '血液型',
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'A', child: Text('A型')),
                                  DropdownMenuItem(value: 'B', child: Text('B型')),
                                  DropdownMenuItem(value: 'O', child: Text('O型')),
                                  DropdownMenuItem(value: 'AB', child: Text('AB型')),
                                  DropdownMenuItem(value: '不明', child: Text('不明')),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                        setState(() => _bloodType = value ?? ''),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _personnelRole,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: '職種',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _personnelPhone,
                                enabled: !_saving,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: '社員台帳の電話番号',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _personnelAddress,
                                enabled: !_saving,
                                decoration: InputDecoration(
                                  labelText: '住所',
                                  suffixIcon: IconButton(
                                    tooltip: 'Googleマップで開く',
                                    onPressed:
                                        _personnelAddress.text.trim().isEmpty
                                            ? null
                                            : () => _openGoogleMap(
                                                  _personnelAddress.text,
                                                ),
                                    icon: const Icon(Icons.map_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '緊急連絡先',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _emergencyName,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: '氏名',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _emergencyRelation,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: '続柄',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _emergencyPhone,
                                enabled: !_saving,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: '電話番号',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _emergencyAddress,
                                enabled: !_saving,
                                decoration: InputDecoration(
                                  labelText: '住所',
                                  suffixIcon: IconButton(
                                    tooltip: 'Googleマップで開く',
                                    onPressed:
                                        _emergencyAddress.text.trim().isEmpty
                                            ? null
                                            : () => _openGoogleMap(
                                                  _emergencyAddress.text,
                                                ),
                                    icon: const Icon(Icons.map_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                '家族・扶養情報',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '社員一覧には表示しません。社会保険等の本人手続きで使う個別情報です。',
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _familyComposition,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: '家族構成',
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (var i = 0;
                                  i < _familyMembers.length;
                                  i++)
                                _profileFamilyMemberCard(i),
                              OutlinedButton.icon(
                                onPressed: _saving
                                    ? null
                                    : () => setState(
                                          () => _familyMembers
                                              .add(EditableFamilyMember()),
                                        ),
                                icon: const Icon(
                                  Icons.person_add_alt_1_outlined,
                                ),
                                label: const Text(
                                  '配偶者・子供・扶養家族を追加',
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: _saving ? null : _savePersonnel,
                                icon: const Icon(Icons.badge_outlined),
                                label: const Text('社員個人情報を保存'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.menu_book_outlined),
                          ),
                          title: const Text(
                            '使い方・説明書',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${ManualContent.roleLabel(widget.role)}用説明書とSKOパンフレットを閲覧・印刷できます',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ManualLibraryPage(role: widget.role),
                            ),
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
