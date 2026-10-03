import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../albums/albums_cloud_page.dart';
import '../notes/notes_cloud_page.dart';
import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import 'chat_appearance_page.dart';
import 'chat_cloud_repository.dart';
import 'chat_friends_page.dart';

enum _ChatTab { all, site, direct, partner }

class ChatCloudPage extends StatefulWidget {
  const ChatCloudPage({
    super.key,
    this.viewerOnlyFriends = false,
  });

  final bool viewerOnlyFriends;

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
  Set<String> _blockedUserIds = <String>{};
  Map<String, int> _unreadCounts = const {};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  ChatAppearance _appearance = const ChatAppearance();
  bool _positionInitialMessages = false;
  bool _chatChromeVisible = true;
  int? _edgePointer;
  Offset? _edgeStart;
  bool _edgeTriggered = false;

  String? _selectedGroupId;
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
        _error = SkoLanguageController.tr('チャットを利用できません。');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final canManagePartnerChat = await repository.canManagePartnerChat();
      var groups = await repository.loadGroups();
      var members = await repository.loadMembers();
      var priorities = await repository.prioritizedSiteGroupIds();
      final blockedUserIds = await repository.loadBlockedUserIds();

      if (widget.viewerOnlyFriends) {
        final workspace = await repository.loadFriendWorkspace();
        final rawFriends = workspace['friends'];
        final friendIds = <String>{
          if (rawFriends is List)
            for (final item in rawFriends)
              if (item is Map && item['user_id'] != null)
                item['user_id'].toString(),
        };
        groups = groups.where((group) {
          if (group['group_type']?.toString() != 'direct') return false;
          final otherUserId = group['direct_other_user_id']?.toString();
          return otherUserId != null && friendIds.contains(otherUserId);
        }).toList(growable: false);
        members = members
            .where((member) => friendIds.contains(member['user_id']?.toString()))
            .toList(growable: false);
        priorities = const [];
      }

      final previous = _selectedGroupId;
      final next = groups.any((g) => g['id']?.toString() == previous)
          ? previous
          : null;

      if (!mounted) return;
      setState(() {
        _canManagePartnerChat = canManagePartnerChat;
        if (!_canManagePartnerChat && _tab == _ChatTab.partner) {
          _tab = _ChatTab.all;
        }
        _groups = groups;
        _members = members;
        _prioritizedSiteGroupIds = priorities;
        _blockedUserIds = blockedUserIds;
        _selectedGroupId = next;
        _loading = false;
      });

