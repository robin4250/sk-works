import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'panel_seven_repository.dart';
import 'apple_account_link_card.dart';
import 'login_method_enrollment_card.dart';
import 'login_method_enrollment_repository.dart';

class PanelSevenPage extends StatefulWidget {
  const PanelSevenPage({super.key, required this.repository});
  final PanelSevenSource repository;

  @override
  State<PanelSevenPage> createState() => _PanelSevenPageState();
}

class _PanelSevenPageState extends State<PanelSevenPage>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _subscription;
  LoginMethodEnrollmentRepository? _enrollment;
  PanelSevenSnapshot? _snapshot;
  PanelSevenSnapshot? _primaryPasswordReceipt;
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enrollment = LoginMethodEnrollmentRepository.maybeCreate();
    _subscription = widget.repository.changes.listen((event) {
      final receipt = _primaryPasswordReceipt;
      if (receipt != null && (event.event == AuthChangeEvent.signedOut ||
          !widget.repository.isCurrent(receipt))) {
        setState(() => _primaryPasswordReceipt = null);
      }
      final snapshot = _snapshot;
      // Never use the event's session: a delayed logout event may carry B.
      if (_foreground && (snapshot == null || !widget.repository.isCurrent(snapshot))) {
        _load();
      }
    });
    _load();
  }

  Future<void> _load() async {
    if (!_foreground || !mounted) return;
    final generation = ++_generation;
    setState(() {
      final receipt = _primaryPasswordReceipt;
      if (receipt != null && !widget.repository.isCurrent(receipt)) {
        _primaryPasswordReceipt = null;
      }
      _snapshot = null;
      _loading = true;
      _failed = false;
    });
    try {
      final snapshot = await widget.repository.load();
      if (!mounted || !_foreground || generation != _generation) return;
      if (!widget.repository.isCurrent(snapshot)) {
        throw StateError('session_changed');
      }
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || !_foreground || generation != _generation) return;
      setState(() { _failed = true; _loading = false; });
    }
  }

  Future<void> _refreshRegistration() async {
    final generation = ++_generation;
    try {
      final snapshot = await widget.repository.load();
      if (!mounted || !_foreground || generation != _generation ||
          !widget.repository.isCurrent(snapshot)) { return; }
      setState(() => _snapshot = snapshot);
    } catch (_) {
      // Keep the operation receipt visible; explicit reload remains available.
    }
  }

  void _recordPrimaryPasswordSave() {
    final snapshot = _snapshot;
    if (!mounted || !_foreground || snapshot == null ||
        !widget.repository.isCurrent(snapshot)) { return; }
    setState(() => _primaryPasswordReceipt = snapshot);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _generation++;
      setState(() { _snapshot = null; _loading = true; });
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    _enrollment?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _help() {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('アカウント設定について'),
      content: const SingleChildScrollView(child: Text(
        'ログインと連絡先、重要情報を開く本人確認、ログイン方法の追加を分けて表示します。'
        '登録済みのログイン方法と本人の認証設定を確認します。'
        '連携済みの方法と、今回のログインに使った方法は別です。'
        '第一パスワードの登録の有無は取得できません。未設定や登録失敗を示すものではありません。'
        '第一パスワードを設定・変更から保存できます。既にある場合は変更します。'
        'この画面で保存に成功した場合だけ、同じログイン状態の間は保存確認を表示します。'
        '他のログイン状態や次回起動での登録有無を示すものではありません。'
        '利用可能な確認済みメールまたは確認済み電話番号があれば設定できます。電話番号の登録は必須ではありません。第二パスワードは変更しません。'
        '電話番号を登録からSMSコードを送り、コード確認後に登録を完了します。'
        'メール未登録の場合はメール確認後に第一パスワードを設定します。'
        '提供準備中の方法は登録できません。サーバーが本人再確認を求める場合は、登録済みの連絡先へ確認コードを送って保存します。'
        '第二パスワードは重要情報用で、ログイン用とは別です。'
        '第二パスワードの設定済み表示は、マスター管理の権限や専用パスワードの設定状況を示しません。'
        'Face ID / Touch IDは端末内の本人確認で、'
        'Apple / Googleとの連携や電話番号の所有確認とは異なります。'
        'Apple追加は提供設定が整った場合だけ、登録済みGoogleで直近にログインした本人が行えます。'
        'Appleの本人確認後、同じアカウントへの連携を確認します。会社・権限・パスワードは変更しません。'
        'マスター専用設定は従来のマスター本人確認の中で管理します。')),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'))],
    ));
  }

  Widget _item(String title, String detail, {String? keyName}) => Card(
    child: ListTile(key: keyName == null ? null : ValueKey(keyName),
      title: Text(title), subtitle: Text(detail)),
  );

  String _provider(String provider) => switch (provider) {
    'google' => 'Google',
    'apple' => 'Apple',
    'phone' => '電話番号',
    'email' => 'メールアドレス',
    _ => 'その他の連携方法',
  };

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('アカウント設定'),
        actions: [IconButton(tooltip: '使い方', onPressed: _help,
            icon: const Icon(Icons.help_outline))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed || snapshot == null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('本人のアカウント情報を確認できませんでした。'),
                  TextButton(onPressed: _load, child: const Text('再読み込み')),
                ]))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('ログインと連絡先', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  _item('連携済みのログイン方法',
                    snapshot.providers.isEmpty ? '確認できません'
                        : snapshot.providers.map(_provider).join('・'),
                    keyName: 'account-providers'),
                  _item('現在のセッションの認証記録',
                    snapshot.sessionMethods.isEmpty ? '確認できません'
                        : snapshot.sessionMethods.map((method) =>
                            switch (method) {
                              'password' => 'パスワード認証',
                              'oauth' => '外部アカウント認証（提供元は特定できません）',
                              'otp' => 'ワンタイムコード認証',
                              'totp' => '認証アプリ',
                              _ => '組織アカウント認証',
                            }).join('・'),
                    keyName: 'account-session-methods'),
                  _item('第一パスワード（ログイン用）',
                    _primaryPasswordReceipt != null &&
                        widget.repository.isCurrent(_primaryPasswordReceipt!) &&
                        _primaryPasswordReceipt!.actorId == snapshot.actorId
                      ? 'この画面で第一パスワードの保存を確認しました。'
                        '現在のログイン状態での保存確認です。'
                      : '登録の有無は取得できません（未設定・登録失敗を示すものではありません）。'
                      '下の「第一パスワードを設定・変更」から保存できます。'
                      '電話番号が未登録でも、利用可能な確認済みメールがあれば設定できます。',
                      keyName: 'account-primary-password'),
                  _item('メールアドレス',
                      snapshot.email?.isNotEmpty == true
                          ? '${snapshot.email}\n${snapshot.emailConfirmed ? "登録確認済み" : "未確認"}'
                          : '未登録'),
                  _item('電話番号',
                      snapshot.phone?.isNotEmpty == true
                          ? '${snapshot.phone}\n${snapshot.phoneConfirmed ? "登録確認済み（今回の番号所有確認ではありません）" : "未確認"}'
                          : '未登録',
                      keyName: 'account-phone'),
                  const SizedBox(height: 12),
                  const Text('重要情報を開く本人確認', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  _item('第二パスワード（重要情報用）',
                      snapshot.secondaryConfigured == null ? '確認できません'
                          : snapshot.secondaryConfigured! ? '設定済み' : '未設定',
                      keyName: 'account-secondary-password'),
                  _item('Face ID / Touch ID',
                      '重要情報用の端末内設定：${snapshot.biometricEnabled == null ? "確認できません" : snapshot.biometricEnabled! ? "有効" : "未設定"}\n'
                      'この端末での利用：${snapshot.biometricAvailable == null ? "確認できません" : snapshot.biometricAvailable! ? "生体認証の登録あり（本人確認は未実施）" : "生体認証の未登録または利用不可"}\n'
                      '端末内の本人確認です。ログイン方法の連携や番号所有確認とは別です。',
                      keyName: 'panel-seven-biometric'),
                  const SizedBox(height: 12),
                  const Text('ログイン方法の追加', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
                  LoginMethodEnrollmentCard(source: _enrollment,
                    onChanged: _refreshRegistration,
                    onPrimaryPasswordSaved: _recordPrimaryPasswordSave),
                  const AppleAccountLinkCard(),
                  TextButton(onPressed: _load, child: const Text('最新の状態を確認')),
                ]),
    );
  }
}
