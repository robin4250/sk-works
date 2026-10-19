import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import 'apple_account_link.dart';

class AppleAccountLinkCard extends StatefulWidget {
  const AppleAccountLinkCard({super.key, this.source});
  final AppleAccountLink? source;
  @override
  State<AppleAccountLinkCard> createState() => _AppleAccountLinkCardState();
}

class _AppleAccountLinkCardState extends State<AppleAccountLinkCard>
    with WidgetsBindingObserver {
  AppleAccountLink? _source;
  StreamSubscription<dynamic>? _events;
  bool _enabled = false, _busy = false, _pending = false, _checking = false;
  bool _complete = false;
  bool _foreground = true;
  int _generation = 0, _actionGeneration = 0;
  String? _message;

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
      if (!_pending && mounted) setState(() { _message = null; _complete = false; });
      _verify();
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final enabled = await _source?.providerEnabled() ?? false;
    if (!mounted || generation != _generation) return;
    setState(() { _enabled = enabled; });
  }

  Future<void> _start() async {
    final source = _source;
    if (source == null || !_enabled || _busy || _pending) return;
    final confirmed = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('このアカウントにAppleを追加'),
        content: const Text('登録済みのGoogleとの連携と、直近5分以内の外部アカウント認証を確認します。'
          'Appleの本人確認後も同じSKOアカウントと会社を使います。'
          '別アカウントの新規登録は行いません。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('戻る')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Appleの本人確認へ'))]));
    if (!mounted || confirmed != true) return;
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
        _message = 'Appleを追加できませんでした。登録済みGoogleで直近にログインし、'
          'Apple側とサーバー側の提供設定を確認してください。'; });
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
    if (_foreground) { _verify(); _load(); }
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
      if (!_enabled) const Text('既存アカウントへのApple連携は準備中です。'
        'Apple側・サーバー側の設定と本人再認証の確認が必要です。'
        '今は登録済みの方法でログインしてください。'),
      if (_enabled && !_pending && !_complete) TextButton(onPressed: _busy ? null : _start,
        child: const Text('このアカウントにAppleを追加')),
      if (_pending) const Text('Appleの本人確認と同じアカウントへの連携を確認しています。'),
      if (_pending) TextButton(onPressed: () async {
        _actionGeneration++;
        await _source?.cancel();
        if (mounted) setState(() { _pending = false; _busy = false; });
      }, child: const Text('Apple追加の確認を中止')),
      if (_message != null) Text(_message!),
    ])));
}
