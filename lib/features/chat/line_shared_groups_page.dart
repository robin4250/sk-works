import 'dart:async';

import 'package:flutter/material.dart';
import '../../international/language_controller.dart';
import 'chat_cloud_repository.dart';
import 'chat_group_delete_confirmation.dart';

import 'line_joined_groups_page.dart';
import 'line_shared_groups_repository.dart';

/// One canonical group is opened from either surface; messages are never copied.
class LineSharedGroupsPage extends StatefulWidget {
  const LineSharedGroupsPage({
    super.key,
    required this.onOpenGroup,
    this.repository,
    this.onOpenSavedTalks,
    this.groupChanges,
  });
  final Future<void> Function(String groupId) onOpenGroup;
  final LineSharedGroupsRepository? repository;
  final Future<void> Function()? onOpenSavedTalks;
  final Stream<String>? groupChanges;
  @override
  State<LineSharedGroupsPage> createState() => _LineSharedGroupsPageState();
}

class _LineSharedGroupsPageState extends State<LineSharedGroupsPage> {
  late final _repository =
      widget.repository ?? LineSharedGroupsRepository.maybeCreate();
  List<Map<String, dynamic>> _groups = const [];
  bool _busy = false;
  int _loadGeneration = 0;
  final Map<String, int> _previewGenerations = {};
  StreamSubscription<String>? _changes;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
    final changes = widget.groupChanges ??
      (widget.repository == null ? _repository?.watchChanges() : null);
    _changes = changes?.listen(_refreshPreview);
  }

  @override
  void dispose() {
    _loadGeneration++;
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _refreshPreview(String id) async {
    final repository = _repository;
    final actor = repository?.actor;
    final scope = _loadGeneration;
    if (repository == null || actor == null ||
        !_groups.any((row) => row['group_id'] == id)) {
      return;
    }
    final generation = (_previewGenerations[id] ?? 0) + 1;
    _previewGenerations[id] = generation;
    try {
      final ChatConversationSummary? preview = await repository.preview(id);
      if (!mounted || repository.actor != actor || _loadGeneration != scope ||
          _previewGenerations[id] != generation) {
        return;
      }
      if (preview == null) {
        await _load(); // A removed group must disappear after returning from its chat.
        return;
      }
      setState(() {
        _groups = [for (final group in _groups)
          if (group['group_id'] == id) {
            ...group, 'last_message_body': preview.body, 'last_message_at': preview.sentAt,
          } else group];
      });
    } catch (_) { /* Preserve the last successful preview on transient failure. */ }
  }

  Future<void> _openGroup(String id) async {
    await widget.onOpenGroup(id);
    if (mounted) await _refreshPreview(id);
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final actor = _repository?.actor;
    try {
      final repository = _repository;
      if (repository == null) throw StateError('Login required');
      final rows = await repository.groups();
      if (mounted && generation == _loadGeneration && repository.actor == actor) {
        setState(() {
          _groups = rows;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _groups = const [];
          _error = _repository?.actor == null
              ? 'SKOへのログインが必要です。'
              : 'グループを読み込めませんでした。再読み込みしてください。';
        });
      }
    }
  }

  Future<void> _create() async {
    if (_busy || _repository == null) return;
    setState(() => _busy = true);
    try {
      final repository = _repository;
      final actor = repository.actor;
      final company = await repository.company();
      if (!mounted || repository.actor != actor) return;
      final source = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => LineJoinedGroupsPage(
            selectOnly: true,
            newGroupCompanyId: company,
          ),
        ),
      );
      if (!mounted || source == null || repository.actor != actor) return;
      final controller = TextEditingController(
        text: source['display_name']?.toString() ?? '',
      );
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('LINEグループから作成'),
          content: TextField(
            controller: controller,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'グループ名'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('作成'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (!mounted || name == null || repository.actor != actor) return;
      final id = await repository.create(
        directoryId: source['id'].toString(),
        name: name,
        companyId: company,
        origin: 'line',
      );
      if (!mounted || repository.actor != actor) return;
      await _load();
      if (mounted && repository.actor == actor) await _openGroup(id);
    } catch (_) {
      if (mounted) setState(() => _error = '作成できませんでした。連携先と権限を確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteGroup(Map<String, dynamic> group) async {
    final repository = _repository;
    final actor = repository?.actor;
    final id = group['group_id']?.toString();
    if (_busy || repository == null || actor == null || id == null ||
        group['can_delete_group'] != true) {
      return;
    }
    setState(() => _busy = true);
    try {
      final confirmed = await confirmChatGroupDeletion(context,
        name: group['name']?.toString() ?? '', lineLinked: true);
      if (!mounted || !confirmed || repository.actor != actor) return;
      await repository.deleteGroup(id);
      if (mounted && repository.actor == actor) await _load();
    } catch (_) {
      if (mounted && repository.actor == actor) {
        setState(() => _error = '削除結果を確認できませんでした。再読み込みしてグループと権限を確認してください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('LINEグループのチャット'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add),
          label: const Text('LINEグループから作成'),
        ),
        if (widget.onOpenSavedTalks != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : widget.onOpenSavedTalks,
            icon: const Icon(Icons.history),
            label: Text(SkoLanguageController.tr('保存済みトーク')),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_error!),
          ),
        for (final group in _groups)
          Card(
            child: ListTile(
              title: Text(
                group['name'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(group['last_message_body']?.toString() ??
                SkoLanguageController.tr('まだ会話はありません'),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (group['can_delete_group'] == true)
                  IconButton(key: ValueKey('line-delete-group-${group['group_id']}'),
                    tooltip: 'グループを削除', icon: const Icon(Icons.delete_outline),
                    onPressed: _busy ? null : () => _deleteGroup(group)),
                const Icon(Icons.chevron_right),
              ]),
              onTap: () => _openGroup(group['group_id'].toString()),
            ),
          ),
      ],
    ),
  );
}
