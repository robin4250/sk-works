import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'employee_invite_repository.dart';

class EmployeeInitialRegistrationPage extends StatefulWidget {
  const EmployeeInitialRegistrationPage({super.key});

  @override
  State<EmployeeInitialRegistrationPage> createState() =>
      _EmployeeInitialRegistrationPageState();
}

class _EmployeeInitialRegistrationPageState
    extends State<EmployeeInitialRegistrationPage> {
  final _repository = EmployeeInviteRepository.maybeCreate();
  final _testFlightUrl = TextEditingController();
  List<InitialRegistrationEmployee> _employees = const [];
  bool _loading = true;
  String? _busyWorkerId;
  String? _error;
  EmployeeInviteResult? _result;
  bool _savingUrl = false;

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
        _error = '初回登録を利用できません。';
      });
      return;
    }
    try {
      final results = await Future.wait([
        repository.loadRegisteredEmployees(),
        repository.loadTestFlightUrl(),
      ]);
      final employees = results[0] as List<InitialRegistrationEmployee>;
      _testFlightUrl.text = results[1] as String;
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _saveTestFlightUrl() async {
    final repository = _repository;
    if (repository == null || _savingUrl) return;
    setState(() => _savingUrl = true);
    try {
      await repository.saveTestFlightUrl(_testFlightUrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TestFlight URLを保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  @override
  void dispose() {
    _testFlightUrl.dispose();
    super.dispose();
  }

  Future<void> _send(InitialRegistrationEmployee employee) async {
    final repository = _repository;
    if (repository == null || _busyWorkerId != null) return;
    setState(() {
      _busyWorkerId = employee.id;
      _error = null;
    });
    try {
      final result = await repository.createInviteForWorker(employee.id);
      if (!mounted) return;
      setState(() => _result = result);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busyWorkerId = null);
    }
  }

  String _shareText(EmployeeInviteResult result) {
    final buffer = StringBuffer()
      ..writeln('SKO初回登録のご案内')
      ..writeln('氏名: ${result.name}');
    final testFlight = result.testFlightUrl?.trim() ?? '';
    if (testFlight.isNotEmpty) {
      buffer.writeln('TestFlight: $testFlight');
    }
    buffer
      ..writeln('電話番号: ${result.phone}')
      ..writeln('初期パスワード: ${result.temporaryPassword}')
      ..writeln('SKOをインストール後、初回ログインQRまたは上記情報でログインしてください。');
    return buffer.toString();
  }

  Future<void> _share(EmployeeInviteResult result) =>
      SharePlus.instance.share(ShareParams(text: _shareText(result)));

  Future<void> _openSms(EmployeeInviteResult result) async {
    final body = Uri.encodeComponent(_shareText(result));
    final uri = Uri.parse('sms:${result.phone}?body=$body');
    if (!await launchUrl(uri)) {
      throw StateError('SMS作成画面を開けませんでした。共有ボタンをご利用ください。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final unsent = _employees.where((item) => !item.invited).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('初回登録', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '従業員登録済みの人へ、TestFlightと本人専用の初回ログイン情報を順番に送ります。'
                        '未送信 $unsent人 / 登録済み ${_employees.length}人',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'TestFlight誘導URL',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '従業員へ送る初回登録案内に入るURLです。TestFlightの招待URLを貼り付けて保存してください。',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _testFlightUrl,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'TestFlight URL',
                              hintText: 'https://testflight.apple.com/join/...',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.link),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _savingUrl ? null : _saveTestFlightUrl,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_savingUrl ? '保存中…' : 'URLを保存'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_employees.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('先に「従業員登録」で名前と電話番号を登録してください。'),
                      ),
                    ),
                  for (final employee in _employees)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            employee.invited ? Icons.check : Icons.sms_outlined,
                          ),
                        ),
                        title: Text(
                          employee.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${employee.phone}\n'
                          '${employee.invited ? '初回登録作成済み' : '未送信'}',
                        ),
                        isThreeLine: true,
                        trailing: employee.invited
                            ? const Icon(Icons.check_circle_outline)
                            : FilledButton(
                                onPressed: _busyWorkerId == null
                                    ? () => _send(employee)
                                    : null,
                                child: _busyWorkerId == employee.id
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('送信'),
                              ),
                      ),
                    ),
                  if (_result != null) ...[
                    const SizedBox(height: 14),
                    _ResultCard(
                      result: _result!,
                      onShare: () => _share(_result!),
                      onSms: () => _openSms(_result!),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.onShare,
    required this.onSms,
  });

  final EmployeeInviteResult result;
  final VoidCallback onShare;
  final VoidCallback onSms;

  @override
  Widget build(BuildContext context) {
    final testFlight = result.testFlightUrl?.trim() ?? '';
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              result.smsSent ? 'SMS送信済み' : '初回登録を作成しました',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            if (!result.smsSent) ...[
              const SizedBox(height: 6),
              Text(
                result.deliveryMessage?.trim().isNotEmpty == true
                    ? result.deliveryMessage!
                    : 'SMS自動送信設定が未接続のため、共有ボタンから送れます。',
              ),
            ],
            if (testFlight.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText('TestFlight: $testFlight'),
            ],
            const SizedBox(height: 10),
            const Text(
              '初回ログインQR',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Center(
              child: QrImageView(
                data: result.qrPayload,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              '初期パスワード: ${result.temporaryPassword}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
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
            FilledButton.icon(
              onPressed: onSms,
              icon: const Icon(Icons.sms_outlined),
              label: const Text('この従業員へSMSを作成'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
              label: const Text('LINE・メッセージ等で共有'),
            ),
          ],
        ),
      ),
    );
  }
}
