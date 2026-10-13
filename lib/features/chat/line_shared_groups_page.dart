import 'package:flutter/material.dart';

import '../../international/language_controller.dart';

import 'line_joined_groups_page.dart';
import 'line_shared_groups_repository.dart';

/// One canonical group is opened from either surface; messages are never copied.
class LineSharedGroupsPage extends StatefulWidget {
  const LineSharedGroupsPage({
    super.key,
    required this.onOpenGroup,
    this.repository,
  });
  final Future<void> Function(String groupId) onOpenGroup;
  final LineSharedGroupsRepository? repository;
  @override
  State<LineSharedGroupsPage> createState() => _LineSharedGroupsPageState();
}

class _LineSharedGroupsPageState extends State<LineSharedGroupsPage> {
  late final _repository =
      widget.repository ?? LineSharedGroupsRepository.maybeCreate();
  List<Map<String, dynamic>> _groups = const [];
  bool _busy = false;
  String? _error;
  String? _displayedActor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = _repository;
      if (repository == null) throw StateError('Login required');
      final actor = repository.actor;
      final rows = await repository.groups();
      if (mounted && repository.actor == actor) {
        setState(() {
          _groups = rows;
          _displayedActor = actor;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _groups = const [];
          _error = 'グループを読み込めませんでした。再読み込みしてください。';
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
          title: Text(SkoLanguageController.tr('LINEグループから作成')),
          content: TextField(
            controller: controller,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: SkoLanguageController.tr('グループ名'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(SkoLanguageController.tr('戻る')),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: Text(SkoLanguageController.tr('作成')),
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
      if (mounted && repository.actor == actor) await widget.onOpenGroup(id);
    } catch (_) {
      if (mounted) setState(() => _error = '作成できませんでした。連携先と権限を確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(SkoLanguageController.tr('LINEグループのチャット')),
      actions: [
        IconButton(
          tooltip: SkoLanguageController.tr('使い方'),
          icon: const Icon(Icons.help_outline),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(SkoLanguageController.tr('LINEグループのチャット')),
              content: Text(
                SkoLanguageController.tr(
                  'LINE側で作ると1つ、SKO側で作ると同じトークを両入口に表示します。写真はグループ設定で変更できます。',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(SkoLanguageController.tr('閉じる')),
                ),
              ],
            ),
          ),
        ),
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
          label: Text(SkoLanguageController.tr('LINEグループから作成')),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(SkoLanguageController.tr(_error!)),
          ),
        for (final group in _groups)
          Card(
            child: ListTile(
              title: Text(
                group['name'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                if (_repository?.actor != _displayedActor) {
                  _load();
                  return;
                }
                widget.onOpenGroup(group['group_id'].toString());
              },
            ),
          ),
      ],
    ),
  );
}
