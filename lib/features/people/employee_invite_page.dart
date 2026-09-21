import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'employee_invite_repository.dart';

class EmployeeInvitePage extends StatefulWidget {
  const EmployeeInvitePage({super.key});

  @override
  State<EmployeeInvitePage> createState() => _EmployeeInvitePageState();
}

class _EmployeeInvitePageState extends State<EmployeeInvitePage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _repository = EmployeeInviteRepository.maybeCreate();

  bool _busy = false;
  EmployeeInviteResult? _result;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final repository = _repository;
    if (repository == null) return;
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = '名前と電話番号を入力してください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await repository.createInvite(
        name: _name.text,
        phone: _phone.text,
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

  @override
  Widget build(BuildContext context) {
    final result = _result;
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
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '従業員登録はSKOを利用中の会社メンバーなら行えます。'
                  '最初に必要なのは名前と携帯電話番号だけです。'
                  '登録後に初期パスワードをSMSアプリ等へ共有したり、'
                  'QRコードを相手に見せることができます。',
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
                            const SnackBar(content: Text('初期パスワードをコピーしました')),
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
                onPressed: () => setState(() {
                  _result = null;
                  _name.clear();
                  _phone.clear();
                }),
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
