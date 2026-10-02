import 'package:flutter/material.dart';

import 'people_cloud_repository.dart';
import 'people_page.dart';

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
