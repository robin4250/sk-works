import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import 'package:image_picker/image_picker.dart';

import 'albums_cloud_repository.dart';
import '../notes/notes_cloud_page.dart' show CommunicationLoadGuard;

class AlbumsCloudPage extends StatefulWidget {
  const AlbumsCloudPage({
    super.key,
    this.initialGroupId,
    this.repository,
    this.currentActorId,
  });

  final String? initialGroupId;
  final AlbumsCloudRepository? repository;
  final String? Function()? currentActorId;

  @override
  State<AlbumsCloudPage> createState() => _AlbumsCloudPageState();
}

class _AlbumsCloudPageState extends State<AlbumsCloudPage> {
  late final _repository = widget.repository ?? AlbumsCloudRepository.maybeCreate();
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _albums = [];
  String? _selectedGroupId;
  final _groupGuard = CommunicationLoadGuard();
  final _contentGuard = CommunicationLoadGuard();
  StreamSubscription<dynamic>? _authSubscription;
  String? get _actorId => widget.currentActorId?.call() ??
      (SupabaseBackend.isInitialized
          ? SupabaseBackend.client.auth.currentUser?.id
          : null);
  bool _loading = true;
  bool _loadingAlbums = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (SupabaseBackend.isInitialized) {
      var actor = _actorId;
      _authSubscription = SupabaseBackend.client.auth.onAuthStateChange.listen((_) {
        if (actor == _actorId) return;
        actor = _actorId;
        _groupGuard.invalidate();
        _contentGuard.invalidate();
        if (!mounted) return;
        setState(() {
          _groups = [];
          _albums = [];
          _selectedGroupId = null;
          _loadingAlbums = false;
        });
        _load();
      });
    }
    _load();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _groupGuard.invalidate();
    _contentGuard.invalidate();
    super.dispose();
  }

  Future<void> _load() async {
    final actor = _actorId;
    final preferredGroup = _selectedGroupId ?? widget.initialGroupId;
    final request = _groupGuard.invalidate();
    _contentGuard.invalidate();
    setState(() {
      _groups = [];
      _albums = [];
      _selectedGroupId = null;
      _loading = true;
      _error = null;
    });
    if (_repository == null || actor == null) {
      setState(() {
        _loading = false;
        _error = 'Supabaseに接続されていません。';
      });
      return;
    }
    try {
      final groups = await _repository.loadGroups();
      if (!mounted || !_groupGuard.accepts(request, actor, _actorId)) return;
      setState(() {
        _groups = groups;
        _selectedGroupId = groups.any(
          (group) => group['id']?.toString() == preferredGroup,
        )
            ? preferredGroup
            : (preferredGroup != null || groups.isEmpty
                ? null : groups.first['id'] as String);
        if (preferredGroup != null && _selectedGroupId == null) {
          _error = '指定されたグループを表示できません。参加権限を確認してください。';
        }
        _loading = false;
      });
      await _loadAlbums();
    } catch (e) {
      if (!mounted || !_groupGuard.accepts(request, actor, _actorId)) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadAlbums() async {
    final groupId = _selectedGroupId;
    final actor = _actorId;
    final request = _contentGuard.invalidate();
    if (_repository == null || groupId == null) return;
    setState(() {
      _albums = [];
      _loadingAlbums = true;
      _error = null;
    });
    try {
      final albums = await _repository.loadAlbums(groupId);
      if (!mounted || !_contentGuard.accepts(request, actor, _actorId,
          requestedGroup: groupId, currentGroup: _selectedGroupId)) return;
      setState(() {
        _albums = albums;
        _loadingAlbums = false;
      });
    } catch (e) {
      if (!mounted || !_contentGuard.accepts(request, actor, _actorId,
          requestedGroup: groupId, currentGroup: _selectedGroupId)) return;
      setState(() {
        _albums = [];
        _loadingAlbums = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アルバム')),
      floatingActionButton: _selectedGroupId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _createAlbum,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('新規アルバム'),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    if (_groups.isEmpty || _selectedGroupId == null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(_error ?? '表示できる参加グループがありません。'),
                        ),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
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
                          if (value == null) return;
                          setState(() => _selectedGroupId = value);
                          await _loadAlbums();
                        },
                      ),
                      const SizedBox(height: 14),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      if (_loadingAlbums)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_albums.isEmpty)
                        const Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text('アルバムはまだありません。'),
                          ),
                        )
                      else
                        for (final album in _albums)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.photo_album_outlined),
                                ),
                                title: Text(
                                  album['name'].toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: (album['description'] ?? '').toString().trim().isEmpty
                                    ? null
                                    : Text(album['description'].toString()),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  final repository = _repository;
                                  final groupId = _selectedGroupId;
                                  if (repository == null || groupId == null) return;
                                  final changed = await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => AlbumDetailPage(
                                        repository: repository,
                                        groupId: groupId,
                                        album: album,
                                      ),
                                    ),
                                  );
                                  if (changed == true) await _loadAlbums();
                                },
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _createAlbum() async {
    final actor = _actorId;
    final groupId = _selectedGroupId;
    if (_repository == null || groupId == null) return;
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新規アルバム'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'アルバム名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: '説明（任意）'),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('作成'),
          ),
        ],
      ),
    );
    if (!mounted || result != true || actor != _actorId || groupId != _selectedGroupId) {
      nameController.dispose();
      descriptionController.dispose();
      return;
    }
    try {
      await _repository.createAlbum(
        groupId: groupId,
        name: nameController.text,
        description: descriptionController.text,
      );
      if (!mounted || actor != _actorId || groupId != _selectedGroupId) return;
      await _loadAlbums();
    } catch (e) {
      if (!mounted || actor != _actorId || groupId != _selectedGroupId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('アルバムを作成できませんでした: $e')),
      );
    } finally {
      nameController.dispose();
      descriptionController.dispose();
    }
  }
}

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    super.key,
    required this.repository,
    required this.groupId,
    required this.album,
  });

  final AlbumsCloudRepository repository;
  final String groupId;
  final Map<String, dynamic> album;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final _picker = ImagePicker();
  final _detailGuard = CommunicationLoadGuard();
  StreamSubscription<dynamic>? _authSubscription;
  String? get _actorId => SupabaseBackend.isInitialized
      ? SupabaseBackend.client.auth.currentUser?.id : null;
  String? _ownerId;
  bool get _sameActor => _ownerId != null && _ownerId == _actorId;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  String get _albumId => widget.album['id'] as String;

  @override
  void initState() {
    super.initState();
    _ownerId = _actorId;
    if (SupabaseBackend.isInitialized) {
      _authSubscription = SupabaseBackend.client.auth.onAuthStateChange.listen((_) {
        if (_sameActor || !mounted) return;
        _detailGuard.invalidate();
        setState(() {
          _items = [];
          _loading = false;
          _error = '利用者が変更されました。アルバムを開き直してください。';
        });
      });
    }
    _load();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _detailGuard.invalidate();
    super.dispose();
  }

  Future<void> _load() async {
    final actor = _actorId;
    final request = _detailGuard.invalidate();
    if (!_sameActor) return;
    setState(() {
      _items = [];
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.loadItems(_albumId);
      if (!mounted || !_detailGuard.accepts(request, actor, _actorId)) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || !_detailGuard.accepts(request, actor, _actorId)) return;
      setState(() {
        _items = [];
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_sameActor ? widget.album['name'].toString() : 'アルバム'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (_sameActor && value == 'delete') _deleteAlbum();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('アルバムを削除')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: !_sameActor || _uploading ? null : _pickPhotos,
        icon: _uploading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_uploading ? 'アップロード中' : '写真を追加'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (_error != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ),
                    if (_items.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('写真はまだありません。')),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = _items[index];
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onLongPress: () => _confirmDeleteItem(item),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        item['signed_url'].toString(),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Center(
                                          child: Icon(Icons.broken_image_outlined),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: IconButton.filledTonal(
                                          tooltip: '削除',
                                          onPressed: () => _confirmDeleteItem(item),
                                          icon: const Icon(Icons.delete_outline),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            childCount: _items.length,
                          ),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 90);
      if (files.isEmpty || !_sameActor) return;
      if (!mounted) return;
      setState(() => _uploading = true);
      for (final file in files) {
        final bytes = await file.readAsBytes();
        if (!mounted || !_sameActor) return;
        await widget.repository.uploadPhoto(
          groupId: widget.groupId,
          albumId: _albumId,
          bytes: bytes,
          originalFilename: file.name,
        );
      }
      await _load();
    } catch (e) {
      if (!mounted || !_sameActor) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写真を追加できませんでした: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDeleteItem(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('写真を削除しますか？'),
        content: const Text('この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (!mounted || !_sameActor || confirmed != true) return;
    try {
      await widget.repository.deleteItem(item);
      await _load();
    } catch (e) {
      if (!mounted || !_sameActor) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写真を削除できませんでした: $e')),
      );
    }
  }

  Future<void> _deleteAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('アルバムを削除しますか？'),
        content: const Text('アルバム内の写真もすべて削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (!mounted || !_sameActor || confirmed != true) return;
    try {
      await widget.repository.deleteAlbum(_albumId);
      if (!mounted || !_sameActor) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted || !_sameActor) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('アルバムを削除できませんでした: $e')),
      );
    }
  }
}
