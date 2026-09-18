import 'dart:async';

import 'package:flutter/material.dart';

import 'chat_cloud_repository.dart';

class ChatCloudPage extends StatefulWidget {
  const ChatCloudPage({super.key});

  @override
  State<ChatCloudPage> createState() => _ChatCloudPageState();
}

class _ChatCloudPageState extends State<ChatCloudPage> {
  final _repository = ChatCloudRepository.maybeCreate();
  final _composer = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _messages = [];
  String? _selectedGroupId;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  Map<String, dynamic>? get _selectedGroup {
    final groupId = _selectedGroupId;
    if (groupId == null) return null;
    for (final group in _groups) {
      if (group['id']?.toString() == groupId) return group;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_repository == null) {
      setState(() {
        _loading = false;
        _error = 'Supabaseに接続されていません。';
      });
      return;
    }

    try {
      final groups = await _repository.loadGroups();
      if (!mounted) return;
      final previousGroupId = _selectedGroupId;
      final nextGroupId = groups.any(
        (group) => group['id']?.toString() == previousGroupId,
      )
          ? previousGroupId
          : (groups.isEmpty ? null : groups.first['id'] as String);
      setState(() {
        _groups = groups;
        _selectedGroupId = nextGroupId;
        _loading = false;
        _error = null;
      });
      await _subscribeToSelectedGroup();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _subscribeToSelectedGroup() async {
    await _subscription?.cancel();
    _subscription = null;
    final repository = _repository;
    final groupId = _selectedGroupId;
    if (repository == null || groupId == null) return;

    setState(() {
      _messages = [];
      _error = null;
    });

    _subscription = repository.watchMessages(groupId).listen(
      (messages) {
        if (!mounted) return;
        setState(() {
          _messages = messages;
          _error = null;
        });
        _scrollToBottom();
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = error.toString());
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final repository = _repository;
    final groupId = _selectedGroupId;
    final text = _composer.text.trim();
    if (repository == null || groupId == null || text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await repository.sendMessage(groupId: groupId, body: text);
      _composer.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('メッセージを送信できませんでした: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _createGroup() async {
    final repository = _repository;
    if (repository == null) return;

    List<Map<String, dynamic>> sites;
    try {
      sites = await repository.loadSites();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('現場一覧を読み込めませんでした: $error')),
      );
      return;
    }

    if (!mounted) return;
    final nameController = TextEditingController();
    var scope = 'company';
    String? siteId;

    final draft = await showDialog<({String name, String? siteId})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('通信グループ作成'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'グループ名',
                    hintText: '例: 東京海上 / 全社連絡',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  decoration: const InputDecoration(labelText: '種類'),
                  items: const [
                    DropdownMenuItem(
                      value: 'company',
                      child: Text('全社・共通グループ'),
                    ),
                    DropdownMenuItem(
                      value: 'site',
                      child: Text('現場グループ'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      scope = value;
                      if (scope == 'company') siteId = null;
                    });
                  },
                ),
                if (scope == 'site') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: siteId,
                    decoration: const InputDecoration(labelText: '現場'),
                    items: sites
                        .map(
                          (site) => DropdownMenuItem<String>(
                            value: site['id'] as String,
                            child: Text(site['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => siteId = value),
                  ),
                  if (sites.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('先に現場管理で現場を登録してください。'),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: scope == 'site' && siteId == null
                  ? null
                  : () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(
                        dialogContext,
                        (name: name, siteId: scope == 'site' ? siteId : null),
                      );
                    },
              child: const Text('作成'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();

    if (draft == null) return;

    try {
      final created = await repository.createGroup(
        name: draft.name,
        siteId: draft.siteId,
      );
      final createdId = created['id']?.toString();
      await _load();
      if (!mounted) return;
      if (createdId != null) {
        setState(() => _selectedGroupId = createdId);
        await _subscribeToSelectedGroup();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通信グループを作成しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通信グループを作成できませんでした: $error')),
      );
    }
  }

  Future<void> _startLineClaim() async {
    final repository = _repository;
    final groupId = _selectedGroupId;
    if (repository == null || groupId == null) return;

    try {
      final claim = await repository.beginLineBindingClaim(groupId);
      final code = claim['claim_code']?.toString();
      final expiresRaw = claim['expires_at']?.toString();
      if (code == null || code.isEmpty) {
        throw StateError('LINE連携コードを確認できませんでした。');
      }

      final expiresAt = expiresRaw == null
          ? null
          : DateTime.tryParse(expiresRaw)?.toLocal();

      if (!mounted) return;
      final shouldRefresh = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('LINEグループを連携'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '連携したいLINEグループに、次の1行をそのまま送信してください。',
                ),
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: SelectableText(
                      'SKO連携 $code',
                      style: Theme.of(dialogContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'このコードを送ったLINEグループだけが、このSKO通信グループに連携されます。',
                ),
                if (expiresAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '有効期限: '
                    '${expiresAt.month.toString().padLeft(2, '0')}/'
                    '${expiresAt.day.toString().padLeft(2, '0')} '
                    '${expiresAt.hour.toString().padLeft(2, '0')}:'
                    '${expiresAt.minute.toString().padLeft(2, '0')}',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('閉じる'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('送信したので確認'),
            ),
          ],
        ),
      );

      if (shouldRefresh == true) {
        await _load();
        if (!mounted) return;
        final selected = _selectedGroup;
        final linked = selected?['line_binding_enabled'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              linked
                  ? 'LINEグループの連携を確認しました。'
                  : 'まだ連携を確認できません。LINE側の送信後、もう一度確認してください。',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LINE連携を開始できませんでした: $error')),
      );
    }
  }

  Future<void> _disableLineBinding() async {
    final repository = _repository;
    final bindingId = _selectedGroup?['line_binding_id']?.toString();
    if (repository == null || bindingId == null || bindingId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('LINE連携を停止'),
        content: const Text(
          'この通信グループへのLINEメッセージ受信を停止します。よろしいですか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('停止する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await repository.disableLineBinding(bindingId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LINE連携を停止しました。')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LINE連携を停止できませんでした: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroup = _selectedGroup;

    return Scaffold(
      appBar: AppBar(
        title: const Text('チャット'),
        actions: [
          IconButton(
            tooltip: '通信グループ作成',
            onPressed: _loading ? null : _createGroup,
            icon: const Icon(Icons.group_add_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _groups.isEmpty
                        ? const Card(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Text('チャットを始めるには、先に通信グループを作成してください。'),
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _selectedGroupId,
                            decoration: const InputDecoration(
                              labelText: 'グループ / 現場',
                              prefixIcon: Icon(Icons.groups_outlined),
                            ),
                            items: _groups
                                .map(
                                  (group) => DropdownMenuItem<String>(
                                    value: group['id'] as String,
                                    child: Text(group['name'].toString()),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) async {
                              if (value == null || value == _selectedGroupId) return;
                              setState(() => _selectedGroupId = value);
                              await _subscribeToSelectedGroup();
                            },
                          ),
                  ),
                  if (selectedGroup != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _LineBindingStatus(
                        group: selectedGroup,
                        onStartClaim: _startLineClaim,
                        onDisable: _disableLineBinding,
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  Expanded(
                    child: _groups.isEmpty
                        ? const SizedBox.shrink()
                        : _messages.isEmpty
                            ? const Center(child: Text('まだメッセージはありません。'))
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) => _MessageBubble(
                                  message: _messages[index],
                                  currentUserId: _repository?.currentUserId,
                                ),
                              ),
                  ),
                  if (_selectedGroupId != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          top: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _composer,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.newline,
                              decoration: const InputDecoration(
                                hintText: 'メッセージを入力',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: '送信',
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _LineBindingStatus extends StatelessWidget {
  const _LineBindingStatus({
    required this.group,
    required this.onStartClaim,
    required this.onDisable,
  });

  final Map<String, dynamic> group;
  final VoidCallback onStartClaim;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final present = group['line_binding_present'] == true;
    final enabled = group['line_binding_enabled'] == true;
    final displayName = group['line_binding_name']?.toString().trim();
    final canManage = group['line_binding_can_manage'] == true;

    late final String title;
    late final String detail;
    late final IconData icon;

    if (!present) {
      title = 'LINE未連携';
      detail = 'このグループはLINEからの受信先にまだ紐付いていません。';
      icon = Icons.link_off;
    } else if (enabled) {
      title = 'LINE連携中';
      detail = displayName?.isNotEmpty == true
          ? '$displayName からの受信を有効にしています。'
          : 'LINEグループからの受信を有効にしています。';
      icon = Icons.link;
    } else {
      title = 'LINE連携停止中';
      detail = displayName?.isNotEmpty == true
          ? '$displayName との紐付けはありますが、現在は受信停止中です。'
          : 'LINEとの紐付けはありますが、現在は受信停止中です。';
      icon = Icons.link_off;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(detail),
        trailing: !canManage
            ? null
            : enabled
                ? TextButton(
                    onPressed: onDisable,
                    child: const Text('停止'),
                  )
                : FilledButton.tonal(
                    onPressed: onStartClaim,
                    child: Text(present ? '再連携' : '連携する'),
                  ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.currentUserId});

  final Map<String, dynamic> message;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final createdBy = message['sender_user_id']?.toString();
    final origin = message['origin']?.toString() ?? 'sk_works';
    final isOwn = origin == 'sk_works' && createdBy != null && createdBy == currentUserId;
    final sender = origin == 'line'
        ? (message['sender_display_name']?.toString().trim().isNotEmpty == true
            ? message['sender_display_name'].toString()
            : 'LINE')
        : isOwn
            ? '自分'
            : 'メンバー';

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: isOwn
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sender,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (origin == 'line') ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chat_bubble_outline, size: 13),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(message['body']?.toString() ?? ''),
            const SizedBox(height: 4),
            Text(
              _formatTime(message['sent_at']?.toString()),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? value) {
    final parsed = value == null ? null : DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.month)}/${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }
}
