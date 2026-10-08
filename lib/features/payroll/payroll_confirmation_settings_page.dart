import 'package:flutter/material.dart';

import 'payroll_confirmation_repository.dart';

class PayrollConfirmationSettingsPage extends StatefulWidget {
  const PayrollConfirmationSettingsPage({super.key});
  @override
  State<PayrollConfirmationSettingsPage> createState() =>
      _PayrollConfirmationSettingsPageState();
}

class _PayrollConfirmationSettingsPageState
    extends State<PayrollConfirmationSettingsPage> {
  final _repository = PayrollConfirmationRepository.maybeCreate();
  PayrollConfirmationSettings? _settings;
  List<String> _selected = [];
  int _day = 25;
  int _offset = 1;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = _repository;
      if (repository == null) throw StateError('会社設定を利用できません。');
      final settings = await repository.loadSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _selected = settings.reviewerUserIds.toList();
        _day = settings.paymentDay;
        _offset = settings.paymentMonthOffset;
        _busy = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_settings?.canManageSettings != true || _busy) return;
    if (_offset == 0 && _day != 31) {
      setState(() => _error = '末締めの当月払いは月末（31日）を選択してください');
      return;
    }
    if (_selected.isEmpty || _selected.length > 3) {
      setState(() => _error = '確認者を1〜3名選択してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository!.saveSettings(
        reviewerUserIds: _selected,
        paymentDay: _day,
        paymentMonthOffset: _offset,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('会社共通の給与設定を保存しました')));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final editable = settings?.canManageSettings == true && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('会社の給与設定')),
      body: _busy && settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('再読み込み'),
                  ),
                ],
                if (settings != null) ...[
                  const Text(
                    '全社員共通',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('締め日'),
                    trailing: Text('末日'),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _offset,
                    decoration: const InputDecoration(labelText: '支払月'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('当月')),
                      DropdownMenuItem(value: 1, child: Text('翌月')),
                      DropdownMenuItem(value: 2, child: Text('翌々月')),
                    ],
                    onChanged: editable
                        ? (value) => setState(() => _offset = value!)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _day,
                    decoration: const InputDecoration(labelText: '給料日'),
                    items: [
                      for (var day = 1; day <= 31; day++)
                        DropdownMenuItem(
                          value: day,
                          child: Text(day == 31 ? '末日' : '$day日'),
                        ),
                    ],
                    onChanged: editable
                        ? (value) => setState(() => _day = value!)
                        : null,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '給与の確認者（1〜3名）',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text('選択した順に確認印を表示します。'),
                  for (final candidate in settings.candidates)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(candidate.name),
                      subtitle: Text(_role(candidate.role)),
                      value: _selected.contains(candidate.userId),
                      onChanged:
                          editable &&
                              (_selected.contains(candidate.userId) ||
                                  _selected.length < 3)
                          ? (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(candidate.userId);
                              } else {
                                _selected.remove(candidate.userId);
                              }
                            })
                          : null,
                    ),
                  const SizedBox(height: 12),
                  const Text('月末に確認開始を通知します。未確認者には給料日の7日前から当日まで毎日通知します。'),
                  const SizedBox(height: 20),
                  if (settings.canManageSettings)
                    FilledButton(
                      onPressed: editable ? _save : null,
                      child: Text(_busy ? '保存中…' : '保存'),
                    ),
                ],
              ],
            ),
    );
  }

  static String _role(String role) => switch (role) {
    'owner' || 'admin' => '管理者',
    'manager' || 'sub_admin' => 'サブ管理者',
    'viewer' => '閲覧者',
    _ => role,
  };
}
