import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'employee_invite_repository.dart';
import 'employee_invite_sms.dart';
import '../../data/supabase_backend.dart';
import '../auth/employee_bootstrap_identity.dart';
import 'employee_registration_page.dart';
import '../../international/language_controller.dart';

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
  String? _error;
  bool _savingUrl = false;
  String? _loadedActor;

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
    final actor = SupabaseBackend.client.auth.currentUser?.id;
    try {
      final results = await Future.wait([
        repository.loadRegisteredEmployees(),
        repository.loadTestFlightUrl(),
      ]);
      if (!mounted) return;
      if (actor == null ||
          SupabaseBackend.client.auth.currentUser?.id != actor) {
        _testFlightUrl.clear();
        setState(() {
          _employees = const [];
          _loadedActor = null;
          _loading = false;
          _error = 'ログイン情報が変わりました。画面を開き直してください。';
        });
        return;
      }
      _loadedActor = actor;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('TestFlight URLを保存しました')));
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

  Future<void> _openGuide(InitialRegistrationEmployee employee) async {
    final repository = _repository;
    final actor = _loadedActor;
    if (repository == null ||
        actor == null ||
        SupabaseBackend.client.auth.currentUser?.id != actor) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EmployeeDistributionPage(
          employee: employee,
          actor: actor,
          repository: repository,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final unissued = _employees.where((item) => !item.invited).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '従業員登録',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
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
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const EmployeeRegistrationPage(),
                        ),
                      );
                      if (mounted) _load();
                    },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(SkoLanguageController.tr('従業員を追加')),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '従業員名の横にある「招待案内」から、本人専用の初回ログイン情報を作成・共有できます。'
                        '\n招待未作成 $unissued人 / 登録済み ${_employees.length}人',
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
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
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
                        child: Text('上の「従業員を追加」から名前と電話番号を登録してください。'),
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
                          '${employee.invited ? '招待作成済み' : '招待未作成'}',
                        ),
                        isThreeLine: true,
                        trailing: FilledButton(
                          onPressed: () => _openGuide(employee),
                          child: const Text('招待案内'),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _EmployeeDistributionPage extends StatefulWidget {
  const _EmployeeDistributionPage({
    required this.employee,
    required this.actor,
    required this.repository,
  });

  final InitialRegistrationEmployee employee;
  final String actor;
  final EmployeeInviteRepository repository;

  @override
  State<_EmployeeDistributionPage> createState() =>
      _EmployeeDistributionPageState();
}

class _EmployeeDistributionPageState extends State<_EmployeeDistributionPage> {
  EmployeeInviteResult? _result;
  String? _existingAccountCode;
  bool _creating = false;
  String? _error;

  bool get _sameActor =>
      SupabaseBackend.client.auth.currentUser?.id == widget.actor;

  Future<void> _createInvite() async {
    if (!_sameActor || _creating || _result != null || _existingAccountCode != null) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final result = await widget.repository.createInviteForWorker(
        widget.employee.id,
        deliverSms: false,
      );
      if (!mounted || !_sameActor) return;
      setState(() => _result = result);
    } catch (error) {
      if (mounted && _sameActor) {
        setState(
          () {
            final details = error is FunctionException ? error.details : null;
            final message = details is Map ? details['error'] : null;
            _error = message is String && message.isNotEmpty
                ? message
                : '初回ログイン情報を作成できませんでした。';
          },
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _issueExistingAccountClaim() async {
    if (!_sameActor || _creating || _result != null) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final code = await widget.repository.issueExistingAccountClaim(widget.employee.id);
      if (mounted && _sameActor) setState(() => _existingAccountCode = code);
    } catch (_) {
      if (mounted && _sameActor) {
        setState(() => _error = '招待コードを発行できませんでした。従業員の登録状況を確認してください。');
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deliver(
    Future<void> Function() action, {
    String? success,
  }) async {
    if (!_sameActor) return;
    try {
      await action();
      if (success != null && mounted && _sameActor) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (!mounted || !_sameActor) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _share(EmployeeInviteResult result) =>
      SharePlus.instance.share(ShareParams(text: employeeInviteSms(result)));

  Future<void> _openSms(String phone, String message) async {
    final body = Uri.encodeComponent(message);
    final uri = Uri.parse('sms:$phone?body=$body');
    if (!await launchUrl(uri)) {
      throw StateError('SMS作成画面を開けませんでした。共有ボタンをご利用ください。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_creating,
      child: Scaffold(
        appBar: AppBar(title: const Text('従業員の招待案内')),
        body: StreamBuilder(
          stream: SupabaseBackend.client.auth.onAuthStateChange,
          builder: (context, _) {
            if (!_sameActor) {
              return const Center(child: Text('ログイン情報が変わりました。画面を開き直してください。'));
            }
            final result = _result;
            final existingAccountCode = _existingAccountCode;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(widget.employee.name),
                  subtitle: Text(widget.employee.phone),
                ),
                const ListTile(
                  title: Text('従業員の登録手順'),
                  subtitle: Text(
                    '端末に合わせた開き方は案内ページをご確認ください。'
                    '\n初めて使う方には、登録電話番号と初回ログインパスワードをお渡しください。',
                  ),
                ),
                const ListTile(
                  title: Text('登録後に使う機能'),
                  subtitle: Text(employeeInviteWorkGuide),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _creating ? null : () => _deliver(
                    () => _openSms(widget.employee.phone, employeeAppGuideSms),
                  ),
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('案内URLだけのSMSを作成'),
                ),
                if (!widget.employee.invited && result == null && existingAccountCode == null)
                  FilledButton.icon(
                    onPressed: _creating ? null : _createInvite,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(_creating ? '作成中…' : '本人専用の招待を作成'),
                  )
                else if (result != null)
                  _ResultCard(
                    result: result,
                    onShare: () => _deliver(() => _share(result)),
                    onSms: () => _deliver(() => _openSms(result.phone, employeeInviteSms(result))),
                    onCopy: (value, message) => _deliver(
                      () => Clipboard.setData(ClipboardData(text: value)),
                      success: message,
                    ),
                  ),
                if (employeeExistingAccountClaimEnabled && !widget.employee.invited && result == null)
                  OutlinedButton(
                    onPressed: _creating ? null : _issueExistingAccountClaim,
                    child: Text(existingAccountCode == null
                        ? '既存アカウント用の招待コードを発行'
                        : '招待コードを再発行'),
                  ),
                if (existingAccountCode != null) ...[
                  const Text('招待コードは48時間有効です。従業員本人に共有してください。'),
                  SelectableText(existingAccountCode),
                  OutlinedButton.icon(
                    onPressed: _creating ? null : () => _deliver(
                      () => Clipboard.setData(ClipboardData(text:
                        'SKOに登録済みの方法でログインし、「従業員の招待を受け取る」を選んでください。\n'
                        '招待コード $existingAccountCode',
                      )),
                      success: '招待案内をコピーしました',
                    ),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('既存アカウント用の案内をコピー'),
                  ),
                ],
              ],
            );
          },
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
    required this.onCopy,
  });

  final EmployeeInviteResult result;
  final VoidCallback onShare;
  final VoidCallback onSms;
  final Future<void> Function(String, String) onCopy;

  @override
  Widget build(BuildContext context) {
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
                    : '登録した電話番号と初期パスワードを本人に共有してください。初回ログインにSMSコードは不要です。',
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '初回ログインパスワード',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SelectableText(result.temporaryPassword),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onCopy(
                result.temporaryPassword,
                'この端末にコピーしました。別のスマホへ渡すときは「配布リンクとログイン案内をコピー」を使います。',
              ),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('① 初回ログインパスワードをコピー'),
            ),
            const Text(
              '別のスマホに渡すときは、下の「配布リンクとログイン案内をコピー」を押し、本人へのメッセージに貼り付けます。',
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('対面でQRを読み取る'),
              children: [
                const Text('本人のスマホで「従業員登録QRでログイン」を押して読み取ります。'),
                const SizedBox(height: 8),
                QrImageView(data: result.qrPayload, size: 220, backgroundColor: Colors.white),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('送信する案内文を確認'),
              children: [SelectableText(employeeInviteSms(result))],
            ),
            FilledButton.icon(
              onPressed: onSms,
              icon: const Icon(Icons.sms_outlined),
              label: const Text('この従業員へSMSを作成'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  onCopy(employeeInviteSms(result), '初回ログインの案内をコピーしました'),
              icon: const Icon(Icons.content_copy_outlined),
              label: const Text('配布リンクとログイン案内をコピー'),
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
