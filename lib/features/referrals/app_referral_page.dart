import 'app_referral_actor_scope.dart';
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
    this.invitationKind = 'app',
    this.guideKind = '',
  });
  final AppReferralRepository repository;
  final bool master;
  final bool friendInvite;
  final String initialName;
  final String initialPhone;
  final String invitationKind;
  final String guideKind;
  @override
  State<AppReferralPage> createState() => _AppReferralPageState();
}

class _AppReferralPageState extends State<AppReferralPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _url = TextEditingController();
  final _testflight = TextEditingController();
  final _web = TextEditingController();
  final _guide = TextEditingController();
  String _channel = 'testflight';
  bool _channelInitialized = false;
  bool get _usesDistribution => _snapshot?['distribution_channels'] is List;
  Map<String, dynamic>? _snapshot;
  String? _error;
  bool _busy = false;
  late final AppReferralComposer _composer;
  late final AppReferralActorScope _actorScope;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    _actorScope = AppReferralActorScope(
      widget.repository,
      onInvalidated: () {
        if (!mounted) return;
        _loadGeneration++;
        _name.clear();
        _phone.clear();
        _url.clear();
        _testflight.clear();
        _web.clear();
        _guide.clear();
        setState(() {
          _snapshot = null;
          _busy = false;
          _error = 'ログイン情報が変わりました。画面を開き直してください。';
        });
      },
    );
    _composer = AppReferralComposer(
      actorId: () => _actorScope.check() ? _actorScope.actor : null,
      prepare: (name, phone, friendInvite) => _usesDistribution
          ? widget.repository.prepareDistribution(
              name,
              phone,
              _channel,
              friendInvite ? 'friend' : widget.invitationKind,
            )
          : widget.repository.prepare(name, phone, friendInvite: friendInvite),
      openComposer: (uri) => launchUrl(uri),
      recordOpened: widget.repository.recordComposerOpened,
    );
    _name.text = widget.initialName;
    _phone.text = widget.initialPhone;
    _load();
  }

  @override
  void dispose() {
    _actorScope.dispose();
    _name.dispose();
    _phone.dispose();
    _url.dispose();
    _testflight.dispose();
    _web.dispose();
    _guide.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppReferralPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.master != widget.master ||
        oldWidget.friendInvite != widget.friendInvite ||
        oldWidget.invitationKind != widget.invitationKind) {
      _actorScope.invalidate();
    }
  }

  Future<void> _load() async {
    if (!_actorScope.check()) {
      if (mounted) {
        setState(() {
          _snapshot = null;
          _error = 'ログイン情報が変わりました。画面を開き直してください。';
        });
      }
      return;
    }
    final generation = ++_loadGeneration;
    try {
      final data = await widget.repository.load(master: widget.master);
      if (!mounted || !_actorScope.check() || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _snapshot = data;
        final links = data['distribution_links'];
        if (links is Map) {
          _testflight.text = links['testflight']?.toString() ?? '';
          _web.text = links['web']?.toString() ?? '';
          _guide.text = links['public']?.toString() ?? '';
        }
        if (!_channelInitialized && data['distribution_channels'] is List) {
          _channel = 'testflight';
          final channels = data['distribution_channels'] as List;
          if (!channels.any(
                (c) => c is Map && c['key'] == _channel && c['ready'] == true,
              )) {
            final ready = channels.whereType<Map>().where(
              (c) => c['ready'] == true,
            );
            if (ready.isNotEmpty) {
              _channel = ready.first['key'].toString();
            }
          }
          _channelInitialized = true;
        }
        _url.text = data['distribution_url']?.toString() ?? '';
        _error = null;
      });
    } catch (_) {
      if (mounted && _actorScope.check() && generation == _loadGeneration) {
        setState(() => _error = '招待機能を読み込めません。サーバー設定・利用権限を確認してください。');
      }
    }
  }

  Future<void> _send() async {
    if (!_actorScope.check() ||
        _busy ||
        (widget.friendInvite && !_usesDistribution)) {
      return;
    }
    setState(() => _busy = true);
    try {
      final outcome = await _composer.send(
        name: _name.text,
        phone: _phone.text,
        friendInvite: widget.friendInvite,
        distributionKey: _usesDistribution
            ? '$_channel:${widget.invitationKind}'
            : '',
        guideUrl: switch (widget.friendInvite ? 'friend' : widget.guideKind) {
          'friend' => 'https://skojapan.com/install/friends/',
          'client' => 'https://skojapan.com/install/client/',
          'partner' => 'https://skojapan.com/install/partner/',
          'employee' => 'https://skojapan.com/install/employee/',
          _ => 'https://skojapan.com/install/invite/',
        },
      );
      if (!mounted || !_actorScope.check()) {
        return;
      }
      final message = switch (outcome) {
        AppReferralComposeOutcome.launchFailed =>
          'SMS作成画面を開けませんでした。同じ入力で再試行すると準備済みの招待を使います。',
        AppReferralComposeOutcome.recordFailed =>
          'SMS作成画面は開きましたが履歴を更新できませんでした。「履歴を更新」で記録だけ再試行できます。送信・配達は未確認です。',
        AppReferralComposeOutcome.prepareFailed =>
          '招待を準備できません。名前・電話番号・配布URL・利用権限を確認してください。',
        AppReferralComposeOutcome.actorChanged => 'ログイン情報が変わりました。画面を開き直してください。',
        _ => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      // Preparation may have saved a history row even if the local composer failed.
      if (mounted && _actorScope.check()) {
        await _load();
      }
      if (mounted && _actorScope.check()) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveLinks() async {
    if (!_actorScope.check() || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.saveDistributionLinks(
        _testflight.text,
        _web.text,
        _guide.text,
      );
      await _load();
    } catch (_) {
      if (mounted && _actorScope.check()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配布先URLを保存できませんでした。URL・利用権限を確認してください。')),
        );
      }
    } finally {
      if (mounted && _actorScope.check()) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_actorScope.check() || _busy || _snapshot == null) return;
    setState(() => _busy = true);
    try {
      final enabled = _snapshot!['enabled'] == true;
      final publicEnabled = _snapshot!['public_enabled'] == true;
      final notifyMaster = _snapshot!['notify_master'] == true;
      if (_usesDistribution) {
        await widget.repository.saveSettingsPreservingDistributionUrl(
          enabled: enabled,
          publicEnabled: publicEnabled,
          notifyMaster: notifyMaster,
        );
      } else {
        await widget.repository.saveSettings(
          enabled: enabled,
          publicEnabled: publicEnabled,
          notifyMaster: notifyMaster,
          url: _url.text,
        );
      }
      await _load();
    } catch (_) {
      if (mounted && _actorScope.check()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('設定を保存できませんでした。既存の配布URL・利用権限を確認し、再読み込みしてください。'),
          ),
        );
      }
    } finally {
      if (mounted && _actorScope.check()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    final rows = data?['invitations'] as List? ?? const [];
    final rankings = data?['rankings'] as List? ?? const [];
    final channels = (data?['distribution_channels'] as List? ?? const [])
        .whereType<Map>()
        .where(
          (c) => c['key'] != 'public' || c['ready'] == true,
        )
        .toList();
    final channelReady = _usesDistribution
        ? channels.any((c) => c['key'] == _channel && c['ready'] == true)
        : !widget.friendInvite && data?['distribution_url_ready'] == true;
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
                  '配布先の種類を選び、後からWEB版URLだけ追加送信できます。友達招待も利用可能なTestFlight・WEB版・公開版から選べます。URL追加送信ではログイン情報を再発行しません。ホーム・メニューの「SKO招待」から名前・電話番号を入力できます。取引会社登録・協力会社登録の一覧上部の「招待」では登録会社を選ぶか電話番号を直接入力します。代表者の電話番号を引き継ぎ、送信前に変更できます。招待の送信だけで社員所属・友達承認・会社連携が成立することはありません。本人の招待と紹介履歴は「設定」→「SKOアプリ招待・自分の紹介履歴」から開きます。会社owner/adminは招待機能ON、一般利用者は一般公開もONの場合に利用できます。OFFや権限不足は入口に表示し、開く直前にも利用状態を再確認します。配布URL未登録でも自分の履歴は確認できますが、SMS作成はできません。Masterは「設定」→「Master 機能設定」→「SKOアプリ招待・紹介管理」から設定・全体履歴を確認できます。機能と一般公開は初期OFFです。正式な配布URLを登録し、機能ONでMasterの招待入口が表示されます。名前・電話番号を入力して送信を押すとSMS作成画面が開きます。送信・配達は確認できません。社員の初回登録とは別の紹介機能です。紹介元確定とポイント付与はまだ接続されていません。SMS起動失敗は同じ入力で再試行でき、起動後の記録失敗は「履歴を更新」で記録だけを再試行します。画面を閉じると再試行状態は引き継ぎません。ポイント数・使い道は未定です。履歴はこの画面で確認できます。ログイン状態が変わった場合は履歴と入力を消し、SMS準備や設定保存を停止します。画面を開き直してください。',
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
                if (!_usesDistribution)
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
                if (_usesDistribution) ...[
                  TextField(
                    controller: _testflight,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'TestFlight URL',
                    ),
                  ),
                  TextField(
                    controller: _web,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'WEB版 URL'),
                  ),
                  TextField(
                    controller: _guide,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: '公開版の案内ページ URL',
                    ),
                  ),
                  const Text(
                    '公開案内はApp Store・Google Play・WEB版の公開済み経路をまとめたページです。',
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _saveLinks,
                    child: const Text('配布先URLを保存'),
                  ),
                ],
              ] else if (data['can_invite'] == true) ...[
                if (_usesDistribution)
                  DropdownButtonFormField<String>(
                    initialValue: _channel,
                    decoration: const InputDecoration(labelText: '送信する案内'),
                    items: [
                      for (final channel in channels)
                        DropdownMenuItem<String>(
                          value: channel['key'].toString(),
                          enabled: channel['ready'] == true,
                          child: Text(channel['label'].toString()),
                        ),
                    ],
                    onChanged:
                        _busy ||
                            _composer.needsRecordRetry
                        ? null
                        : (value) {
                            if (value != null) setState(() => _channel = value);
                          },
                  ),
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
                if (widget.friendInvite && !_usesDistribution)
                  const Text('配布先の案内を確認できないため、友達招待は送信できません。配布設定の更新をお待ちください。'),
                if (!channelReady)
                  const Text('配布URLが未登録、または公開前です。管理者へURL・公開設定の確認を依頼してください。'),
                FilledButton(
                  onPressed:
                      _busy || (!channelReady && !_composer.needsRecordRetry)
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
                    '${referralJapanTime(row['created_at'].toString())}\n${row['source_label']}／${row['state_label']}${row['distribution_label'] == null ? '' : '／${row['distribution_label']}'}'
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
