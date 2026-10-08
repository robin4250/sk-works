import '../../international/language_controller.dart';
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
      if (repository == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = '会社設定を利用できません。';
        });
        return;
      }
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
            .showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('会社共通の給与設定を保存しました'))));
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
    SkoLanguageController.watch(context);
    final settings = _settings;
    final editable = settings?.canManageSettings == true && !_busy;
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('会社の給与設定'))),
      body: _busy && settings == null
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) ...[
                  Text(
                    SkoLanguageController.tr(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: Text(SkoLanguageController.tr('再読み込み')),
                  ),
                ],
                if (settings != null) ...[
                  Text(
                    SkoLanguageController.tr('全社員共通'),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(SkoLanguageController.tr('締め日')),
                    trailing: Text(SkoLanguageController.tr('末日')),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _offset,
                    decoration: InputDecoration(labelText: SkoLanguageController.tr('支払月')),
                    items: [
                      DropdownMenuItem(value: 0, child: Text(SkoLanguageController.tr('当月'))),
                      DropdownMenuItem(value: 1, child: Text(SkoLanguageController.tr('翌月'))),
                      DropdownMenuItem(value: 2, child: Text(SkoLanguageController.tr('翌々月'))),
                    ],
                    onChanged: editable
                        ? (value) => setState(() => _offset = value!)
                        : null,
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _day,
                    decoration: InputDecoration(labelText: SkoLanguageController.tr('給料日')),
                    items: [
                      for (var day = 1; day <= 31; day++)
                        DropdownMenuItem(
                          value: day,
                          child: Text(day == 31 ? SkoLanguageController.tr('末日') : SkoLanguageController.trParams('{day}日', {'day': day})),
                        ),
                    ],
                    onChanged: editable
                        ? (value) => setState(() => _day = value!)
                        : null,
                  ),
                  SizedBox(height: 24),
                  Text(
                    SkoLanguageController.tr('給与の確認者（1〜3名）'),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(SkoLanguageController.tr('選択した順に確認印を表示します。')),
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
                  SizedBox(height: 12),
                  Text(SkoLanguageController.tr('月末に確認開始を通知します。未確認者には給料日の7日前から当日まで毎日通知します。')),
                  SizedBox(height: 20),
                  if (settings.canManageSettings)
                    FilledButton(
                      onPressed: editable ? _save : null,
                      child: Text(_busy ? SkoLanguageController.tr('保存中…') : SkoLanguageController.tr('保存')),
                    ),
                ],
              ],
            ),
    );
  }

  static String _role(String role) => switch (role) {
    'owner' || 'admin' => SkoLanguageController.tr('管理者'),
    'manager' || 'sub_admin' => SkoLanguageController.tr('サブ管理者'),
    'viewer' => SkoLanguageController.tr('閲覧者'),
    _ => role,
  };
}