      await _refreshUnreadCounts(groups);
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
        setState(() {
          _messages = messages;
          for (final message in messages) {
            final id = message['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              _messageKeys.putIfAbsent(id, GlobalKey.new);
            }
          }
        });
        if (_positionInitialMessages) {
          _positionInitialMessageView(messages);
        } else if (_isNearBottom()) {
          _scrollToBottom();
          _markRead(id);
        }
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
    final appearance = await ChatAppearanceStore.load(id);
    if (!mounted) return;
    setState(() {
      _selectedGroupId = id;
      _tab = _ChatTab.all;
      _positionInitialMessages = true;
      _appearance = appearance;
      _chatChromeVisible = true;
      _unreadCounts = {..._unreadCounts, id: 0};
    });
    await _subscribeSelected();
  }

  Future<void> _closeConversation() async {
    await _subscription?.cancel();
    _subscription = null;
    if (!mounted) return;
    setState(() {
      _selectedGroupId = null;
      _messages = [];
      _positionInitialMessages = false;
      _chatChromeVisible = true;
      _tab = _ChatTab.all;
    });
  }

  void _chatPointerDown(PointerDownEvent event) {
    if (_selectedGroupId == null || event.position.dx > 24) return;
    _edgePointer = event.pointer;
    _edgeStart = event.position;
    _edgeTriggered = false;
  }

  void _chatPointerMove(PointerMoveEvent event) {
    if (_edgePointer != event.pointer || _edgeTriggered) return;
    final start = _edgeStart;
    if (start == null) return;
    final dx = event.position.dx - start.dx;
    final dy = (event.position.dy - start.dy).abs();
    if (dx >= 72 && dx > dy * 1.4) {
      _edgeTriggered = true;
      _closeConversation();
    }
  }

  void _chatPointerEnd(PointerEvent event) {
    if (_edgePointer != event.pointer) return;
    _edgePointer = null;
    _edgeStart = null;
    _edgeTriggered = false;
  }

  Future<void> _markRead(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sko_chat_last_read_$groupId',
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> _refreshUnreadCounts(
    List<Map<String, dynamic>> groups,
  ) async {
    final repository = _repository;
    if (repository == null || groups.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final lastRead = <String, DateTime>{};
    final fallback = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final group in groups) {
      final id = group['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final raw = prefs.getString('sko_chat_last_read_$id');
      lastRead[id] = DateTime.tryParse(raw ?? '') ?? fallback;
    }
    try {
      final counts = await repository.loadUnreadCounts(lastRead);
      if (!mounted) return;
      setState(() => _unreadCounts = counts);
    } catch (_) {
      // Unread badges are supplemental and must not block chat loading.
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels < 120;
  }

  void _positionInitialMessageView(List<Map<String, dynamic>> messages) {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _scrollToBottom();
      _positionInitialMessages = false;
      await _markRead(groupId);
      if (!mounted) return;
      setState(() => _unreadCounts = {..._unreadCounts, groupId: 0});
    });
  }

  Future<void> _openAppearance() async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;
    final value = await Navigator.of(context).push<ChatAppearance>(
      MaterialPageRoute(
        builder: (_) => ChatAppearancePage(
          groupId: groupId,
          initial: _appearance,
        ),
      ),
    );
    if (value == null || !mounted) return;
    setState(() => _appearance = value);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
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
        SnackBar(content: Text('${SkoLanguageController.tr('送信できませんでした')}: $error')),
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
        SnackBar(content: Text('${SkoLanguageController.tr('個別トークを開始できませんでした')}: $error')),
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
        SnackBar(content: Text('${SkoLanguageController.tr('写真を送信できませんでした')}: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachCamera() async {
    final id = _selectedGroupId;
    final repository = _repository;
    if (id == null || repository == null) return;

    final file = await _picker.pickImage(
      source: ImageSource.camera,
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
        SnackBar(content: Text('${SkoLanguageController.tr('カメラ写真を送信できませんでした')}: $error')),
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
        SnackBar(content: Text('${SkoLanguageController.tr('ファイルを送信できませんでした')}: $error')),
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
              title: Text(SkoLanguageController.tr('写真')),
              onTap: () {
                Navigator.pop(sheetContext);
                _attachPhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(SkoLanguageController.tr('カメラ')),
              onTap: () {
                Navigator.pop(sheetContext);
                _attachCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(SkoLanguageController.tr('ファイル')),
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

  Future<void> _toggleBlockSelectedDirect() async {
    final repository = _repository;
    final otherUserId = _selectedGroup?['direct_other_user_id']?.toString();
    if (repository == null || otherUserId == null || otherUserId.isEmpty) {
      return;
    }
    final currentlyBlocked = _blockedUserIds.contains(otherUserId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentlyBlocked ? 'ブロックを解除しますか？' : 'この相手をブロックしますか？'),
        content: Text(
          currentlyBlocked
              ? '解除後は再びメッセージを送受信できます。'
              : 'ブロック中はこの相手とのやり取りを制限します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(SkoLanguageController.tr('戻る')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(currentlyBlocked ? '解除する' : 'ブロックする'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.setBlocked(
      userId: otherUserId,
      blocked: !currentlyBlocked,
    );
    if (!mounted) return;
    setState(() {
      final next = <String>{..._blockedUserIds};
      if (currentlyBlocked) {
        next.remove(otherUserId);
      } else {
        next.add(otherUserId);
      }
      _blockedUserIds = next;
    });
  }

  Future<void> _confirmDeleteOwnMessage(Map<String, dynamic> message) async {
    final repository = _repository;
    if (repository == null) return;
    final id = message['id']?.toString() ?? '';
    final sender = message['sender_user_id']?.toString();
    if (id.isEmpty || sender != repository.currentUserId) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(SkoLanguageController.isEnglish ? 'Delete this message?' : 'メッセージを削除しますか？'),
        content: Text(SkoLanguageController.isEnglish ? 'You can only delete messages you sent.' : '自分が送信したメッセージだけ削除できます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(SkoLanguageController.isEnglish ? 'Delete' : '削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repository.deleteOwnMessage(id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${SkoLanguageController.tr('削除できませんでした')}: $error')),
      );
    }
  }

  Future<void> _openFriends() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChatFriendsPage()),
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

  Future<void> _showSelectedGroupMembers() async {
    final repository = _repository;
    final groupId = _selectedGroupId;
    if (repository == null || groupId == null) return;

    try {
      final members = await repository.loadGroupMembers(groupId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    '${SkoLanguageController.tr('参加メンバー')}  ${members.length}${SkoLanguageController.isEnglish ? '' : '人'}',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: members.isEmpty
                      ? Center(child: Text(SkoLanguageController.tr('参加メンバーはいません')))
                      : ListView.separated(
                          padding: const EdgeInsets.all(10),
                          itemCount: members.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final avatarUrl =
                                member['avatar_url']?.toString();
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage:
                                    avatarUrl == null || avatarUrl.isEmpty
                                        ? null
                                        : NetworkImage(avatarUrl),
                                child: avatarUrl == null || avatarUrl.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Text(
                                member['display_name']?.toString() ??
                                    SkoLanguageController.tr('メンバー'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                member['company_name']?.toString() ?? '',
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${SkoLanguageController.tr('参加メンバーを読み込めませんでした')}: $error')),
      );
    }
  }

  List<Map<String, dynamic>> get _allGroups {
    final groups = List<Map<String, dynamic>>.from(_groups);
    groups.sort(
      (a, b) => _lastActivity(b).compareTo(_lastActivity(a)),
    );
    return groups;
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
    final wallpaperPath =
        selected == null ? null : _appearance.wallpaperPath?.trim();

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Theme.of(context).colorScheme.surface,
        ),
        if (wallpaperPath != null && wallpaperPath.isNotEmpty)
          Opacity(
            opacity: _appearance.backgroundAlpha,
            child: Image.file(
              File(wallpaperPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _chatPointerDown,
      onPointerMove: _chatPointerMove,
      onPointerUp: _chatPointerEnd,
      onPointerCancel: _chatPointerEnd,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: selected != null && !_chatChromeVisible
          ? null
          : AppBar(
        backgroundColor: Theme.of(context)
            .colorScheme
            .surface
            .withValues(alpha: _appearance.headerAlpha),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        leading: selected == null
            ? null
            : IconButton(
                tooltip: SkoLanguageController.tr('トーク一覧に戻る'),
                onPressed: _closeConversation,
                icon: const Icon(Icons.arrow_back_ios_new),
              ),
        title: selected == null
            ? const Text(
                'チャット',
                style: TextStyle(fontWeight: FontWeight.w900),
              )
            : InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _showSelectedGroupMembers,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          selected['display_name']?.toString() ?? SkoLanguageController.tr('チャット'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.group_outlined, size: 18),
                    ],
                  ),
                ),
              ),
        actions: [
          IconButton(
            tooltip: SkoLanguageController.tr('友達追加'),
            onPressed: _openFriends,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          const SkoNotificationBell(),
          if (selected != null)
            PopupMenuButton<String>(
              tooltip: SkoLanguageController.tr('トーク機能'),
              onSelected: (value) {
                if (value == 'notes') _openNotes();
                if (value == 'albums') _openAlbums();
                if (value == 'block') _toggleBlockSelectedDirect();
                if (value == 'appearance') _openAppearance();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'notes',
                  child: ListTile(
                    leading: Icon(Icons.sticky_note_2_outlined),
                    title: Text(SkoLanguageController.tr('ノート')),
                  ),
                ),
                PopupMenuItem(
                  value: 'albums',
                  child: ListTile(
                    leading: Icon(Icons.photo_album_outlined),
                    title: Text(SkoLanguageController.tr('アルバム')),
                  ),
                ),
                PopupMenuItem(
                  value: 'appearance',
                  child: ListTile(
                    leading: Icon(Icons.wallpaper_outlined),
                    title: Text(SkoLanguageController.tr('背景・透明度')),
                  ),
                ),
                if (selected['group_type'] == 'direct')
                  PopupMenuItem(
                    value: 'block',
                    child: ListTile(
                      leading: const Icon(Icons.block_outlined),
                      title: Text(
                        _blockedUserIds.contains(
                          selected['direct_other_user_id']?.toString(),
                        )
                            ? SkoLanguageController.tr('ブロック解除')
                            : SkoLanguageController.tr('ブロック'),
                      ),
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
                  if (selected == null || _chatChromeVisible) ...[
                    _tabs(),
                    Divider(
                      height: 1,
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: _appearance.headerAlpha),
                    ),
                  ],
                  Expanded(
                    child: switch (_tab) {
                      _ChatTab.all => _selectedGroupId == null
                          ? _groupList(
                              _allGroups,
                              emptyText: SkoLanguageController.tr('トークはまだありません'),
                            )
                          : _conversationView(),
                      _ChatTab.site => _groupList(
                          _siteGroups,
                          emptyText: SkoLanguageController.tr('現場トークはまだありません'),
                        ),
                      _ChatTab.direct => _directList(),
                      _ChatTab.partner => _groupList(
                          _partnerGroups,
                          emptyText: SkoLanguageController.tr('協力会社トークはまだありません'),
                        ),
                    },
                  ),
                ],
              ),
      ),
      ),
        ),
      ],
    );
  }

  Widget _tabs() {
    final tabs = <(_ChatTab, String)>[
      (_ChatTab.all, SkoLanguageController.tr('すべて')),
      (_ChatTab.site, SkoLanguageController.tr('現場')),
      (_ChatTab.direct, SkoLanguageController.tr('個別')),
      if (_canManagePartnerChat)
        (_ChatTab.partner, SkoLanguageController.tr('協力会社')),
    ];

    return Container(
      width: double.infinity,
      color: Theme.of(context)
          .colorScheme
          .surface
          .withValues(alpha: _appearance.headerAlpha),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++) ...[
            Expanded(
              child: _chatTabButton(
                tab: tabs[index].$1,
                label: tabs[index].$2,
              ),
            ),
            if (index < tabs.length - 1) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }

  Widget _chatTabButton({
    required _ChatTab tab,
    required String label,
  }) {
    final selected = _tab == tab;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: (selected ? scheme.primaryContainer : scheme.surface)
          .withValues(alpha: _appearance.headerAlpha),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _tab = tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _conversationView() {
    if (_selectedGroupId == null) {
      return Center(
        child: Text(
          SkoLanguageController.tr('トークを選択してください'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }

    final archived = _selectedGroup?['archived_at'] != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
        if (archived)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Row(
              children: [
                Icon(Icons.archive_outlined, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'この現場は終了済みです。履歴は閲覧できますが、新しいメッセージは送信できません。',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
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
              ? Center(child: Text(SkoLanguageController.tr('まだメッセージはありません')))
              : NotificationListener<ScrollUpdateNotification>(
                  onNotification: (notification) {
                    final delta = notification.scrollDelta ?? 0;
                    if (delta > 4 && _chatChromeVisible) {
                      setState(() => _chatChromeVisible = false);
                    } else if (delta < -4 && !_chatChromeVisible) {
                      setState(() => _chatChromeVisible = true);
                    }
                    return false;
                  },
                  child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[_messages.length - 1 - index];
                    final messageId = message['id']?.toString() ?? '';
                    return _MessageBubble(
                      key: messageId.isEmpty ? null : _messageKeys[messageId],
                      message: message,
                      currentUserId: _repository?.currentUserId,
                      bubbleOpacity: _appearance.bubbleAlpha,
                      onDelete: () => _confirmDeleteOwnMessage(message),
                    );
                  },
                ),
                ),
        ),
        if (_chatChromeVisible)
          Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: _appearance.footerAlpha),
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: SkoLanguageController.tr('写真・ファイル'),
                onPressed: _sending || archived ? null : _showAttachMenu,
                icon: const Icon(Icons.add_circle_outline),
              ),
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !archived,
                  decoration: InputDecoration(
                    hintText: archived ? SkoLanguageController.tr('アーカイブ済み') : SkoLanguageController.tr('メッセージ'),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: SkoLanguageController.tr('送信'),
                onPressed: _sending || archived ? null : _send,
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
              group['archived_at'] != null
                  ? 'アーカイブ済み / \${_activityText(_lastActivity(group))}'
                  : _activityText(_lastActivity(group)),
            ),
            trailing: _unreadCounts[group['id']?.toString()] != null &&
                    (_unreadCounts[group['id']?.toString()] ?? 0) > 0
                ? Badge(
                    label: Text(
                      (_unreadCounts[group['id']?.toString()] ?? 0).toString(),
                    ),
                    child: const Icon(Icons.chat_bubble_outline),
                  )
                : selected
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
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: SkoLanguageController.tr('社員を検索'),
              hintText: SkoLanguageController.tr('名前を入力'),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: members.isEmpty
              ? Center(child: Text(SkoLanguageController.tr('該当するメンバーはいません')))
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
                              SkoLanguageController.tr('メンバー'),
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
    if (value.millisecondsSinceEpoch == 0) return SkoLanguageController.tr('まだ会話はありません');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.bubbleOpacity,
    required this.onDelete,
  });

  final Map<String, dynamic> message;
  final String? currentUserId;
  final double bubbleOpacity;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final senderUserId = message['sender_user_id']?.toString();
    final origin = message['origin']?.toString() ?? 'sk_works';
    final own = origin == 'sk_works' &&
        senderUserId != null &&
        senderUserId == currentUserId;

    final sender = own
        ? SkoLanguageController.tr('自分')
        : (message['sender_display_name']?.toString().trim().isNotEmpty ==
                true
            ? message['sender_display_name'].toString()
            : SkoLanguageController.tr('メンバー'));

    final attachments = message['attachments'] is List
        ? List<Map<String, dynamic>>.from(
            message['attachments'] as List,
          )
        : const <Map<String, dynamic>>[];

    final time = _formatTime(message['sent_at']?.toString());
    final bubble = Flexible(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: (own
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHigh)
              .withValues(alpha: bubbleOpacity),
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
                              SkoLanguageController.tr('ファイル'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
            ],
            Text(message['body']?.toString() ?? ''),
          ],
        ),
      ),
    );

    final timeWidget = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        time,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );

    return GestureDetector(
      onLongPress: own ? onDelete : null,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            own ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: own
            ? [
                timeWidget,
                const SizedBox(width: 6),
                bubble,
              ]
            : [
                bubble,
                const SizedBox(width: 6),
                timeWidget,
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
