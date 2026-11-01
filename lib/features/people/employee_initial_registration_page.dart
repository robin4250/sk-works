import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'employee_invite_repository.dart';
import 'employee_invite_delivery_message.dart';
import 'employee_distribution_url_repository.dart';
import '../../data/supabase_backend.dart';
import '../referrals/app_referral_page.dart';
import '../referrals/app_referral_repository.dart';
import 'employee_registration_page.dart';
import '../../international/language_controller.dart';

class EmployeeInitialRegistrationPage extends StatefulWidget {
  const EmployeeInitialRegistrationPage({
    super.key,
    this.selectedCompanyId,
    this.repository,
    this.urlRepository,
  });
  final String? selectedCompanyId;
  final EmployeeInviteRepository? repository;
  final EmployeeDistributionUrlRepository? urlRepository;

  @override
  State<EmployeeInitialRegistrationPage> createState() =>
      _EmployeeInitialRegistrationPageState();
}

class _EmployeeInitialRegistrationPageState
    extends State<EmployeeInitialRegistrationPage> {
  late final EmployeeInviteRepository? _repository;
  final _testFlightUrl = TextEditingController();
  EmployeeDistributionUrlRepository? _urlRepository;
  EmployeeDistributionUrlSnapshot? _urlBefore;
  String? _urlError;
  bool _urlInitialized = false;
  List<InitialRegistrationEmployee> _employees = const [];
  bool _loading = true;
  String? _busyWorkerId;
  String? _error;
  EmployeeInviteResult? _result;
  bool _savingUrl = false;
  String? _loadedActor;
  EmployeeInviteRequest? _request;
  StreamSubscription<dynamic>? _authSubscription;
  bool _invalidated = false;
  bool _current() => !_invalidated && _request?.isCurrent == true;
  void _invalidate() {
    if (!mounted || _invalidated) return;
    _testFlightUrl.clear();
    setState(() {
      _invalidated = true;
      _urlBefore = null;
      _result = null;
      _employees = const [];
      _loadedActor = null;
      _loading = false;
      _error = 'ログイン状態または会社が変わりました。画面を開き直してください。';
    });
  }

  @override
  void didUpdateWidget(covariant EmployeeInitialRegistrationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCompanyId != widget.selectedCompanyId) _invalidate();
  }

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? EmployeeInviteRepository.maybeCreate();
    _urlRepository = widget.urlRepository ?? EmployeeDistributionUrlRepository.maybeCreate();
    _authSubscription = _repository?.authChanges.listen((event) {
      _request?.observeSession(event.session);
      if (_request != null && !_request!.isCurrent) _invalidate();
    }, onError: (Object _) => _invalidate(), onDone: _invalidate);
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
    if (_invalidated) return;
    final actor = repository.currentActorId;
    try {
      _request ??= await repository.beginRequest(
        companyId: widget.selectedCompanyId,
      );
      _request!.check();
      final employees = await repository.loadRegisteredEmployees(request: _request);
      if (!mounted) return;
      if (!_current() || actor == null || repository.currentActorId != actor) {
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
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loading = false;
        _error = null;
      });
      await _loadUrl();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadUrl() async {
    final repository = _urlRepository;
    final request = _request;
    if (repository == null || request == null || !_current()) {
      if (mounted) setState(() => _urlError = 'URL設定を利用できません。');
      return;
    }
    try {
      if (!_urlInitialized) {
        await repository.initialize(request);
        _urlInitialized = true;
      }
      final before = await repository.read(request);
      if (!mounted || !_current()) return;
      setState(() {
        _urlBefore = before;
        // Never turn an unread or invalid response into an empty before-value.
        if (!repository.hasUnknownResult) _testFlightUrl.text = before.url ?? '';
        _urlError = repository.hasUnknownResult
            ? '前の保存結果を確認してください。再保存はできません。'
            : before.canSave ? null : 'URL設定の保存は停止中です。';
      });
    } catch (_) {
      if (!mounted || !_current()) return;
      setState(() {
        _urlBefore = null;
        _urlError = 'URL設定を確認できません。保存せず管理者に確認してください。';
      });
    }
  }

  Future<void> _saveTestFlightUrl() async {
    final repository = _urlRepository;
    final request = _request;
    final before = _urlBefore;
    if (repository == null || request == null || before == null ||
        _savingUrl || !_current() || !before.canSave || repository.hasUnknownResult) return;
    setState(() => _savingUrl = true);
    try {
      final status = await repository.save(request, before, _testFlightUrl.text);
      if (!mounted || !_current()) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        status == 'saved' ? 'TestFlight URLを保存しました' : '設定が変更されています。最新の値を確認してください。',
      )));
      await _loadUrl();
    } catch (error) {
      if (mounted && _current()) {
        setState(() => _urlError = error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  Future<void> _inspectUrlResult() async {
    final repository = _urlRepository;
    final request = _request;
    if (repository == null || request == null || !_current() || _savingUrl) return;
    setState(() => _savingUrl = true);
    try {
      final status = await repository.inspectUnknownResult(request);
      if (!mounted || !_current()) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        status == 'saved' ? '保存結果を確認しました' : '設定競合で保存されていません。最新の値を確認してください。',
      )));
      await _loadUrl();
    } catch (error) {
      if (mounted && _current()) {
        setState(() => _urlError = error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    if (widget.repository == null) _repository?.dispose();
    _testFlightUrl.dispose();
    super.dispose();
  }

  Future<void> _send(InitialRegistrationEmployee employee) async {
    final repository = _repository;
    if (repository == null || _busyWorkerId != null || !_current()) return;
    setState(() {
      _busyWorkerId = employee.id;
      _error = null;
    });
    try {
      final result = await repository.createInviteForWorker(
        employee.id,
        expectedPhone: employee.phone,
        request: _request,
      );
      if (!mounted || !_current()) {
        _invalidate();
        return;
      }
      setState(() => _result = result);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busyWorkerId = null);
    }
  }

  void _sendDistribution(InitialRegistrationEmployee employee) {
    if (_loadedActor == null ||
        SupabaseBackend.client.auth.currentUser?.id != _loadedActor) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppReferralPage(
          repository: AppReferralRepository(SupabaseBackend.client),
          invitationKind: 'employee',
          initialName: employee.name,
          initialPhone: employee.phone,
        ),
      ),
    );
  }

  String _shareText(EmployeeInviteResult result) =>
      employeeInviteDeliveryMessage(
        name: result.name,
        phone: result.phone,
        temporaryPassword: result.temporaryPassword,
        testFlightUrl: result.testFlightUrl,
        english: SkoLanguageController.isEnglish,
      );

  Future<void> _share(EmployeeInviteResult result) async {
    if (!_current() || !identical(result, _result)) {
      _invalidate();
      return;
    }
    await SharePlus.instance.share(ShareParams(text: _shareText(result)));
  }

  Future<void> _openSms(EmployeeInviteResult result) async {
    if (!_current() || !identical(result, _result)) {
      _invalidate();
      return;
    }
    final body = Uri.encodeComponent(_shareText(result));
    final uri = Uri.parse('sms:${result.phone}?body=$body');
    if (!await launchUrl(uri)) {
      throw StateError('SMS作成画面を開けませんでした。共有ボタンをご利用ください。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _current() ? _result : null;
    final unsent = _employees.where((item) => !item.invited).length;
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
                    onPressed: _busyWorkerId != null
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const EmployeeRegistrationPage(),
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
                        '従業員登録済みの人へ、TestFlightと本人専用の初回ログイン情報を順番に送ります。'
                        '未送信 $unsent人 / 登録済み ${_employees.length}人。'
                        '初回登録作成済みの人には「URLを追加送信」からTestFlight・WEB版の案内だけを送れます。ログイン情報は再発行しません。',
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
                            enabled: _current() && _urlBefore?.canSave == true &&
                                _urlRepository?.hasUnknownResult == false && !_savingUrl,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'TestFlight URL',
                              hintText: 'App Store Connectからコピーした参加URL',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.link),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _savingUrl || !_current() ||
                                _urlBefore?.canSave != true ||
                                _urlRepository?.hasUnknownResult != false
                                ? null : _saveTestFlightUrl,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_savingUrl ? '確認中…' : 'URLを保存'),
                          ),
                          if (_urlError != null) Text(_urlError!),
                          if (_urlRepository?.hasUnknownResult == true)
                            TextButton(onPressed: _savingUrl || !_current() ? null : _inspectUrlResult,
                              child: const Text('URLの保存結果を確認')),
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
                          '${employee.invited ? '初回登録作成済み' : '未送信'}',
                        ),
                        isThreeLine: true,
                        trailing: employee.invited
                            ? OutlinedButton(
                                onPressed: _busyWorkerId == null
                                    ? () => _sendDistribution(employee)
                                    : null,
                                child: const Text('URLを追加送信'),
                              )
                            : FilledButton(
                                onPressed: _busyWorkerId == null
                                    ? () => _send(employee)
                                    : null,
                                child: _busyWorkerId == employee.id
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('送信'),
                              ),
                      ),
                    ),
                  if (result != null) ...[
                    const SizedBox(height: 14),
                    _ResultCard(
                      result: result,
                      onShare: () => _share(result),
                      onSms: () => _openSms(result),
                      isCurrent: () => _current() && identical(result, _result),
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
    required this.isCurrent,
  });

  final EmployeeInviteResult result;
  final VoidCallback onShare;
  final VoidCallback onSms;
  final bool Function() isCurrent;

  @override
  Widget build(BuildContext context) {
    final testFlight = employeeInviteTestFlightUrl(result.testFlightUrl);
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              result.smsSent ? 'SMS送信サービス受付済み（配達未確認）' : '初回登録を作成しました',
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
            if (testFlight != null) ...[
              const SizedBox(height: 8),
              SelectableText('TestFlight: $testFlight'),
            ] else ...[
              const SizedBox(height: 8),
              const Text('TestFlight参加URLは未設定、または利用できない形式です。管理者に確認してください。'),
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
                if (!isCurrent()) return;
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


