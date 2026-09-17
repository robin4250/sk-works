import 'package:flutter/material.dart';

import 'notes_cloud_repository.dart';

class NotesCloudPage extends StatefulWidget {
  const NotesCloudPage({super.key});

  @override
  State<NotesCloudPage> createState() => _NotesCloudPageState();
}

class _NotesCloudPageState extends State<NotesCloudPage> {
  final _repository = NotesCloudRepository.maybeCreate();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _notes = [];
  String? _selectedGroupId;
  bool _loading = true;
  bool _loadingNotes = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
      });
      if (_selectedGroupId != null) await _loadNotes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadNotes() async {
    final groupId = _selectedGroupId;
    if (_repository == null || groupId == null) return;
    setState(() {
      _loadingNotes = true;
      _error = null;
    });
    try {
      final notes = await _repository.loadNotes(groupId);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loadingNotes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingNotes = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _notes.where((note) {
      if (query.isEmpty) return true;
      final title = (note['title'] ?? '').toString().toLowerCase();
      final body = (note['body'] ?? '').toString().toLowerCase();
      return title.contains(query) || body.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('ノート')),
      floatingActionButton: _selectedGroupId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addNote,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('新規ノート'),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadNotes,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    if (_groups.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('ノートを作成するには、先に通信グループを作成してください。'),
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
                          await _loadNotes();
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'ノートを検索',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
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
                      if (_loadingNotes)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (filtered.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('ノートはまだありません。'),
                          ),
                        )
                      else
                        for (final note in filtered)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(
                              child: ListTile(
                                leading: Icon(
                                  note['is_pinned'] == true
                                      ? Icons.push_pin
                                      : Icons.sticky_note_2_outlined,
                                ),
                                title: Text(
                                  note['title'].toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: (note['body'] ?? '').toString().trim().isEmpty
                                    ? null
                                    : Text(
                                        note['body'].toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showNote(note),
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

  Future<void> _addNote() async {
    final result = await Navigator.of(context).push<_NoteDraft>(
      MaterialPageRoute(builder: (_) => const _NoteFormPage()),
    );
    if (result == null || _repository == null || _selectedGroupId == null) return;

    try {
      await _repository.insertNote(
        groupId: _selectedGroupId,
        title: result.title,
        body: result.body,
        isPinned: result.isPinned,
      );
      await _loadNotes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ノートを保存できませんでした: $e')),
      );
    }
  }

  void _showNote(Map<String, dynamic> note) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note['title'].toString(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: note['is_pinned'] == true ? 'ピンを外す' : 'ピン留め',
                    onPressed: () async {
                      final next = note['is_pinned'] != true;
                      Navigator.pop(sheetContext);
                      await _repository?.setPinned(note['id'] as String, next);
                      await _loadNotes();
                    },
                    icon: Icon(
                      note['is_pinned'] == true
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText((note['body'] ?? '').toString().trim().isEmpty
                  ? '本文なし'
                  : note['body'].toString()),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _repository?.deleteNote(note['id'] as String);
                  await _loadNotes();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('削除'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteDraft {
  const _NoteDraft({required this.title, this.body, required this.isPinned});

  final String title;
  final String? body;
  final bool isPinned;
}

class _NoteFormPage extends StatefulWidget {
  const _NoteFormPage();

  @override
  State<_NoteFormPage> createState() => _NoteFormPageState();
}

class _NoteFormPageState extends State<_NoteFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _isPinned = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新規ノート')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'タイトル'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'タイトルを入力してください'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _body,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: '本文',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('重要ノートとしてピン留め'),
                value: _isPinned,
                onChanged: (value) => setState(() => _isPinned = value),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存する'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _NoteDraft(
        title: _title.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        isPinned: _isPinned,
      ),
    );
  }
}
