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
      setState(() {
        _groups = groups;
        _selectedGroupId = groups.isEmpty ? null : groups.first['id'] as String;
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

  @override
  Widget build(BuildContext context) {
    final selectedGroup = _selectedGroup;

    return Scaffold(
      appBar: AppBar(title: const Text('チャット')),
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
                      child: _LineBindingStatus(group: selectedGroup),
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
  const _LineBindingStatus({required this.group});

  final Map<String, dynamic> group;

  @override
  Widget build(BuildContext context) {
    final present = group['line_binding_present'] == true;
    final enabled = group['line_binding_enabled'] == true;
    final displayName = group['line_binding_name']?.toString().trim();

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
    final createdBy = message['created_by']?.toString();
    final origin = message['origin']?.toString() ?? 'sko';
    final isOwn = origin == 'sko' && createdBy != null && createdBy == currentUserId;
    final sender = origin == 'line'
        ? (message['external_sender_name']?.toString().trim().isNotEmpty == true
            ? message['external_sender_name'].toString()
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
              _formatTime(message['created_at']?.toString()),
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
