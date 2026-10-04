import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../albums/albums_cloud_page.dart';
import '../notes/notes_cloud_page.dart';
import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import 'chat_appearance_page.dart';
import 'chat_cloud_repository.dart';
import 'chat_friends_page.dart';

enum _ChatTab { all, friends, site, groups, partner }

class ChatCloudPage extends StatefulWidget {
  const ChatCloudPage({
    super.key,
    this.viewerOnlyFriends = false,
    this.showGroupsInitially = false,
  });

  final bool viewerOnlyFriends;
  final bool showGroupsInitially;

  @override
  State<ChatCloudPage> createState() => _ChatCloudPageState();
}

class _ChatCloudPageState extends State<ChatCloudPage> {
  final _repository = ChatCloudRepository.maybeCreate();
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingGroupInvites = [];
  List<String> _prioritizedSiteGroupIds = const [];
  Set<String> _pinnedGroupIds = <String>{};
  Set<String> _hiddenGroupIds = <String>{};
  Set<String> _mutedGroupIds = <String>{};
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
  bool _appNotificationSoundEnabled = true;
  final Map<String, String?> _lastObservedMessageIdByGroup = <String, String?>{};
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
    if (widget.showGroupsInitially) {
      _tab = _ChatTab.groups;
    }
    _load();
  }

  Future<void> _loadListPreferences() async {
    final repository = _repository;
    final userId = repository?.currentUserId ?? 'anonymous';
    final prefs = await SharedPreferences.getInstance();
    _pinnedGroupIds =
        prefs.getStringList('sko_chat_pinned_$userId')?.toSet() ?? <String>{};
    _hiddenGroupIds =
        prefs.getStringList('sko_chat_hidden_$userId')?.toSet() ?? <String>{};
    _mutedGroupIds =
        prefs.getStringList('sko_chat_muted_$userId')?.toSet() ?? <String>{};
    _appNotificationSoundEnabled =
        prefs.getBool('sko_app_notification_sound_enabled') ?? true;
  }

  Future<void> _saveListPreference(
    String kind,
    Set<String> values,
  ) async {
    final repository = _repository;
    final userId = repository?.currentUserId ?? 'anonymous';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'sko_chat_${kind}_$userId',
      values.toList(growable: false),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _composer.dispose();
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
      var priorities = await repository.prioritizedSiteGroupIds();
      final blockedUserIds = await repository.loadBlockedUserIds();
      final friendWorkspace = await repository.loadFriendWorkspace();
      final rawFriends = friendWorkspace['friends'];
      final friends = rawFriends is List
          ? rawFriends
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : <Map<String, dynamic>>[];
      final pendingGroupInvites = await repository.loadPendingGroupInvites();
      await _loadListPreferences();

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
        _friends = friends;
        _pendingGroupInvites = pendingGroupInvites;
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
        final latest = messages.isEmpty ? null : messages.last;
        final latestId = latest?['id']?.toString();
        final previousId = _lastObservedMessageIdByGroup[id];
        final senderId = latest?['sender_user_id']?.toString();
        final shouldSound = previousId != null &&
            latestId != null &&
            latestId != previousId &&
            senderId != null &&
            senderId != repository.currentUserId &&
            _appNotificationSoundEnabled &&
            !_mutedGroupIds.contains(id);
        _lastObservedMessageIdByGroup[id] = latestId;
        if (shouldSound) {
          SystemSound.play(SystemSoundType.alert);
        }
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
    if (id == _selectedGroupId) return;
    Map<String, dynamic>? target;
    for (final group in _groups) {
      if (group['id']?.toString() == id) {
        target = group;
        break;
      }
    }
    final appearance = await ChatAppearanceStore.load(id);
    if (!mounted) return;
    setState(() {
      _selectedGroupId = id;
      _tab = _tabForGroup(target);
      _positionInitialMessages = true;
      _appearance = appearance;
      _chatChromeVisible = true;
      _unreadCounts = {..._unreadCounts, id: 0};
    });
    await _subscribeSelected();
  }

  _ChatTab _tabForGroup(Map<String, dynamic>? group) {
    if (_isCustomGroup(group)) return _ChatTab.groups;
    return switch (group?['group_type']?.toString()) {
      'direct' => _ChatTab.friends,
      'site' => _ChatTab.site,
      'partner' => _ChatTab.partner,
      _ => _ChatTab.all,
    };
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

  Future<void> _openFriendsForChat() async {
    final friend = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => const ChatFriendsPage(selectForChat: true),
      ),
    );
    if (friend == null || !mounted) return;
    await _startDirect(friend);
  }

  Future<void> _createCustomGroup() async {
    final repository = _repository;
    if (repository == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('グループチャット作成'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'グループ名',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final id = await repository.createCustomGroup(name);
      await _load();
      if (!mounted) return;
      await _selectGroup(id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('グループを作成できませんでした: $error')),
      );
    }
  }

  Future<void> _inviteFriendToSelectedGroup() async {
    final repository = _repository;
    final groupId = _selectedGroupId;
    if (repository == null || groupId == null) return;
    final friend = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => const ChatFriendsPage(selectForGroupInvite: true),
      ),
    );
    if (friend == null || !mounted) return;
    final friendUserId = friend['user_id']?.toString() ?? '';
    if (friendUserId.isEmpty) return;
    try {
      await repository.inviteFriendToGroup(
        groupId: groupId,
        friendUserId: friendUserId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('グループ招待の承認通知を送りました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('友達を招待できませんでした: $error')),
      );
    }
  }

  Future<void> _respondGroupInvite(
    Map<String, dynamic> invite,
    bool accept,
  ) async {
    final repository = _repository;
    final inviteId = invite['id']?.toString() ?? '';
    if (repository == null || inviteId.isEmpty) return;
    try {
      final groupId = await repository.respondGroupInvite(
        inviteId: inviteId,
        accept: accept,
      );
      await _load();
      if (!mounted || !accept || groupId.isEmpty) return;
      await _selectGroup(groupId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('グループ招待を処理できませんでした: $error')),
      );
    }
  }

  Future<void> _leaveSelectedGroup() async {
    final repository = _repository;
    final groupId = _selectedGroupId;
    if (repository == null || groupId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('グループから脱退しますか？'),
        content: const Text(
          '最後の1名が脱退した場合、このグループは削除されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('脱退'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.leaveCustomGroup(groupId);
    if (!mounted) return;
    await _closeConversation();
    await _load();
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
    final selectedGroup = _selectedGroup;
    if (repository == null || groupId == null) return;

    try {
      final members = _isCustomGroup(selectedGroup)
          ? await repository.loadCustomGroupMembers(groupId)
          : await repository.loadGroupMembers(groupId);
      if (!mounted) return;
      final customGroup = _isCustomGroup(selectedGroup);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    '${SkoLanguageController.tr('参加メンバー')}  ${members.length}${SkoLanguageController.isEnglish ? '' : '人'}',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                if (customGroup)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _inviteFriendToSelectedGroup();
                            },
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('友達招待'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _leaveSelectedGroup();
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text('脱退'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: members.isEmpty
                      ? Center(
                          child: Text(
                            SkoLanguageController.tr('参加メンバーはいません'),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(10),
                          itemCount: members.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final avatarUrl =
                                member['avatar_url']?.toString();
                            final userId =
                                member['user_id']?.toString() ?? '';
                            final isMe = userId == repository.currentUserId;
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
                                customGroup && !isMe
                                    ? '長押しで追放'
                                    : member['company_name']?.toString() ?? '',
                              ),
                              onLongPress: !customGroup || isMe
                                  ? null
                                  : () async {
                                      final confirmed =
                                          await showDialog<bool>(
                                        context: sheetContext,
                                        builder: (dialogContext) =>
                                            AlertDialog(
                                          title: const Text(
                                            'このメンバーを追放しますか？',
                                          ),
                                          content: Text(
                                            member['display_name']
                                                    ?.toString() ??
                                                'メンバー',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(
                                                dialogContext,
                                                false,
                                              ),
                                              child: const Text('戻る'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(
                                                dialogContext,
                                                true,
                                              ),
                                              child: const Text('追放'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true) return;
                                      try {
                                        await repository
                                            .removeCustomGroupMember(
                                          groupId: groupId,
                                          userId: userId,
                                        );
                                        if (sheetContext.mounted) {
                                          Navigator.pop(sheetContext);
                                        }
                                        if (mounted) {
                                          await _showSelectedGroupMembers();
                                        }
                                      } catch (error) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'メンバーを追放できませんでした: $error',
                                            ),
                                          ),
                                        );
                                      }
                                    },
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
        SnackBar(
          content: Text(
            '${SkoLanguageController.tr('参加メンバーを読み込めませんでした')}: $error',
          ),
        ),
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

  List<Map<String, dynamic>> get _friendGroups {
    final friendIds = _friends
        .map((friend) => friend['user_id']?.toString())
        .whereType<String>()
        .toSet();
    final groups = _directGroups.where((group) {
      final other = group['direct_other_user_id']?.toString();
      return other != null && friendIds.contains(other);
    }).toList();
    return groups;
  }

  List<Map<String, dynamic>> get _customGroups {
    final groups = _groups.where((group) {
      final id = group['id']?.toString() ?? '';
      return group['group_type'] == 'company' &&
          group['participants_only'] == true &&
          !_hiddenGroupIds.contains(id);
    }).toList();
    groups.sort((a, b) {
      final aId = a['id']?.toString() ?? '';
      final bId = b['id']?.toString() ?? '';
      final aPinned = _pinnedGroupIds.contains(aId);
      final bPinned = _pinnedGroupIds.contains(bId);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      return _lastActivity(b).compareTo(_lastActivity(a));
    });
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
          TextButton.icon(
            onPressed: _openFriendsForChat,
            icon: const Icon(Icons.people_outline),
            label: const Text(
              '友達一覧',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
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
                      _ChatTab.friends => _selectedGroupId != null &&
                              selected?['group_type'] == 'direct'
                          ? _conversationView()
                          : _groupList(
                              _friendGroups,
                              emptyText: SkoLanguageController.tr('友達とのトークはまだありません'),
                            ),
                      _ChatTab.site => _selectedGroupId != null &&
                              selected?['group_type'] == 'site'
                          ? _conversationView()
                          : _groupList(
                              _siteGroups,
                              emptyText: SkoLanguageController.tr('現場トークはまだありません'),
                            ),
                      _ChatTab.groups => _selectedGroupId != null &&
                              _isCustomGroup(selected)
                          ? _conversationView()
                          : _groupWorkspace(),
                      _ChatTab.partner => _selectedGroupId != null &&
                              selected?['group_type'] == 'partner'
                          ? _conversationView()
                          : _groupList(
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
      (_ChatTab.friends, SkoLanguageController.tr('友達')),
      (_ChatTab.site, SkoLanguageController.tr('現場')),
      (_ChatTab.groups, SkoLanguageController.tr('グループ')),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < tabs.length; index++) ...[
              SizedBox(
                width: 78,
                child: _chatTabButton(
                  tab: tabs[index].$1,
                  label: tabs[index].$2,
                ),
              ),
              if (index < tabs.length - 1) const SizedBox(width: 5),
            ],
          ],
        ),
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
        if (_isCustomGroup(_selectedGroup))
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _inviteFriendToSelectedGroup,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text(
                  '友達を招待',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
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

  bool _isCustomGroup(Map<String, dynamic>? group) =>
      group != null &&
      group['group_type'] == 'company' &&
      group['participants_only'] == true;

  Widget _groupWorkspace() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _createCustomGroup,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text(
                'グループチャット作成',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        if (_pendingGroupInvites.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.mark_email_unread_outlined),
                    title: Text(
                      'グループ招待',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  for (final invite in _pendingGroupInvites)
                    ListTile(
                      title: Text(
                        invite['group_name']?.toString() ?? 'グループ',
                      ),
                      subtitle: Text(
                        '${invite['inviter_name']?.toString() ?? 'SKOユーザー'}さんから招待',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: '拒否',
                            onPressed: () => _respondGroupInvite(invite, false),
                            icon: const Icon(Icons.close),
                          ),
                          IconButton(
                            tooltip: '承認',
                            onPressed: () => _respondGroupInvite(invite, true),
                            icon: const Icon(Icons.check_circle_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _groupList(
            _customGroups,
            emptyText: 'グループチャットはまだありません',
            enableGroupActions: true,
          ),
        ),
      ],
    );
  }

  Future<bool> _handleCustomGroupSwipe(
    Map<String, dynamic> group,
    DismissDirection direction,
  ) async {
    if (direction == DismissDirection.endToStart) {
      await _showCustomGroupLeftActions(group);
    } else if (direction == DismissDirection.startToEnd) {
      await _showCustomGroupRightActions(group);
    }
    return false;
  }

  Future<void> _showCustomGroupLeftActions(
    Map<String, dynamic> group,
  ) async {
    final groupId = group['id']?.toString() ?? '';
    if (groupId.isEmpty) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('非表示'),
              onTap: () => Navigator.pop(sheetContext, 'hide'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                '削除',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'hide') {
      setState(() => _hiddenGroupIds.add(groupId));
      await _saveListPreference('hidden', _hiddenGroupIds);
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('グループを削除しますか？'),
          content: const Text('この操作は元に戻せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('削除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await _repository?.deleteCustomGroup(groupId);
        await _load();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('グループを削除できませんでした: $error')),
        );
      }
    }
  }

  Future<void> _showCustomGroupRightActions(
    Map<String, dynamic> group,
  ) async {
    final groupId = group['id']?.toString() ?? '';
    if (groupId.isEmpty) return;
    final pinned = _pinnedGroupIds.contains(groupId);
    final muted = _mutedGroupIds.contains(groupId);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(pinned ? 'ピン留めを解除' : '上位にピン留め'),
              onTap: () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: Icon(
                muted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
              ),
              title: Text(
                muted ? '通知音をON' : '通知音をOFF',
              ),
              onTap: () => Navigator.pop(sheetContext, 'sound'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'pin') {
      setState(() {
        if (pinned) {
          _pinnedGroupIds.remove(groupId);
        } else {
          _pinnedGroupIds.add(groupId);
        }
      });
      await _saveListPreference('pinned', _pinnedGroupIds);
    } else if (action == 'sound') {
      setState(() {
        if (muted) {
          _mutedGroupIds.remove(groupId);
        } else {
          _mutedGroupIds.add(groupId);
        }
      });
      await _saveListPreference('muted', _mutedGroupIds);
    }
  }

  Widget _groupList(
    List<Map<String, dynamic>> groups, {
    required String emptyText,
    bool enableGroupActions = false,
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

        final card = Card(
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

        if (!enableGroupActions || !_isCustomGroup(group)) {
          return card;
        }

        final groupId = group['id']?.toString() ?? '';
        return Dismissible(
          key: ValueKey('custom-group-$groupId'),
          confirmDismiss: (direction) =>
              _handleCustomGroupSwipe(group, direction),
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _pinnedGroupIds.contains(groupId)
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                ),
                const SizedBox(width: 10),
                Icon(
                  _mutedGroupIds.contains(groupId)
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                ),
              ],
            ),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.visibility_off_outlined),
                SizedBox(width: 10),
                Icon(Icons.delete_outline),
              ],
            ),
          ),
          child: card,
        );
      },
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
