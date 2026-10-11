import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'chat_cloud_repository.dart';
import 'chat_friends_strings.dart';

class ChatFriendsPage extends StatefulWidget {
  const ChatFriendsPage({
    super.key,
    this.repository,
    this.selectForChat = false,
    this.selectForGroupInvite = false,
  });

  final ChatCloudRepository? repository;
  final bool selectForChat;
  final bool selectForGroupInvite;

  @override
  State<ChatFriendsPage> createState() => _ChatFriendsPageState();
}

class _ChatFriendsPageState extends State<ChatFriendsPage> {
  late final _repository =
      widget.repository ?? ChatCloudRepository.maybeCreate();
  final _search = TextEditingController();

  Map<String, dynamic> _workspace = const {};
  Map<String, dynamic>? _searchResult;
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
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

    try {
      final workspace = await repository.loadFriendWorkspace();
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
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

  Future<void> _find() async {
    final repository = _repository;
    final value = _search.text.trim();
    if (repository == null || value.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _searchResult = null;
    });

    try {
      final result = await repository.searchFriendBySkoId(value);
      if (!mounted) return;
      setState(() => _searchResult = result);
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ChatFriendsStrings.tr('該当するSKO IDが見つかりません'))),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ChatFriendsStrings.format('検索できませんでした: {error}', {'error': error}),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendRequest() async {
    final repository = _repository;
    final result = _searchResult;
    if (repository == null || result == null || _busy) return;

    final name = result['display_name']?.toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        SkoLanguageController.watch(context);
        return AlertDialog(
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
        );
      },
    );
    if (!mounted || confirmed != true) return;

    setState(() => _busy = true);
    try {
      await repository.sendFriendRequest(result['sko_id']?.toString() ?? '');
      _search.clear();
      _searchResult = null;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ChatFriendsStrings.tr('友達申請を送信しました'))),
      );
    } catch (error) {
      if (!mounted) return;
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(Map<String, dynamic> request, bool accept) async {
    final repository = _repository;
    if (repository == null || _busy) return;
    final id = request['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        SkoLanguageController.watch(context);
        return AlertDialog(
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
        );
      },
    );
    if (!mounted || confirmed != true) return;

    setState(() => _busy = true);
    try {
      await repository.respondFriendRequest(requestId: id, accept: accept);
      await _load();
    } catch (error) {
      if (!mounted) return;
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeFriend(Map<String, dynamic> friend) async {
    final repository = _repository;
    if (repository == null || _busy) return;
    final userId = friend['user_id']?.toString() ?? '';
    if (userId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        SkoLanguageController.watch(context);
        return AlertDialog(
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
        );
      },
    );
    if (!mounted || confirmed != true) return;

    setState(() => _busy = true);
    try {
      await repository.removeFriend(userId);
      await _load();
    } catch (error) {
      if (!mounted) return;
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final incoming = _rows('incoming');
    final outgoing = _rows('outgoing');
    final friends = _rows('friends');

    return Scaffold(
      appBar: AppBar(
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
            ? (friends.isEmpty
                  ? Center(child: Text(ChatFriendsStrings.tr('友達はまだいません')))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: friends.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(
                              friend['display_name']?.toString() ??
                                  ChatFriendsStrings.tr('SKOユーザー'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).pop(friend),
                          ),
                        );
                      },
                    ))
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
                            decoration: InputDecoration(
                              labelText: ChatFriendsStrings.tr('SKO ID検索'),
                              hintText: 'SKO-XXXXXXXXXX',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _find(),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _busy ? null : _find,
                            icon: const Icon(Icons.person_search_outlined),
                            label: Text(ChatFriendsStrings.tr('検索')),
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
    );
  }
}
