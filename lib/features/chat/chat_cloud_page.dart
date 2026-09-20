import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../albums/albums_cloud_page.dart';
import '../notes/notes_cloud_page.dart';
import '../notifications/notification_bell.dart';
import 'chat_cloud_repository.dart';

enum _ChatTab { all, site, direct, partner }

class ChatCloudPage extends StatefulWidget {
  const ChatCloudPage({super.key});

  @override
  State<ChatCloudPage> createState() => _ChatCloudPageState();
}

class _ChatCloudPageState extends State<ChatCloudPage> {
  final _repository = ChatCloudRepository.maybeCreate();
  final _composer = TextEditingController();
  final _memberSearch = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _messages = [];
  List<String> _prioritizedSiteGroupIds = const [];

  String? _selectedGroupId;
  String _role = 'viewer';
  bool _canManagePartnerChat = false;
  _ChatTab _tab = _ChatTab.all;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  Map<String, dynamic>? get _selectedGroup {
    final id = _selectedGroupId;
    if (id == null) return null;
    for (final group in _groups) {
      if (group['id']?.toString() == id) return group;
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
    _memberSearch.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'チャットを利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final membership = await repository.membership();
      final canManagePartnerChat = await repository.canManagePartnerChat();
      final groups = await repository.loadGroups();
      final members = await repository.loadMembers();
      final priorities = await repository.prioritizedSiteGroupIds();

      final previous = _selectedGroupId;
      final next = groups.any((g) => g['id']?.toString() == previous)
          ? previous
          : (groups.isEmpty ? null : groups.first['id']?.toString());

      if (!mounted) return;
      setState(() {
        _role = membership.role;
        _canManagePartnerChat = canManagePartnerChat;
        if (!_canManagePartnerChat && _tab == _ChatTab.partner) {
          _tab = _ChatTab.all;
        }
        _groups = groups;
        _members = members;
        _prioritizedSiteGroupIds = priorities;
        _selectedGroupId = next;
        _loading = false;
      });

      await _subscribeSelected();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _subscribeSelected() async {
    await _subscription?.cancel();
    _subscription = null;
    final id = _selectedGroupId;
    final repository = _repository;
    if (id == null || repository == null) return;

    setState(() {
      _messages = [];
      _error = null;
    });

    _subscription = repository.watchMessages(id).listen(
      (messages) {
        if (!mounted) return;
        setState(() => _messages = messages);
        _scrollToBottom();
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = error.toString());
      },
    );
  }

  Future<void> _selectGroup(String id) async {
    if (id == _selectedGroupId) {
      setState(() => _tab = _ChatTab.all);
      return;
    }
    setState(() {
      _selectedGroupId = id;
      _tab = _ChatTab.all;
    });
    await _subscribeSelected();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final repository = _repository;
    final id = _selectedGroupId;
    final text = _composer.text.trim();
    if (repository == null || id == null || text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await repository.sendMessage(groupId: id, body: text);
      _composer.clear();
      await _loadGroupsOnly();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('送信できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadGroupsOnly() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final groups = await repository.loadGroups();
      final priorities = await repository.prioritizedSiteGroupIds();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _prioritizedSiteGroupIds = priorities;
      });
    } catch (_) {}
  }

