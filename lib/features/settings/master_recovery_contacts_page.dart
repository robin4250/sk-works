import 'package:flutter/material.dart';

import 'master_recovery_repository.dart';

class MasterRecoveryContactsPage extends StatefulWidget {
  const MasterRecoveryContactsPage({super.key});

  @override
  State<MasterRecoveryContactsPage> createState() =>
      _MasterRecoveryContactsPageState();
}

class _MasterRecoveryContactsPageState
    extends State<MasterRecoveryContactsPage> {
  final _repository = MasterRecoveryRepository.maybeCreate();
  final _primary = TextEditingController();
  final _secondary = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  MasterRecoveryContactsState? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'Master緊急復旧設定を利用できません。';
      });
      return;
    }
    try {
      final value = await repository.load();
      if (!mounted) return;
      setState(() {
        _state = value;
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
    final primary = _primary.text.trim();
    final secondary = _secondary.text.trim();
    if (repository == null || primary.isEmpty || secondary.isEmpty) {
      setState(() => _error = '2つの復旧用メールアドレスを入力してください。');
      return;
    }
    if (primary.toLowerCase() == secondary.toLowerCase()) {
      setState(() => _error = '異なる2つのメールアドレスを登録してください。');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('復旧用メールを変更しますか？'),
        content: const Text(
          'この設定はMaster緊急復旧に使います。2つの別メールへ別々の確認コードを送る方式の土台です。'
          '変更は監査ログへ記録されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('変更する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await repository.save(
        primaryEmail: primary,
        secondaryEmail: secondary,
      );
      if (!mounted) return;
      setState(() {
        _state = updated;
        _primary.clear();
        _secondary.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master復旧用メールを更新しました')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recoveryState = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('Master 緊急復旧設定')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '信頼済みMaster端末・生体認証・第2パスワードを通過した後だけ変更できます。'
                        '復旧時は2つの別メールへ別々のワンタイムコードを送る方式を使用します。',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (recoveryState?.configured == true)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: const Text('現在の復旧用メール'),
                        subtitle: Text(
                          '${recoveryState?.primaryMasked ?? '-'}\n'
                          '${recoveryState?.secondaryMasked ?? '-'}',
                        ),
                      ),
                    )
                  else
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.warning_amber_outlined),
                        title: Text('復旧用メールは未設定です'),
                        subtitle: Text('異なる2つのメールアドレスを登録してください。'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _primary,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '復旧用メール 1',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secondary,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '復旧用メール 2',
                      prefixIcon: Icon(Icons.mark_email_read_outlined),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.security_update_good_outlined),
                    label: Text(_saving ? '更新中...' : '2つの復旧メールを確認して保存'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
