import 'package:flutter/material.dart';

import 'people_cloud_repository.dart';
import 'people_page.dart';
import 'personnel_family_member.dart';

class EmployeePersonnelEditPage extends StatefulWidget {
  const EmployeePersonnelEditPage({
    super.key,
    required this.record,
  });

  final PersonRecord record;

  @override
  State<EmployeePersonnelEditPage> createState() =>
      _EmployeePersonnelEditPageState();
}

class _EmployeePersonnelEditPageState
    extends State<EmployeePersonnelEditPage> {
  final _repository = PeopleCloudRepository.maybeCreate();

  late final TextEditingController _name;
  late final TextEditingController _role;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyRelation;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _emergencyAddress;
  late final TextEditingController _familyComposition;
  late List<EditableFamilyMember> _familyMembers;
  late String _bloodType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _name = TextEditingController(text: record.name);
    _role = TextEditingController(text: record.role);
    _phone = TextEditingController(text: record.phone);
    _address = TextEditingController(text: record.address);
    _emergencyName = TextEditingController(text: record.emergencyName);
    _emergencyRelation =
        TextEditingController(text: record.emergencyRelation);
    _emergencyPhone = TextEditingController(text: record.emergencyPhone);
    _emergencyAddress = TextEditingController(text: record.emergencyAddress);
    _familyComposition =
        TextEditingController(text: record.familyComposition);
    _familyMembers = record.familyMembers
        .map(EditableFamilyMember.fromValue)
        .toList();
    _bloodType = record.bloodType;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _role,
      _phone,
      _address,
      _emergencyName,
      _emergencyRelation,
      _emergencyPhone,
      _emergencyAddress,
      _familyComposition,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || _saving) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名前を入力してください')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('社員個人情報を変更しますか？'),
        content: const Text(
          '登録済みの社員個人情報は直接変更せず、承認者2名へ変更申請を送ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('変更申請を送る'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final result = await repository.savePersonnelProfile({
        ...widget.record.toJson(),
        'name': _name.text.trim(),
        'bloodType': _bloodType,
        'role': _role.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'emergencyName': _emergencyName.text.trim(),
        'emergencyRelation': _emergencyRelation.text.trim(),
        'emergencyPhone': _emergencyPhone.text.trim(),
        'emergencyAddress': _emergencyAddress.text.trim(),
        'familyComposition': _familyComposition.text.trim(),
        'familyMembers': [
          for (final member in _familyMembers) member.toValue().toJson(),
        ],
      });
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
      Navigator.of(context).pop(!pending);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('社員個人情報を編集')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '未登録なら直接保存されます。登録済み情報の変更は承認者2名の承認後に反映されます。',
              ),
            ),
          ),
          const SizedBox(height: 10),
          _field(_name, '名前'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _bloodType.isEmpty ? null : _bloodType,
            decoration: const InputDecoration(
              labelText: '血液型',
              border: OutlineInputBorder(),
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
                : (value) => setState(() => _bloodType = value ?? ''),
          ),
          const SizedBox(height: 10),
          _field(_role, '職種'),
          const SizedBox(height: 10),
          _field(_phone, '電話番号', keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          _field(_address, '住所'),
          const SizedBox(height: 18),
          const Text(
            '緊急連絡先',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _field(_emergencyName, '氏名'),
          const SizedBox(height: 10),
          _field(_emergencyRelation, '続柄'),
          const SizedBox(height: 10),
          _field(
            _emergencyPhone,
            '電話番号',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          _field(_emergencyAddress, '住所'),
          const SizedBox(height: 20),
          const Text(
            '家族・扶養情報',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '社員一覧には表示しません。社会保険等の手続き用の個別情報です。',
          ),
          const SizedBox(height: 10),
          _field(_familyComposition, '家族構成'),
          const SizedBox(height: 10),
          for (var i = 0; i < _familyMembers.length; i++)
            _familyMemberCard(i),
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () => setState(
                      () => _familyMembers.add(EditableFamilyMember()),
                    ),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('配偶者・子供・扶養家族を追加'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.approval_outlined),
            label: Text(_saving ? '送信中…' : '変更申請を送る'),
          ),
        ],
      ),
    );
  }

  Widget _familyMemberCard(int index) {
    final member = _familyMembers[index];
    final birth = member.birthDate;
    final age = member.toValue().ageOn();

    return Card(
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
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => member.name = value,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '家族情報を削除',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _familyMembers.removeAt(index)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: member.relation,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: '続柄（夫・妻・子・扶養家族など）',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => member.relation = value,
            ),
            const SizedBox(height: 10),
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
                        (age == null ? '' : '　現在 ' + age.toString() + '歳'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: birth ?? DateTime(now.year - 30),
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
              subtitle: const Text('社会保険等で扶養対象として扱う場合にON'),
              value: member.isDependent,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => member.isDependent = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) =>
      TextField(
        controller: controller,
        enabled: !_saving,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );
}
