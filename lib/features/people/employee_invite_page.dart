import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'employee_invite_repository.dart';

class EmployeeInvitePage extends StatefulWidget {
  const EmployeeInvitePage({
    super.key,
    this.canAssignManagementRole = false,
  });

  final bool canAssignManagementRole;

  @override
  State<EmployeeInvitePage> createState() => _EmployeeInvitePageState();
}

class _EmployeeInvitePageState extends State<EmployeeInvitePage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _repository = EmployeeInviteRepository.maybeCreate();

  bool _busy = false;
  bool _assigneeLoading = false;
  bool _makeSubAdmin = false;
  bool _makeApprovalAssignee = false;
  String? _replaceApprovalAssigneeUserId;
  List<ApprovalAssigneeOption> _currentApprovalAssignees = const [];
  EmployeeInviteResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.canAssignManagementRole) {
      _loadApprovalAssignees();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadApprovalAssignees() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _assigneeLoading = true);
    try {
      final rows = await repository.loadCurrentApprovalAssignees();
      if (!mounted) return;
      setState(() {
        _currentApprovalAssignees = rows;
        _assigneeLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _assigneeLoading = false);
    }
  }

  Future<String?> _chooseApprovalReplacement() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('承認担当者は最大3名です'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '現在登録中の3名のうち、誰か1名を外してください。'
                '新しい従業員の本登録承認と同時に入れ替えます。',
              ),
              const SizedBox(height: 12),
              for (final item in _currentApprovalAssignees)
                Card(
                  child: ListTile(
                    title: Text(item.displayName),
                    subtitle: Text(
                      item.role == 'owner'
                          ? '管理者'
                          : item.role == 'admin'
                              ? '管理者'
                              : 'サブ管理者',
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, item.userId),
                      child: const Text('この人を外す'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _setApprovalAssignee(bool value) async {
    if (!value) {
      setState(() {
        _makeApprovalAssignee = false;
        _replaceApprovalAssigneeUserId = null;
      });
      return;
    }

    setState(() => _makeSubAdmin = true);

    if (_currentApprovalAssignees.length >= 3) {
      final replacement = await _chooseApprovalReplacement();
      if (!mounted) return;
      if (replacement == null) {
        setState(() {
          _makeApprovalAssignee = false;
          _replaceApprovalAssigneeUserId = null;
        });
        return;
      }
      setState(() {
        _makeApprovalAssignee = true;
        _replaceApprovalAssigneeUserId = replacement;
      });
      return;
    }

    setState(() {
      _makeApprovalAssignee = true;
      _replaceApprovalAssigneeUserId = null;
    });
  }

  Future<void> _create() async {
    final repository = _repository;
    if (repository == null) return;
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = '名前と電話番号を入力してください。');
      return;
    }

    if (_makeApprovalAssignee &&
        _currentApprovalAssignees.length >= 3 &&
        _replaceApprovalAssigneeUserId == null) {
      final replacement = await _chooseApprovalReplacement();
      if (!mounted) return;
      if (replacement == null) {
        setState(() => _error = '承認担当者から外す人を選んでください。');
        return;
      }
      _replaceApprovalAssigneeUserId = replacement;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await repository.createInvite(
        name: _name.text,
        phone: _phone.text,
        requestedRole: _makeSubAdmin ? 'manager' : 'viewer',
        requestedApprovalAssignee: _makeApprovalAssignee,
        replaceApprovalAssigneeUserId: _replaceApprovalAssigneeUserId,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  String _shareText(EmployeeInviteResult result) =>
      'SKOの従業員登録が作成されました。\n'
      '電話番号: ${result.phone}\n'
      '初期パスワード: ${result.temporaryPassword}\n'
      'SKOアプリを開き、初期パスワードでログインしてください。'
      '初回ログイン後に本パスワードを設定します。';

  Future<void> _share(EmployeeInviteResult result) async {
    await SharePlus.instance.share(
      ShareParams(text: _shareText(result)),
    );
  }

  void _reset() {
    setState(() {
      _result = null;
      _name.clear();
      _phone.clear();
      _makeSubAdmin = false;
      _makeApprovalAssignee = false;
      _replaceApprovalAssigneeUserId = null;
      _error = null;
    });
    if (widget.canAssignManagementRole) {
      _loadApprovalAssignees();
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final replacementName = _replaceApprovalAssigneeUserId == null
        ? null
        : _currentApprovalAssignees
                .where(
                  (item) => item.userId == _replaceApprovalAssigneeUserId,
                )
                .isEmpty
            ? null
            : _currentApprovalAssignees
                .firstWhere(
                  (item) => item.userId == _replaceApprovalAssigneeUserId,
                )
                .displayName;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '従業員登録',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.canAssignManagementRole
                      ? '従業員登録はSKOを利用中の会社メンバーなら行えます。'
                          '管理者はこの画面でサブ管理者・承認担当者の指定もできます。'
                      : '従業員登録はSKOを利用中の会社メンバーなら行えます。'
                          '一般ユーザーとして招待します。'
                          'サブ管理者・承認担当者の指定は管理者が行います。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              enabled: result == null,
              decoration: const InputDecoration(
                labelText: '名前 *',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              enabled: result == null,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '携帯電話番号 *',
                hintText: '09012345678',
                prefixIcon: Icon(Icons.phone_iphone_outlined),
              ),
            ),
            if (widget.canAssignManagementRole && result == null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '役割・承認権限',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('サブ管理者にする'),
                        subtitle: const Text(
                          '請求書・管理者用現場データ・現場単価は表示しません',
                        ),
                        value: _makeSubAdmin,
                        onChanged: _busy
                            ? null
                            : (value) {
                                final enabled = value ?? false;
                                setState(() {
                                  _makeSubAdmin = enabled;
                                  if (!enabled) {
                                    _makeApprovalAssignee = false;
                                    _replaceApprovalAssigneeUserId = null;
                                  }
                                });
                              },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('承認担当者にする'),
                        subtitle: Text(
                          _assigneeLoading
                              ? '現在の承認担当者を確認中...'
                              : '現在 ${_currentApprovalAssignees.length} / 3名'
                                  '${replacementName == null ? '' : '　→ $replacementNameさんと入れ替え予定'}',
                        ),
                        value: _makeApprovalAssignee,
                        onChanged: _busy || _assigneeLoading
                            ? null
                            : (value) =>
                                _setApprovalAssignee(value ?? false),
                      ),
                      if (_makeApprovalAssignee)
                        const Text(
                          '承認担当者を選ぶと、サブ管理者も自動でONになります。',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (result == null)
              FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1),
                label: const Text('従業員登録を作成'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 18),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '初期パスワードを渡してください',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      if (_makeSubAdmin) ...[
                        const SizedBox(height: 6),
                        Text(
                          _makeApprovalAssignee
                              ? '本登録後：サブ管理者・承認担当者'
                              : '本登録後：サブ管理者',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SelectableText(
                        result.temporaryPassword,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: result.temporaryPassword),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('初期パスワードをコピーしました'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('初期パスワードをコピー'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _share(result),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('SMS・メッセージなどで共有'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      const Text(
                        'QRコードで渡す',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      QrImageView(
                        data: result.qrPayload,
                        version: QrVersions.auto,
                        size: 230,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '相手のSKOログイン画面で「QRコードから登録」を開き、'
                        'このQRコードを読み取ってください。',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _reset,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('続けて別の従業員を登録'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