  Future<void> _startDirect(Map<String, dynamic> member) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final id = await repository.startDirectChat(
        member['user_id'].toString(),
      );
      await _loadGroupsOnly();
      if (!mounted) return;
      await _selectGroup(id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('個別トークを開始できませんでした: $error')),
      );
    }
  }

  Future<void> _attachPhoto() async {
    final id = _selectedGroupId;
    final repository = _repository;
    if (id == null || repository == null) return;

    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2000,
    );
    if (file == null) return;

    setState(() => _sending = true);
    try {
      await repository.sendAttachment(
        groupId: id,
        bytes: await file.readAsBytes(),
        filename: file.name,
        mimeType: file.mimeType ?? 'image/jpeg',
        isImage: true,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写真を送信できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachFile() async {
    final id = _selectedGroupId;
    final repository = _repository;
    if (id == null || repository == null) return;

    final file = await FilePicker.pickFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();

    setState(() => _sending = true);
    try {
      await repository.sendAttachment(
        groupId: id,
        bytes: bytes,
        filename: file.name,
        mimeType: 'application/octet-stream',
        isImage: false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ファイルを送信できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showAttachMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('写真'),
              onTap: () {
                Navigator.pop(sheetContext);
                _attachPhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('ファイル'),
              onTap: () {
                Navigator.pop(sheetContext);
                _attachFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNotes() async {
    final id = _selectedGroupId;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotesCloudPage(initialGroupId: id),
      ),
    );
  }

  Future<void> _openAlbums() async {
    final id = _selectedGroupId;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumsCloudPage(initialGroupId: id),
      ),
    );
  }

  List<Map<String, dynamic>> get _siteGroups {
    final groups =
        _groups.where((g) => g['group_type'] == 'site').toList();
    final order = {
      for (var i = 0; i < _prioritizedSiteGroupIds.length; i++)
        _prioritizedSiteGroupIds[i]: i,
    };
    groups.sort((a, b) {
      final ai = order[a['id']?.toString()] ?? 999999;
      final bi = order[b['id']?.toString()] ?? 999999;
      if (ai != bi) return ai.compareTo(bi);
      return _lastActivity(b).compareTo(_lastActivity(a));
    });
    return groups;
  }

  List<Map<String, dynamic>> get _directGroups {
    final groups =
        _groups.where((g) => g['group_type'] == 'direct').toList();
    groups.sort(
      (a, b) => _lastActivity(b).compareTo(_lastActivity(a)),
    );
    return groups;
  }

  List<Map<String, dynamic>> get _partnerGroups {
    final groups =
        _groups.where((g) => g['group_type'] == 'partner').toList();
    groups.sort(
      (a, b) => _lastActivity(b).compareTo(_lastActivity(a)),
    );
    return groups;
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final query = _memberSearch.text.trim().toLowerCase();
    final directActivityByUser = <String, DateTime>{};
    for (final group in _directGroups) {
      final other = group['direct_other_user_id']?.toString();
      if (other != null) {
        directActivityByUser[other] = _lastActivity(group);
      }
    }

    final members = _members.where((member) {
      if (query.isEmpty) return true;
      return (member['display_name'] ?? '')
          .toString()
          .toLowerCase()
          .contains(query);
    }).toList();

    members.sort((a, b) {
      final aId = a['user_id']?.toString() ?? '';
      final bId = b['user_id']?.toString() ?? '';
      final aDate = directActivityByUser[aId];
      final bDate = directActivityByUser[bId];
      if (aDate != null || bDate != null) {
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        final byDate = bDate.compareTo(aDate);
        if (byDate != 0) return byDate;
      }
      return (a['display_name'] ?? '')
          .toString()
          .compareTo((b['display_name'] ?? '').toString());
    });

    return members;
  }

  DateTime _lastActivity(Map<String, dynamic> group) =>
      DateTime.tryParse(group['last_activity_at']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    final selected = _selectedGroup;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected?['display_name']?.toString() ?? 'チャット',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          const SkoNotificationBell(),
          if (selected != null)
            PopupMenuButton<String>(
              tooltip: 'トーク機能',
              onSelected: (value) {
                if (value == 'notes') _openNotes();
                if (value == 'albums') _openAlbums();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'notes',
                  child: ListTile(
                    leading: Icon(Icons.sticky_note_2_outlined),
                    title: Text('ノート'),
                  ),
                ),
                PopupMenuItem(
                  value: 'albums',
                  child: ListTile(
                    leading: Icon(Icons.photo_album_outlined),
                    title: Text('アルバム'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _tabs(),
                  const Divider(height: 1),
                  Expanded(
                    child: switch (_tab) {
                      _ChatTab.all => _conversationView(),
                      _ChatTab.site => _groupList(
                          _siteGroups,
                          emptyText: '現場トークはまだありません',
                        ),
                      _ChatTab.direct => _directList(),
                      _ChatTab.partner => _groupList(
                          _partnerGroups,
                          emptyText: '協力会社トークはまだありません',
                        ),
                    },
                  ),
                ],
              ),
      ),
    );
  }

  Widget _tabs() {
    final tabs = <ButtonSegment<_ChatTab>>[
      const ButtonSegment(value: _ChatTab.all, label: Text('すべて')),
      const ButtonSegment(value: _ChatTab.site, label: Text('現場')),
      const ButtonSegment(value: _ChatTab.direct, label: Text('個別')),
      if (_canManagePartnerChat)
        const ButtonSegment(
          value: _ChatTab.partner,
          label: Text('協力会社'),
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: SegmentedButton<_ChatTab>(
        segments: tabs,
        selected: {_tab},
        onSelectionChanged: (value) =>
            setState(() => _tab = value.first),
      ),
    );
  }

  Widget _conversationView() {
    if (_selectedGroupId == null) {
      return const Center(
        child: Text(
          'トークを選択してください',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }

    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(child: Text('まだメッセージはありません'))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _MessageBubble(
                    message: _messages[index],
                    currentUserId: _repository?.currentUserId,
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: '写真・ファイル',
                onPressed: _sending ? null : _showAttachMenu,
                icon: const Icon(Icons.add_circle_outline),
              ),
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'メッセージ',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: '送信',
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupList(
    List<Map<String, dynamic>> groups, {
    required String emptyText,
  }) {
    if (groups.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        final group = groups[index];
        final selected =
            group['id']?.toString() == _selectedGroupId;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: group['avatar_url'] == null
                  ? null
                  : NetworkImage(group['avatar_url'].toString()),
              child: group['avatar_url'] == null
                  ? Icon(
                      group['group_type'] == 'site'
                          ? Icons.business_outlined
                          : Icons.groups_outlined,
                    )
                  : null,
            ),
            title: Text(
              group['display_name']?.toString() ??
                  group['name']?.toString() ??
                  '',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              _activityText(_lastActivity(group)),
            ),
            trailing: selected
                ? const Icon(Icons.chat_bubble)
                : const Icon(Icons.chevron_right),
            onTap: () => _selectGroup(group['id'].toString()),
          ),
        );
      },
    );
  }

  Widget _directList() {
    final members = _filteredMembers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
          child: TextField(
            controller: _memberSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: '社員を検索',
              hintText: '名前を入力',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: members.isEmpty
              ? const Center(child: Text('該当するメンバーはいません'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 5, 10, 10),
                  itemCount: members.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: member['avatar_url'] == null
                              ? null
                              : NetworkImage(
                                  member['avatar_url'].toString(),
                                ),
                          child: member['avatar_url'] == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(
                          member['display_name']?.toString() ??
                              'メンバー',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          member['role']?.toString() ?? '',
                        ),
                        trailing:
                            const Icon(Icons.chat_bubble_outline),
                        onTap: () => _startDirect(member),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _activityText(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) return 'まだ会話はありません';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.currentUserId,
  });

  final Map<String, dynamic> message;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final senderUserId = message['sender_user_id']?.toString();
    final origin = message['origin']?.toString() ?? 'sk_works';
    final own = origin == 'sk_works' &&
        senderUserId != null &&
        senderUserId == currentUserId;

    final sender = own
        ? '自分'
        : (message['sender_display_name']?.toString().trim().isNotEmpty ==
                true
            ? message['sender_display_name'].toString()
            : 'メンバー');

    final attachments = message['attachments'] is List
        ? List<Map<String, dynamic>>.from(
            message['attachments'] as List,
          )
        : const <Map<String, dynamic>>[];

    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        decoration: BoxDecoration(
          color: own
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!own)
              Text(
                sender,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (!own) const SizedBox(height: 3),
            for (final attachment in attachments) ...[
              if (attachment['attachment_type'] == 'image' &&
                  attachment['signed_url'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    attachment['signed_url'].toString(),
                    width: 250,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 90,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file_outlined),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          attachment['original_filename']?.toString() ??
                              'ファイル',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
            ],
            Text(message['body']?.toString() ?? ''),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                _formatTime(message['sent_at']?.toString()),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? value) {
    final parsed =
        value == null ? null : DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.hour)}:${two(parsed.minute)}';
  }
}
