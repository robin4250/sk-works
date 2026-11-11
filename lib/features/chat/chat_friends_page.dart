import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../international/language_controller.dart';
import '../../data/supabase_backend.dart';
import '../referrals/app_referral_page.dart';
import '../referrals/app_referral_repository.dart';
import 'chat_cloud_repository.dart';
import 'chat_friends_strings.dart';
import 'chat_friend_profile_page.dart';
import 'chat_friend_order.dart';
import 'chat_actor_guard.dart';
import 'sko_id_search_input.dart';

class ChatFriendsPage extends StatefulWidget {
  const ChatFriendsPage({
    super.key,
    this.repository,
    this.selectForChat = false,
    this.selectForGroupInvite = false,
    this.onPhoneInvitation,
    this.onReturnToChats,
    this.existingGroups = const [],
  });

  /// Returns through the existing chat route; never creates another chat page.
  final VoidCallback? onReturnToChats;
  final ChatCloudRepository? repository;
  final bool selectForChat;
  final bool selectForGroupInvite;
  final List<Map<String, dynamic>> existingGroups;
  final Future<void> Function(BuildContext context, String source)?
  onPhoneInvitation;

  @override
  State<ChatFriendsPage> createState() => _ChatFriendsPageState();
}

class _ChatFriendsPageState extends State<ChatFriendsPage> with WidgetsBindingObserver {
  late final _repository =
      widget.repository ?? ChatCloudRepository.maybeCreate();
  final _search = TextEditingController();
  String _friendQuery = '';
  Set<String> _pinnedFriends = {};
  String? _actor;
  bool _sessionInvalidated = false;
  final _profileActorEpoch = ValueNotifier<int>(0);
  StreamSubscription<String?>? _actorSubscription;

