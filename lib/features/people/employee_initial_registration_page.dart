import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'employee_invite_repository.dart';

class EmployeeInitialRegistrationPage extends StatefulWidget {
  const EmployeeInitialRegistrationPage({super.key, this.allowInvitations = true});

  final bool allowInvitations;

  @override
  State<EmployeeInitialRegistrationPage> createState() =>
      _EmployeeInitialRegistrationPageState();
}

class _EmployeeInitialRegistrationPageState
    extends State<EmployeeInitialRegistrationPage> {
  final _repository = EmployeeInviteRepository.maybeCreate();
  final _testFlightUrl = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _registering = false;
  String? _registrationMessage;
  List<InitialRegistrationEmployee> _employees = const [];
  bool _loading = true;
  String? _busyWorkerId;
  String? _error;
  EmployeeInviteResult? _result;
  bool _savingUrl = false;
  bool _onlyUnprepared = true;
  final Map<String, String> _deliveryEventIds = {}; // No password or QR payload is persisted.

  @override
  void initState() {
    super.initState();
    if (widget.allowInvitations) {
      _load();
    } else {
      _loading = false;
    }
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
    _name.dispose();
    _phone.dispose();
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
      final result = await repository.createInviteForWorker(employee.id, deliverSms: false);
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

  Future<void> _recordManualSending(InitialRegistrationEmployee employee) async {
    final repository = _repository;
    if (repository == null || _busyWorkerId != null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('手動送信の記録'),
      content: Text('${employee.name}さんへ案内を実際に送ったことを記録しますか？SMSや共有画面を開いただけの場合は記録しないでください。相手への配信・受信を証明する記録ではありません。'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('送ったことを記録'))],
    ));
    if (confirmed != true || !mounted) return;
    final eventId = _deliveryEventIds.putIfAbsent(
      '${employee.registrationStatus!.companyId}/${employee.id}/${employee.registrationStatus!.invitationId}', () {
      final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    });
    setState(() => _busyWorkerId = employee.id);
    try {
      await repository.recordManualSending(employee, eventId);
      _deliveryEventIds.remove(
        '${employee.registrationStatus!.companyId}/${employee.id}/${employee.registrationStatus!.invitationId}',
      );
      await _load();
    } catch (error) {
      if (mounted) { setState(() => _error = '記録結果を確認できません。同じ記録で再確認してください。 $error'); }
    } finally {
      if (mounted) setState(() => _busyWorkerId = null);
    }
  }

  Future<void> _register({required bool continueToInvite}) async {
    final repository = _repository;
    if (repository == null || _registering || _busyWorkerId != null) return;
    setState(() {
      _registering = true;
      _registrationMessage = null;
      _error = null;
    });
    try {
      final name = _name.text.trim();
      final phone = _phone.text.trim();
      final workerId = await repository.registerEmployee(name: name, phone: phone);
      if (!mounted) return;
      setState(() {
        _name.clear();
        _phone.clear();
        _registrationMessage = '従業員を登録しました。';
      });
      if (continueToInvite && widget.allowInvitations) {
        await _send(InitialRegistrationEmployee(
          id: workerId, name: name, phone: phone, invited: false,
        ));
      } else if (widget.allowInvitations) {
        await _load();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('従業員登録・初回案内'),
        content: const Text(
          '「登録だけ」は名前と携帯電話番号を保存します。'
          '「登録して続けて案内作成」は保存された本人のIDで初回案内を作成します。'
          '登録後に案内作成が失敗しても従業員は登録済みなので、再登録せず送信対象から選んでください。'
          'TestFlight URLは同じ画面で保存できます。QR・SMS作成・共有は従来と同じです。'
          'SMS作成画面や共有画面を開いたことは、実際の送信完了を意味しません。'
          '初回案内の機能は従来の管理者権限で利用します。'
          '状態確認が利用可能な場合、承認済みの初回登録完了者は一覧に出しません。未送信の絞り込みは手動送信の記録がない人を表示します。状態未確認を送信済みや登録完了と推測しません。'
          '既存案内の安全な再発行は未対応のため、新しいアカウントを再作成しません。手動送信の記録は実配信・受信の確認とは別です。',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('確認'))],
      ),
    );
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

  Widget _registrationCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('名前と携帯電話番号だけを先に登録します。', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: _name, enabled: !_registering, decoration: const InputDecoration(labelText: '名前 *')),
          const SizedBox(height: 12),
          TextField(controller: _phone, enabled: !_registering, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '携帯電話番号 *', hintText: '09012345678')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _registering || _busyWorkerId != null ? null : () => _register(continueToInvite: false),
            icon: const Icon(Icons.person_add_alt_1), label: const Text('登録だけ'),
          ),
          if (widget.allowInvitations) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _registering || _busyWorkerId != null ? null : () => _register(continueToInvite: true),
              icon: const Icon(Icons.sms_outlined), label: const Text('登録して続けて案内作成'),
            ),
          ],
          if (!widget.allowInvitations && _error != null) Text(_error!),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final unsent = _employees.where((item) => item.needsSending).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('従業員登録', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: _showHelp, tooltip: '従業員登録の使い方', icon: const Icon(Icons.help_outline)),
          if (widget.allowInvitations) IconButton(
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
                  _registrationCard(),
                  if (_registrationMessage != null) Text(_registrationMessage!),
                  if (widget.allowInvitations) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '同じ画面で登録と初回案内を行います。'
                        '未送信・状態未確認 $unsent人。'
                        'アカウント作成と実送信・初回登録完了は別です。',
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
                        child: Text('上の登録欄から名前と電話番号を登録してください。'),
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('未送信・状態未確認の人だけ表示'),
                    value: _onlyUnprepared,
                    onChanged: (value) => setState(() => _onlyUnprepared = value),
                  ),
                  for (final employee in _employees.where((item) => !item.completed && (!_onlyUnprepared || item.needsSending)))
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            employee.hasInvitation ? Icons.check : Icons.sms_outlined,
                          ),
                        ),
                        title: Text(
                          employee.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${employee.phone}\n'
                          '${!employee.hasInvitation ? '案内未作成' : employee.manuallySent ? '手動送信を記録済み（配信・受信は未確認）' : '案内作成済み・送信状態未確認'}'
                          '${employee.registrationStatus == null ? '\n状態確認はOFFまたは未導入です' : ''}'
                          '${employee.hasInvitation ? '\n作成済み案内の安全な再開は未対応です（再登録不要）' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: employee.hasInvitation
                            ? employee.registrationStatus?.invitationId != null && !employee.manuallySent
                                ? TextButton(onPressed: _busyWorkerId == null ? () => _recordManualSending(employee) : null, child: const Text('送信を記録'))
                                : const Icon(Icons.info_outline)
                            : FilledButton(
                                onPressed: _busyWorkerId == null && !_registering
                                    ? () => _send(employee)
                                    : null,
                                child: _busyWorkerId == employee.id
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('案内作成'),
                              ),
                      ),
                    ),
                  ],
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
