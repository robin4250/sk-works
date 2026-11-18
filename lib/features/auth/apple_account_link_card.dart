import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import 'apple_account_link.dart';
import 'apple_native_credential_preparation.dart';

class AppleAccountLinkCard extends StatefulWidget {
  const AppleAccountLinkCard({super.key, this.source, this.onLinked});
  final AppleAccountLink? source;
  final VoidCallback? onLinked;
  @override
  State<AppleAccountLinkCard> createState() => _AppleAccountLinkCardState();
}

class _AppleAccountLinkCardState extends State<AppleAccountLinkCard>
    with WidgetsBindingObserver {
  AppleAccountLink? _source;
  StreamSubscription<dynamic>? _events;
  AppleLinkReadiness? _readiness;
  bool _loading = true, _busy = false, _pending = false, _checking = false;
  bool _complete = false, _confirming = false;
  bool _foreground = true;
  int _generation = 0, _actionGeneration = 0;
  String? _message;
  BuildContext? _confirmationContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _source = widget.source;
    if (_source == null && !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        SupabaseBackend.isInitialized && SupabaseBackendConfig.isConfigured) {
      _source = AppleAccountLink(SupabaseBackend.client,
          settingsUrl: Uri.parse('${SupabaseBackendConfig.url}/auth/v1/settings'),
          publicKey: SupabaseBackendConfig.publishableKey);
    }
    _events = _source?.changes.listen((_) {
      if (!_pending && mounted) {
        _actionGeneration++;
        final dialog = _confirmationContext;
        _confirmationContext = null;
        if (dialog != null && dialog.mounted &&
            ModalRoute.of(dialog)?.isCurrent == true) {
          Navigator.of(dialog).pop(false);
        }
        setState(() { _message = null; _complete = false; });
        _load();
      }
      if (!_nativeEnrollmentEnabled) _verify();
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _readiness = null; });
    AppleLinkReadiness readiness;
    try { readiness = await _source?.readiness() ?? AppleLinkReadiness.unavailable; }
    catch (_) { readiness = AppleLinkReadiness.unavailable; }
    if (!mounted || generation != _generation) return;
    setState(() { _readiness = readiness; _loading = false; });
  }

  static const _nativeEnrollmentEnabled =
      bool.fromEnvironment('SKO_APPLE_NATIVE_ENROLLMENT_ENABLED');

  Future<void> _startNativeEnrollment() async {
    final source = _source;
    if (source == null || _busy || _pending || !_nativeEnrollmentEnabled) return;
    final original = source.client.auth.currentSession;
    if (original == null || original.isExpired) return;
    final action = ++_actionGeneration;
    setState(() { _busy = true; _pending = true; _message = null; });
    final preparation = AppleNativeCredentialPreparation(source.client, enabled: true);
    final transport = http.Client();
    try {
      var password = '';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('第一パスワードで本人確認'),
          content: TextField(
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '第一パスワード'),
            onChanged: (value) => password = value,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('戻る')),
            TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Appleの本人確認へ')),
          ],
        ),
      );
      if (!mounted || confirmed != true || password.isEmpty ||
          action != _actionGeneration ||
          source.client.auth.currentSession?.accessToken != original.accessToken) return;
      final credential = await preparation.requestForExistingGoogleAccount();
      // The system sheet can deliver its result before Flutter reports resume.
      final resumeDeadline = Stopwatch()..start();
      while (mounted && !_foreground && action == _actionGeneration &&
          source.client.auth.currentSession?.accessToken == original.accessToken &&
          resumeDeadline.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!mounted || !_foreground || action != _actionGeneration ||
          credential.exactAccessToken != original.accessToken ||
          source.client.auth.currentSession?.accessToken != original.accessToken) {
        throw StateError('enrollment session changed');
      }
      final request = http.Request('POST', Uri.parse(
        '${SupabaseBackendConfig.url}/functions/v1/apple-native-enrollment',
      ))
        ..followRedirects = false
        ..headers.addAll({
          'apikey': SupabaseBackendConfig.publishableKey,
          'authorization': 'Bearer ${original.accessToken}',
          'content-type': 'application/json',
        })
        ..body = jsonEncode({'password': password, 'id_token': credential.idToken,
          'nonce': credential.nonce});
      password = '';
      final response = await transport.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw StateError('enrollment not confirmed');
      final bytes = await response.stream.fold<List<int>>(<int>[], (buffer, chunk) {
        if (buffer.length + chunk.length > 4096) throw StateError('enrollment not confirmed');
        return buffer..addAll(chunk);
      }).timeout(const Duration(seconds: 10));
      final receipt = jsonDecode(utf8.decode(bytes));
      if (receipt is! Map || receipt['linked'] != true || receipt['user_id'] != original.user.id) {
        throw StateError('enrollment not confirmed');
      }
      final user = (await source.client.auth.getUser(original.accessToken)
          .timeout(const Duration(seconds: 10))).user;
      if (!mounted || !_foreground || action != _actionGeneration ||
          source.client.auth.currentSession?.accessToken != original.accessToken ||
          user?.id != original.user.id ||
          user?.identities?.any((identity) => identity.provider == 'apple' &&
              identity.userId == original.user.id) != true) {
        throw StateError('enrollment not confirmed');
      }
      setState(() { _complete = true; _message = '同じSKOアカウントへのApple連携を確認しました。'; });
      widget.onLinked?.call();
    } catch (_) {
      if (mounted && action == _actionGeneration) {
        setState(() => _message = 'Apple連携を確認できませんでした。連携状況を再確認してください。');
      }
    } finally {
      preparation.dispose();
      transport.close();
      if (mounted && action == _actionGeneration) {
        setState(() { _busy = false; _pending = false; });
      }
    }
  }

  Future<void> _start() async {
    final source = _source;
    if (source == null || _readiness != AppleLinkReadiness.ready || _busy || _pending || _confirming) return;
    final original = source.client.auth.currentSession;
    if (original == null || original.isExpired) return;
    final confirmationGeneration = _actionGeneration;
    _confirming = true;
    final confirmed = await showDialog<bool>(context: context,
      builder: (context) {
        _confirmationContext = context;
        return AlertDialog(
        title: const Text('このアカウントにAppleを追加'),
        content: const Text('登録済みのGoogleとの連携と、直近5分以内の外部アカウント認証を確認します。'
          'Appleの本人確認後も同じSKOアカウントと会社を使います。'
          '別アカウントの新規登録は行いません。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('戻る')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Appleの本人確認へ'))]);
      });
    _confirmationContext = null;
    _confirming = false;
    if (!mounted || confirmed != true ||
        confirmationGeneration != _actionGeneration ||
        source.client.auth.currentSession?.user.id != original.user.id ||
        source.client.auth.currentSession?.accessToken != original.accessToken) {
      return;
    }
    final action = ++_actionGeneration;
    setState(() { _busy = true; _pending = true; _message = null; });
    try {
      await source.begin();
      if (!mounted || action != _actionGeneration) return;
      setState(() { _busy = false; });
      await _verify();
    } catch (_) {
      if (!mounted || action != _actionGeneration) return;
      setState(() { _busy = false; _pending = false;
        _message = 'Apple追加を完了できませんでした。現在のログイン方法を保持して、提供状態を再確認してください。'; });
    }
  }

  Future<void> _verify() async {
    if (!mounted || !_foreground || !_pending || _busy || _checking) return;
    _checking = true;
    final action = _actionGeneration;
    try {
      final complete = await _source!.verifyCompletion();
      if (!mounted || action != _actionGeneration) return;
      if (complete) {
        setState(() { _pending = false; _complete = true;
          _message = '同じSKOアカウントへのApple連携を確認しました。'; });
        widget.onLinked?.call();
      }
    } catch (_) {
      if (action != _actionGeneration) return;
      await _source?.cancel();
      if (!mounted || action != _actionGeneration) return;
      setState(() { _pending = false;
        _message = '本人のアカウントとの連携を確認できませんでした。'; });
    } finally { _checking = false; }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) { if (!_nativeEnrollmentEnabled) _verify(); _load(); }
  }

  @override
  void dispose() {
    _generation++;
    _actionGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    if (widget.source == null) {
      _source?.dispose();
    } else {
      _source?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16), child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Appleを追加'),
      if (_loading) const LinearProgressIndicator(),
      if (!_loading && !_pending && !_complete && !_nativeEnrollmentEnabled) Text(switch (_readiness) {
        AppleLinkReadiness.ready => '追加前の確認ができました。Appleの本人確認と連携はまだ完了していません。',
        AppleLinkReadiness.linked => 'このアカウントへのApple連携は確認済みです。',
        AppleLinkReadiness.enrollmentPreparing => 'Appleアカウントの追加は準備中です。Google・Face IDと現在の会社設定は引き続き使えます。',
        AppleLinkReadiness.providerDisabled => 'Apple連携は提供準備中です。現在のログイン方法を引き続き使えます。',
        AppleLinkReadiness.recentOAuthRequired => '同じログインを保った追加の本人確認が必要です。この接続は準備中です。',
        AppleLinkReadiness.loginRequired => '現在のログインを確認できません。Apple追加は開始できません。',
        AppleLinkReadiness.googleRequired => '登録済みGoogleとの連携を確認できないため、Apple追加は開始できません。',
        _ => 'Appleの提供状態または本人の登録状況を確認できませんでした。再確認してください。',
      }),
      if (_nativeEnrollmentEnabled && _source != null &&
          SupabaseBackendConfig.url == 'https://ztktgquxvcxcjxtluspu.supabase.co' &&
          !_loading && !_pending && !_complete && _readiness != AppleLinkReadiness.linked)
        TextButton(onPressed: _busy ? null : _startNativeEnrollment,
          child: const Text('本人確認してAppleを追加')),
      if (!_nativeEnrollmentEnabled && _readiness == AppleLinkReadiness.ready && !_loading && !_pending && !_complete)
        TextButton(onPressed: _busy ? null : _start,
          child: const Text('このアカウントにAppleを追加')),
      if (!_pending) TextButton(onPressed: _busy || _loading ? null : _load,
        child: const Text('Apple追加の状態を再確認')),
      const ExpansionTile(title: Text('？ Apple追加について'), children: [
        Padding(padding: EdgeInsets.all(8), child: Text(
          'Appleは現在のSKOアカウントへ追加します。Google・Face IDと会社の所属を保持します。'
          '追加前の提供状態と本人確認、追加後の同じアカウントへの連携を確認します。'
          '追加の本人確認が準備中の場合は開始できません。ログアウトせず、現在の方法を引き続き使えます。')),
      ]),
      if (_pending) const Text('Appleの本人確認と同じアカウントへの連携を確認しています。'),
      if (_pending && !_nativeEnrollmentEnabled) TextButton(onPressed: () async {
        _actionGeneration++;
        await _source?.cancel();
        if (mounted) setState(() { _pending = false; _busy = false; });
      }, child: const Text('Apple追加の確認を中止')),
      if (_message != null) Text(_message!),
    ])));
}
