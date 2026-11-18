import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/secondary_reset_session_guard.dart';
import 'company_registration_page.dart';

class CompanyReviewAccessPage extends StatefulWidget {
  const CompanyReviewAccessPage({super.key, required this.client});
  final SupabaseClient client;

  @override
  State<CompanyReviewAccessPage> createState() =>
      _CompanyReviewAccessPageState();
}

class _CompanyReviewAccessPageState extends State<CompanyReviewAccessPage> {
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  SecondaryResetSessionGuard? _guard;
  Timer? _expiry;
  bool _unlocked = false;
  bool _busy = false;
  String? _message;

  Session? get _session => widget.client.auth.currentSession;

  void _lock(String message) {
    _expiry?.cancel();
    _primary.clear();
    _secondary.clear();
    if (mounted) {
      setState(() {
        _unlocked = false;
        _message = message;
      });
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    unawaited(_guard?.close());
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || _primary.text.isEmpty || _secondary.text.isEmpty) return;
    final session = _session;
    if (session == null ||
        SecondaryResetSessionGuard.identityOf(session) == null) {
      _lock('ログイン状態を確認してください。');
      return;
    }

    final primary = _primary.text;
    final secondary = _secondary.text;
    _primary.clear();
    _secondary.clear();
    unawaited(_guard?.close());
    final guard = SecondaryResetSessionGuard(
      currentSession: () => _session,
      changes: widget.client.auth.onAuthStateChange,
      onInvalidated: () => _lock('ログイン状態が変わりました。'),
    );
    _guard = guard;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final verified = await widget.client
          .rpc(
            'verify_company_review_passwords',
            params: {'p_primary': primary, 'p_secondary': secondary},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      await guard.checkAfterQueuedEvents();
      if (!mounted) return;
      if (verified != true) {
        _lock('本人確認できませんでした。入力を確認してください。繰り返し失敗した場合は5分お待ちください。');
        return;
      }
      _expiry = Timer(const Duration(minutes: 2, seconds: 55), () {
        _lock('本人確認の有効時間が切れました。もう一度確認してください。');
      });
      setState(() => _unlocked = true);
    } catch (_) {
      _lock('本人確認を完了できませんでした。時間をおいてお試しください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked && _guard?.isCurrent == true) {
      return CompanyRegistrationPage(client: widget.client, review: true);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('会社からの利用申請')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'マスター本人確認',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('会社の申請を審査するには、2つのパスワードを入力してください。'),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _primary,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'ログイン用パスワード',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _secondary,
                        enabled: !_busy,
                        obscureText: true,
                        onSubmitted: (_) => _verify(),
                        decoration: const InputDecoration(labelText: '第2パスワード'),
                      ),
                      if (_message case final message?) ...[
                        const SizedBox(height: 16),
                        Text(
                          message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _verify,
                        child: Text(_busy ? '確認中…' : '本人確認して開く'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
