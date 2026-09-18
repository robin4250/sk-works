import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../branding/product_brand.dart';
import '../../data/supabase_backend.dart';

class SupabaseAuthGate extends StatefulWidget {
  const SupabaseAuthGate({
    super.key,
    required this.homeBuilder,
  });

  final Widget Function(VoidCallback onSignOut) homeBuilder;

  @override
  State<SupabaseAuthGate> createState() => _SupabaseAuthGateState();
}

class _SupabaseAuthGateState extends State<SupabaseAuthGate> {
  late Future<_GateState> _state;

  SupabaseClient get _client => SupabaseBackend.client;

  @override
  void initState() {
    super.initState();
    _state = _loadState();
  }

  Future<_GateState> _loadState() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const _GateState.unauthenticated();
    }

    final memberships = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);

    if (memberships.isEmpty) {
      return _GateState.needsCompany(user.email ?? '');
    }

    return _GateState.authenticated(user.email ?? '');
  }

  void _reload() {
    setState(() {
      _state = _loadState();
    });
  }

  Future<void> _signOut() async {
    await _client.auth.signOut();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateState>(
      future: _state,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }
        if (snapshot.hasError) {
          return _ErrorScreen(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }

        final state = snapshot.data ?? const _GateState.unauthenticated();
        return switch (state.status) {
          _GateStatus.unauthenticated => AuthPage(onAuthenticated: _reload),
          _GateStatus.needsCompany => CompanySetupPage(
              email: state.email,
              onCreated: _reload,
              onSignOut: _signOut,
            ),
          _GateStatus.authenticated => widget.homeBuilder(_signOut),
        };
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _registerMode = false;
  String? _message;

  SupabaseClient get _client => SupabaseBackend.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.length < 6) {
      setState(() {
        _message = 'メールアドレスと6文字以上のパスワードを入力してください。';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      if (_registerMode) {
        final response = await _client.auth.signUp(
          email: email,
          password: password,
        );
        if (!mounted) return;
        if (response.session == null) {
          setState(() {
            _registerMode = false;
            _message = '確認メールを送信しました。メール認証後にログインしてください。';
          });
          return;
        }
      } else {
        await _client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
      widget.onAuthenticated();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = '処理に失敗しました: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(ProductBrand.displayName)),
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
                        _registerMode ? '初回アカウント登録' : 'ログイン',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _registerMode
                            ? '最初の管理者アカウントを作成します。'
                            : '${ProductBrand.displayName}のクラウドデータに接続します。',
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'メールアドレス',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: const InputDecoration(
                          labelText: 'パスワード',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_registerMode ? Icons.person_add : Icons.login),
                        label: Text(_registerMode ? 'アカウントを作成' : 'ログイン'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _registerMode = !_registerMode;
                                  _message = null;
                                });
                              },
                        child: Text(
                          _registerMode
                              ? 'すでにアカウントがある方'
                              : '初めて使う方はこちら',
                        ),
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

class CompanySetupPage extends StatefulWidget {
  const CompanySetupPage({
    super.key,
    required this.email,
    required this.onCreated,
    required this.onSignOut,
  });

  final String email;
  final VoidCallback onCreated;
  final Future<void> Function() onSignOut;

  @override
  State<CompanySetupPage> createState() => _CompanySetupPageState();
}

class _CompanySetupPageState extends State<CompanySetupPage> {
  final _companyController = TextEditingController();
  bool _busy = false;
  String? _error;

  SupabaseClient get _client => SupabaseBackend.client;

  @override
  void dispose() {
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _createCompany() async {
    final name = _companyController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '会社名を入力してください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _client.rpc(
        'create_company',
        params: {'company_name': name},
      );
      widget.onCreated();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '会社登録に失敗しました: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('初期設定'),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onSignOut,
            child: const Text('ログアウト'),
          ),
        ],
      ),
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
                        '会社を登録',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(widget.email),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _companyController,
                        decoration: const InputDecoration(
                          labelText: '会社名',
                          prefixIcon: Icon(Icons.business_outlined),
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
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _busy ? null : _createCompany,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('${ProductBrand.displayName}を開始'),
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

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('再試行')),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GateStatus { unauthenticated, needsCompany, authenticated }

class _GateState {
  const _GateState._(this.status, this.email);

  const _GateState.unauthenticated()
      : this._(_GateStatus.unauthenticated, '');
  const _GateState.needsCompany(String email)
      : this._(_GateStatus.needsCompany, email);
  const _GateState.authenticated(String email)
      : this._(_GateStatus.authenticated, email);

  final _GateStatus status;
  final String email;
}