  Map<String, dynamic> _workspace = const {};
  Map<String, dynamic>? _searchResult;
  int _workspaceLoadEpoch = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  List<Map<String, dynamic>> _rows(String key) {
    final raw = _workspace[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _actor = _repository?.currentUserId;
    _actorSubscription = _repository?.watchActorChanges().listen((actor) {
      if (!mounted || actor == _actor) return;
      _invalidateActor(actor);
    }, onError: (Object _) => _invalidateActor(null));
    _load();
  }

  bool _isCurrent(String? actor, int epoch) => mounted && !_sessionInvalidated &&
      actor != null && actor == _actor && actor == _repository?.currentUserId &&
      epoch == _profileActorEpoch.value;

  void _invalidateActor(String? actor) {
    if (!mounted) return;
    _actor = actor;
    _sessionInvalidated = true;
    _profileActorEpoch.value++;
    _workspaceLoadEpoch++;
    _search.clear();
    setState(() {
      _workspace = const {};
      _searchResult = null;
      _pinnedFriends = {};
      _busy = false;
      _loading = false;
      _error = 'ログイン情報が変わりました。友達一覧を開き直してください。';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _actorSubscription?.cancel();
    _profileActorEpoch.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final repository = _repository;
    // A screen invalidated by an account change must be opened again; do not
    // revive another account's rows through resume or the refresh button.
    if (!mounted || repository == null || _sessionInvalidated ||
        repository.currentUserId != _actor || _loading || _busy) {
      return;
    }
    setState(() => _loading = true);
    await _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '友達機能を利用できません。';
      });
      return;
    }

    final actor = repository.currentUserId;
    if (actor == null) { _invalidateActor(null); return; }
    final epoch = _profileActorEpoch.value;
    if (!mounted || !_isCurrent(actor, epoch)) return;
    final loadEpoch = ++_workspaceLoadEpoch;
    try {
      final workspace = await repository.loadFriendWorkspace();
      final prefs = widget.selectForChat ? await SharedPreferences.getInstance() : null;
      if (!mounted || !_isCurrent(actor, epoch) || loadEpoch != _workspaceLoadEpoch) return;
      setState(() {
        _actor = actor;
        _pinnedFriends = prefs?.getStringList('sko_chat_friend_pinned_$actor')?.toSet() ?? {};
        _workspace = workspace;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || !_isCurrent(actor, epoch) || loadEpoch != _workspaceLoadEpoch) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<bool> _pinFriend(Map<String, dynamic> friend) async {
    final actor = _actor;
    final id = friend['user_id']?.toString() ?? '';
    final epoch = _profileActorEpoch.value;
    if (id.isEmpty || !_isCurrent(actor, epoch)) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || !_isCurrent(actor, epoch)) return false;
    setState(() {
      if (!_pinnedFriends.remove(id)) _pinnedFriends.add(id);
    });
    await prefs.setStringList(
      'sko_chat_friend_pinned_$actor',
      _pinnedFriends.toList(),
    );
    return false;
  }

  Future<void> _find() async {
    final repository = _repository;
    final actor = _actor;
    final epoch = _profileActorEpoch.value;
    if (!mounted || !_isCurrent(actor, epoch)) return;
    final value = skoIdSearchValue(_search.text);
    if (repository == null || value.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _searchResult = null;
    });

    try {
      final result = await repository.searchFriendBySkoId(value);
      if (!mounted || !_isCurrent(actor, epoch)) return;
      setState(() => _searchResult = result);
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ChatFriendsStrings.tr('該当するSKO IDが見つかりません'))),
        );
      }
    } catch (error) {
      if (!mounted || !_isCurrent(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatFriendsStrings.format('検索できませんでした: {error}', {'error': error}),
          ),
        ),
      );
    } finally {
      if (_isCurrent(actor, epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _sendRequest() async {
    final repository = _repository;
    final actor = _actor;
    final epoch = _profileActorEpoch.value;
    if (!mounted || !_isCurrent(actor, epoch)) return;
    final result = _searchResult;
    if (repository == null || result == null || _busy) return;

    final name = result['display_name']?.toString();
    setState(() => _busy = true);
    try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        SkoLanguageController.watch(context);
        return ChatActorGuard(epoch: _profileActorEpoch, initialEpoch: epoch, child: AlertDialog(
          title: Text(ChatFriendsStrings.tr('友達申請を送りますか？')),
          content: Text(
            ChatFriendsStrings.format('{name} さんへ友達申請を送信します。', {
              'name': name ?? ChatFriendsStrings.tr('SKOユーザー'),
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ChatFriendsStrings.tr('戻る')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ChatFriendsStrings.tr('申請する')),
            ),
          ],
        ));
      },
    );
    if (!mounted || !_isCurrent(actor, epoch) || confirmed != true) return;
      await repository.sendFriendRequest(result['sko_id']?.toString() ?? '');
      if (!mounted || !_isCurrent(actor, epoch)) return;
      _search.clear();
      _searchResult = null;
      await _load();
      if (!mounted || !_isCurrent(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ChatFriendsStrings.tr('友達申請を送信しました'))),
      );
    } catch (error) {
      if (!mounted || !_isCurrent(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatFriendsStrings.format('友達申請を送信できませんでした: {error}', {
              'error': error,
            }),
          ),
        ),
      );
    } finally {
      if (_isCurrent(actor, epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _respond(Map<String, dynamic> request, bool accept) async {
    final repository = _repository;
    final actor = _actor;
    final epoch = _profileActorEpoch.value;
    if (!mounted || !_isCurrent(actor, epoch)) return;
    if (repository == null || _busy) return;
    final id = request['id']?.toString() ?? '';
    if (id.isEmpty) return;

    setState(() => _busy = true);
    try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        SkoLanguageController.watch(context);
        return ChatActorGuard(epoch: _profileActorEpoch, initialEpoch: epoch, child: AlertDialog(
          title: Text(
            accept
                ? ChatFriendsStrings.tr('友達申請を承認しますか？')
                : ChatFriendsStrings.tr('友達申請を拒否しますか？'),
          ),
          content: Text(
            request['display_name']?.toString() ??
                ChatFriendsStrings.tr('SKOユーザー'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ChatFriendsStrings.tr('戻る')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                accept
                    ? ChatFriendsStrings.tr('承認する')
                    : ChatFriendsStrings.tr('拒否する'),
              ),
            ),
          ],
        ));
      },
    );
    if (!mounted || !_isCurrent(actor, epoch) || confirmed != true) return;
      await repository.respondFriendRequest(requestId: id, accept: accept);
      if (!mounted || !_isCurrent(actor, epoch)) return;
      await _load();
    } catch (error) {
      if (!mounted || !_isCurrent(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatFriendsStrings.format('友達申請を更新できませんでした: {error}', {
              'error': error,
            }),
          ),
        ),
      );
    } finally {
      if (_isCurrent(actor, epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _removeFriend(Map<String, dynamic> friend) async {
    final repository = _repository;
    final actor = _actor;
    final epoch = _profileActorEpoch.value;
    if (!mounted || !_isCurrent(actor, epoch)) return;
    if (repository == null || _busy) return;
    final userId = friend['user_id']?.toString() ?? '';
    if (userId.isEmpty) return;

    setState(() => _busy = true);
    try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        SkoLanguageController.watch(context);
        return ChatActorGuard(epoch: _profileActorEpoch, initialEpoch: epoch, child: AlertDialog(
          title: Text(ChatFriendsStrings.tr('友達から削除しますか？')),
          content: Text(
            friend['display_name']?.toString() ??
                ChatFriendsStrings.tr('SKOユーザー'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ChatFriendsStrings.tr('戻る')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ChatFriendsStrings.tr('削除する')),
            ),
          ],
        ));
      },
    );
    if (!mounted || !_isCurrent(actor, epoch) || confirmed != true) return;
      await repository.removeFriend(userId);
      if (!mounted || !_isCurrent(actor, epoch)) return;
      await _load();
    } catch (error) {
      if (!mounted || !_isCurrent(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatFriendsStrings.format('友達から削除できませんでした: {error}', {
              'error': error,
            }),
          ),
        ),
      );
    } finally {
      if (_isCurrent(actor, epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _openFriend(Map<String, dynamic> friend) async {
    final actor = _actor;
    if (_sessionInvalidated || actor == null || actor != _repository?.currentUserId) return;
    final epoch = _profileActorEpoch.value;
    final startChat = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ChatActorGuard(epoch: _profileActorEpoch, initialEpoch: epoch, child: ChatFriendProfilePage(friend: friend))),
    );
    if (!mounted || startChat != true || actor != _repository?.currentUserId || epoch != _profileActorEpoch.value) return;
    Navigator.of(context).pop(friend);
  }

  Future<void> _openAdd() async {
    final actor = _actor;
    final epoch = _profileActorEpoch.value;
    if (!mounted || !_isCurrent(actor, epoch) || _busy) return;
    setState(() => _busy = true);
    try {
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ChatActorGuard(epoch: _profileActorEpoch, initialEpoch: epoch, child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('ID検索'),
              onTap: () => Navigator.pop(context, 'id'),
            ),
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('電話番号通知'),
              subtitle: const Text('SKOアプリからの友達追加です'),
              onTap: () => Navigator.pop(context, 'phone'),
            ),
          ],
        ),
      )),
    );
    if (!mounted || !_isCurrent(actor, epoch) || method == null) return;
    if (method == 'phone') {
      await _launchPhoneInvitation();
      if (_isCurrent(actor, epoch)) await _load();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatFriendsPage(
          repository: _repository,
          onReturnToChats: widget.onReturnToChats,
        ),
      ),
    );
    if (_isCurrent(actor, epoch)) await _load();
    } finally {
      if (_isCurrent(actor, epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _openPhoneInvitation() async {
    final actor = _actor;
    final epoch = _profileActorEpoch.value;
    if (!mounted || !_isCurrent(actor, epoch) || _loading || _busy ||
        widget.selectForGroupInvite) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _launchPhoneInvitation();
      if (_isCurrent(actor, epoch)) await _load();
    } catch (_) {
      if (mounted && _isCurrent(actor, epoch)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ChatFriendsStrings.tr('SKO招待を開けませんでした。もう一度お試しください。')),
        ));
      }
    } finally {
      if (_isCurrent(actor, epoch)) setState(() => _busy = false);
    }
  }

  // Both entries keep the same referral source and the server's distribution gate.
  Future<void> _launchPhoneInvitation() async {
    final open = widget.onPhoneInvitation;
    if (open != null) {
      await open(context, 'friend_add');
    } else if (SupabaseBackend.isInitialized &&
        SupabaseBackend.client.auth.currentUser?.id != null &&
        SupabaseBackend.client.auth.currentUser?.id == _actor) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => AppReferralPage(
          repository: AppReferralRepository(SupabaseBackend.client),
          friendInvite: true,
        ),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログイン情報を確認できません。友達一覧を開き直してください。')),
      );
    }
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('友達一覧の使い方'),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text(
          '右上の更新ボタンで申請・承認の最新状態を取得できます。アプリへ戻った時も自動更新します。\n\n'
          '登録済み友達の氏名・公開会社名・SKO IDを検索できます。検索を消すと一覧へ戻ります。\n\n'
          '戻るとチャット一覧へ戻ります。SKO ID検索はSKO-より後ろだけ入力します。完全なSKO IDの貼り付けもできます。\n\n'
          '友達を押すと公開名とSKO IDを確認し、「チャットを始める」で既存の個別チャットを開きます。写真・所属会社は承認済み友達の公開情報だけを表示します。写真は短時間の閲覧URLを使用し、取得できない場合は標準アイコンになります。\n\n'
          '左から右へスワイプするとピン留め／解除できます。この端末のログイン中ユーザーごとに保存し、友達や会話は削除しません。並びはピン留め、既存の個別チャット相手、その他の登録順です。登録日時が無い行は取得順を保ちます。\n\n'
          '右上の「SKO招待」から名前・電話番号を入力する招待画面を開けます。下の「追加」→「ID検索」で申請・承認を管理します。「電話番号通知」も同じ招待画面を開きます。招待機能ONと利用権限が必要です。正式な配布URL未登録ではSMSを作成できません。送信を押すとSMS作成画面が開き、実際の送信はそこで行います。トーク本文や全履歴の検索はこの画面では行いません。',
        ), const SizedBox(height: 12), Text(ChatFriendsStrings.tr('ログイン状態が変わった場合は、検索結果と確認中の操作を破棄します。友達一覧を開き直してください。'))])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final compactInviteAction = MediaQuery.sizeOf(context).width < 420 ||
        MediaQuery.textScalerOf(context).scale(14) > 16.8;
    final incoming = _rows('incoming');
    final outgoing = _rows('outgoing');
    final friends =
        orderChatFriends(
              _rows('friends'),
              widget.existingGroups,
              pinnedUserIds: _pinnedFriends,
            )
            .where(
              (friend) =>
                  _friendQuery.trim().isEmpty ||
                  ['display_name', 'company_name', 'sko_id'].any(
                    (key) => (friend[key]?.toString() ?? '')
                        .toLowerCase()
                        .contains(_friendQuery.trim().toLowerCase()),
                  ),
            )
            .toList();

    return PopScope<dynamic>(
      onPopInvokedWithResult: (didPop, result) {
        final returnToChats = widget.onReturnToChats;
        if (didPop && result == null && returnToChats != null) {
          // Wait until the completed native/onscreen pop unlocks Navigator.
          WidgetsBinding.instance.addPostFrameCallback((_) => returnToChats());
        }
      },
      child: Scaffold(
      bottomNavigationBar: widget.selectForChat
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _loading || _busy ? null : _openAdd,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('追加'),
                ),
              ),
            )
          : null,
      appBar: AppBar(
        actions: [
          if (!widget.selectForGroupInvite)
            if (compactInviteAction)
              IconButton(
                tooltip: ChatFriendsStrings.tr('SKO招待'),
                onPressed: _loading || _busy || _sessionInvalidated
                    ? null : _openPhoneInvitation,
                icon: const Icon(Icons.sms_outlined),
              )
            else
              TextButton.icon(
                onPressed: _loading || _busy || _sessionInvalidated
                    ? null : _openPhoneInvitation,
                icon: const Icon(Icons.sms_outlined),
                label: Text(ChatFriendsStrings.tr('SKO招待')),
              ),
          IconButton(tooltip: '友達一覧を更新', onPressed: _loading || _busy ? null : _refresh, icon: const Icon(Icons.refresh)), IconButton(tooltip: '使い方', onPressed: _showHelp, icon: const Icon(Icons.help_outline))],
        title: Text(
          widget.selectForChat
              ? ChatFriendsStrings.tr('友達一覧')
              : widget.selectForGroupInvite
              ? ChatFriendsStrings.tr('友達を招待')
              : ChatFriendsStrings.tr('友達'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _repository == null
                        ? ChatFriendsStrings.tr('友達機能を利用できません。')
                        : ChatFriendsStrings.format(
                            '友達一覧を読み込めませんでした: {error}',
                            {'error': _error},
                          ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : (widget.selectForChat || widget.selectForGroupInvite)
            ? Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: '友達検索',
                        hintText: '氏名・所属会社・SKO ID',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setState(() => _friendQuery = value),
                    ),
                  ),
                  Expanded(
                    child: friends.isEmpty
                        ? Center(
                            child: Text(_friendQuery.trim().isEmpty ? ChatFriendsStrings.tr('友達はまだいません') : '一致する友達はいません。検索を消すと一覧へ戻ります。'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: friends.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final friend = friends[index];
                              return Dismissible(
                                key: ValueKey('friend-${friend['user_id']}'),
                                direction: widget.selectForChat ? DismissDirection.startToEnd : DismissDirection.none,
                                confirmDismiss: (_) => _pinFriend(friend),
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Icon(
                                    _pinnedFriends.contains(
                                          friend['user_id']?.toString(),
                                        )
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                  ),
                                ),
                                child: Card(
                                  child: ListTile(
                                    leading: ChatFriendAvatar(friend: friend),
                                    title: Text(
                                      friend['display_name']?.toString() ??
                                          ChatFriendsStrings.tr('SKOユーザー'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    subtitle: Text('所属会社：${friendCompanyLabel(friend)}'),
                                    trailing: _pinnedFriends.contains(friend['user_id']?.toString())
                                        ? const Icon(Icons.push_pin)
                                        : const Icon(Icons.chevron_right),
                                    onTap: () => widget.selectForGroupInvite
                                        ? Navigator.of(context).pop(friend)
                                        : _openFriend(friend),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            ChatFriendsStrings.tr('自分のSKO ID'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            _workspace['my_sko_id']?.toString() ?? '',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _search,
                            textCapitalization: TextCapitalization.characters,
                            autocorrect: false,
                            enableSuggestions: false,
                            inputFormatters: const [SkoIdSuffixInputFormatter()],
                            decoration: InputDecoration(
                              labelText: ChatFriendsStrings.tr('SKO ID検索'),
                              hintText: 'XXXXXXXXXX',
                              prefixIcon: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Center(widthFactor: 1, child: Text('SKO-')),
                              ),
                              prefixIconConstraints: const BoxConstraints(minHeight: 44),
                              isDense: true,
                              suffixIcon: IconButton(
                                tooltip: ChatFriendsStrings.tr('検索'),
                                onPressed: _busy ? null : _find,
                                icon: const Icon(Icons.search),
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _find(),
                          ),
                          if (_searchResult != null) ...[
                            const Divider(height: 24),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                child: Icon(Icons.person_add_alt_1),
                              ),
                              title: Text(
                                _searchResult!['display_name']?.toString() ??
                                    ChatFriendsStrings.tr('SKOユーザー'),
                              ),
                              subtitle: Text(
                                _searchResult!['sko_id']?.toString() ?? '',
                              ),
                              trailing: FilledButton(
                                onPressed: _busy ? null : _sendRequest,
                                child: Text(ChatFriendsStrings.tr('申請')),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (incoming.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      ChatFriendsStrings.tr('届いた申請'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    for (final request in incoming)
                      Card(
                        child: ListTile(
                          title: Text(
                            request['display_name']?.toString() ??
                                ChatFriendsStrings.tr('SKOユーザー'),
                          ),
                          subtitle: Text(request['sko_id']?.toString() ?? ''),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: ChatFriendsStrings.tr('拒否'),
                                onPressed: _busy
                                    ? null
                                    : () => _respond(request, false),
                                icon: const Icon(Icons.close),
                              ),
                              IconButton(
                                tooltip: ChatFriendsStrings.tr('承認'),
                                onPressed: _busy
                                    ? null
                                    : () => _respond(request, true),
                                icon: const Icon(Icons.check_circle_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (outgoing.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      ChatFriendsStrings.tr('申請中'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    for (final request in outgoing)
                      ListTile(
                        title: Text(
                          request['display_name']?.toString() ??
                              ChatFriendsStrings.tr('SKOユーザー'),
                        ),
                        subtitle: Text(ChatFriendsStrings.tr('承認待ち')),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    ChatFriendsStrings.tr('友達一覧'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (friends.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(ChatFriendsStrings.tr('友達はまだいません')),
                      ),
                    )
                  else
                    for (final friend in friends)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(
                            friend['display_name']?.toString() ??
                                ChatFriendsStrings.tr('SKOユーザー'),
                          ),
                          subtitle: Text(friend['sko_id']?.toString() ?? ''),
                          trailing:
                              widget.selectForChat ||
                                  widget.selectForGroupInvite
                              ? const Icon(Icons.chevron_right)
                              : IconButton(
                                  tooltip: ChatFriendsStrings.tr('友達から削除'),
                                  onPressed: _busy
                                      ? null
                                      : () => _removeFriend(friend),
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                  ),
                                ),
                          onTap:
                              widget.selectForChat ||
                                  widget.selectForGroupInvite
                              ? () => Navigator.of(context).pop(friend)
                              : null,
                        ),
                      ),
                ],
              ),
      ),
      ),
    );
  }
}
