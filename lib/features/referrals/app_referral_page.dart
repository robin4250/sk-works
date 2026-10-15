import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_referral_repository.dart';
import 'app_referral_composer.dart';

class AppReferralPage extends StatefulWidget {
  const AppReferralPage({
    super.key,
    required this.repository,
    this.master = false,
    this.friendInvite = false,
    this.initialName = '',
    this.initialPhone = '',
  });
  final AppReferralRepository repository;
  final bool master;
  final bool friendInvite;
  final String initialName;
  final String initialPhone;
  @override
  State<AppReferralPage> createState() => _AppReferralPageState();
}

class _AppReferralPageState extends State<AppReferralPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _url = TextEditingController();
  Map<String, dynamic>? _snapshot;
  String? _error;
  bool _busy = false;
  late final AppReferralComposer _composer;
  @override
  void initState() {
    super.initState();
    _composer = AppReferralComposer(
      actorId: () => widget.repository.client.auth.currentUser?.id,
      prepare: (name, phone, friendInvite) => widget.repository.prepare(
        name, phone, friendInvite: friendInvite,
      ),
      openComposer: (uri) => launchUrl(uri),
      recordOpened: widget.repository.recordComposerOpened,
    );
    _name.text = widget.initialName;
    _phone.text = widget.initialPhone;
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.repository.load(master: widget.master);
      if (!mounted) return;
      setState(() {
        _snapshot = data;
        _url.text = data['distribution_url']?.toString() ?? '';
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '招待機能を読み込めません。サーバー設定・利用権限を確認してください。');
      }
    }
  }

  Future<void> _send() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final outcome = await _composer.send(
        name: _name.text,
        phone: _phone.text,
        friendInvite: widget.friendInvite,
      );
      if (!mounted) {
        return;
      }
      final message = switch (outcome) {
        AppReferralComposeOutcome.launchFailed =>
          'SMS作成画面を開けませんでした。同じ入力で再試行すると準備済みの招待を使います。',
        AppReferralComposeOutcome.recordFailed =>
          'SMS作成画面は開きましたが履歴を更新できませんでした。「履歴を更新」で記録だけ再試行できます。送信・配達は未確認です。',
        AppReferralComposeOutcome.prepareFailed =>
          '招待を準備できません。名前・電話番号・配布URL・利用権限を確認してください。',
        AppReferralComposeOutcome.actorChanged =>
          'ログイン情報が変わりました。画面を開き直してください。',
        _ => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      // Preparation may have saved a history row even if the local composer failed.
      if (mounted) {
        await _load();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.repository.saveSettings(
        enabled: _snapshot!['enabled'] == true,
        publicEnabled: _snapshot!['public_enabled'] == true,
        notifyMaster: _snapshot!['notify_master'] == true,
        url: _url.text,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('設定を保存できませんでした。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    final rows = data?['invitations'] as List? ?? const [];
    final rankings = data?['rankings'] as List? ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.master
              ? 'SKO ID管理・紹介記録'
              : widget.friendInvite
              ? '友達追加からSKOへ招待'
              : 'SKOアプリ招待',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('SKOアプリ招待の使い方'),
                content: const Text(
                  '本人の招待と紹介履歴は「設定」→「SKOアプリ招待・自分の紹介履歴」から開きます。会社owner/adminは招待機能ON、一般利用者は一般公開もONの場合に利用できます。OFFや権限不足は入口に表示し、開く直前にも利用状態を再確認します。配布URL未登録でも自分の履歴は確認できますが、SMS作成はできません。Masterは「設定」→「Master 機能設定」→「SKOアプリ招待・紹介管理」から設定・全体履歴を確認できます。機能と一般公開は初期OFFです。正式な配布URLを登録し、機能ONでMasterの招待入口が表示されます。名前・電話番号を入力して送信を押すとSMS作成画面が開きます。送信・配達は確認できません。社員の初回登録とは別の紹介機能です。紹介元確定とポイント付与はまだ接続されていません。SMS起動失敗は同じ入力で再試行でき、起動後の記録失敗は「履歴を更新」で記録だけを再試行します。画面を閉じると再試行状態は引き継ぎません。ポイント数・使い道は未定です。履歴はこの画面で確認できます。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('再読み込み')),
            ],
            if (data == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (data != null) ...[
              if (widget.master) ...[
                if (data['attribution_connected'] != true)
                  const Text(
                    '新規登録者の本人確認・紹介元確定・ポイント付与・登録完了通知は未接続です。登録済みとは表示しません。',
                  ),
                for (final entry in {
                  'enabled': '招待機能',
                  'public_enabled': '一般ユーザーへ公開',
                  'notify_master': '登録完了をマスターへ通知',
                }.entries)
                  SwitchListTile(
                    title: Text(entry.value),
                    value: data[entry.key] == true,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => data[entry.key] = value),
                  ),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: '配布URL（TestFlight／公開後のストア）',
                  ),
                ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('設定を保存'),
                ),
              ] else if (data['can_invite'] == true) ...[
                TextField(
                  controller: _name,
                  enabled: !_busy && !_composer.needsRecordRetry,
                  decoration: const InputDecoration(labelText: '名前'),
                ),
                TextField(
                  controller: _phone,
                  enabled: !_busy && !_composer.needsRecordRetry,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '電話番号'),
                ),
                if (data['distribution_url_ready'] != true)
                  const Text('配布URLが未登録です。管理者へTestFlight URLの設定を依頼してください。'),
                FilledButton(
                  onPressed: _busy || data['distribution_url_ready'] != true
                      ? null
                      : _send,
                  child: Text(_composer.needsRecordRetry ? '履歴を更新' : '送信'),
                ),
                const Text('SMS作成画面を開きます。送信・配達を保証する表示ではありません。'),
              ] else
                const Text('現在、招待機能は利用できません。'),
              const Divider(),
              const Text('招待履歴'),
              for (final row in rows)
                ListTile(
                  title: Text(
                    '${row['recipient_name']}　${row['recipient_phone']}',
                  ),
                  subtitle: Text(
                    '${referralJapanTime(row['created_at'].toString())}\n${row['source_label']}／${row['state_label']}'
                    '${widget.master ? '\n招待者: ${row['inviter_name']}／${row['company_name']}' : ''}',
                  ),
                ),
              if (rows.isEmpty) const Text('招待履歴はありません。'),
              if (widget.master) ...[
                const Divider(),
                const Text('紹介ランキング（ポイント利用方法・付与数は未設定）'),
                for (var i = 0; i < rankings.length; i++)
                  ListTile(
                    title: Text(
                      '${i + 1}位　${rankings[i]['name']}　${rankings[i]['company_name']}',
                    ),
                    subtitle: Text(
                      '登録 ${rankings[i]['registration_count']}人／ポイント ${rankings[i]['points'] ?? '未設定'}',
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
