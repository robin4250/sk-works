import 'package:flutter/material.dart';

import 'employee_invite_repository.dart';

class EmployeeRegistrationPage extends StatefulWidget {
  const EmployeeRegistrationPage({super.key});

  @override
  State<EmployeeRegistrationPage> createState() =>
      _EmployeeRegistrationPageState();
}

class _EmployeeRegistrationPageState extends State<EmployeeRegistrationPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _repository = EmployeeInviteRepository.maybeCreate();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await repository.registerEmployee(
        name: _name.text,
        phone: _phone.text,
      );
      if (!mounted) return;
      setState(() {
        _name.clear();
        _phone.clear();
        _message = '従業員を登録しました。続けて次の従業員を登録できます。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('従業員登録', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'ここでは従業員の名前と携帯電話番号だけを先に登録します。'
                  '登録後、TOPページの「初回登録」からTestFlightと初回ログイン情報を送ります。',
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '名前 *',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '携帯電話番号 *',
                hintText: '09012345678',
                prefixIcon: Icon(Icons.phone_iphone_outlined),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _message!.contains('登録しました')
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1),
              label: Text(_busy ? '登録中…' : '従業員を登録'),
            ),
          ],
        ),
      ),
    );
  }
}
