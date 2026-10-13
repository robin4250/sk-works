import 'package:flutter/material.dart';

import 'people_cloud_repository.dart';

class WorkerPersonnelApproverSettingsPage extends StatefulWidget {
  const WorkerPersonnelApproverSettingsPage({super.key});

  @override
  State<WorkerPersonnelApproverSettingsPage> createState() =>
      _WorkerPersonnelApproverSettingsPageState();
}

class _WorkerPersonnelApproverSettingsPageState
    extends State<WorkerPersonnelApproverSettingsPage> {
  final _repository = PeopleCloudRepository.maybeCreate();
  List<Map<String, dynamic>> _candidates = const [];
  final List<String> _selected = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '承認者設定を利用できません。';
      });
      return;
    }
    try {
      final value = await repository.loadPersonnelApproverSettings();
      final selectedRaw = value['selected'] is List
          ? value['selected'] as List<dynamic>
          : const <dynamic>[];
      final candidatesRaw = value['candidates'] is List
          ? value['candidates'] as List<dynamic>
          : const <dynamic>[];
      final selected = <String>[];
      for (final raw in selectedRaw) {
        if (raw is! Map) continue;
        final id = raw['user_id']?.toString() ?? '';
        if (id.isNotEmpty) selected.add(id);
      }
      final candidates = <Map<String, dynamic>>[
        for (final raw in candidatesRaw)
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(selected.take(3));
        _candidates = candidates;
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

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || _saving) return;
    if (_selected.isEmpty || _selected.length > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('承認者は1〜3名で選択してください')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await repository.savePersonnelApprovers(_selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('社員個人情報の承認者を${_selected.length}名で保存しました')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '社員個人情報 承認者設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    children: [
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            '社員個人情報の変更を承認する人を1〜3名登録します。'
                            '登録人数がその申請に必要な承認人数になります。'
                            '申請者本人は自分の申請を承認できません。',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final candidate in _candidates)
                        CheckboxListTile(
                          value: _selected.contains(
                            candidate['user_id']?.toString() ?? '',
                          ),
                          title: Text(
                            candidate['name']?.toString() ?? 'ユーザー',
                          ),
                          subtitle: Text(
                            _roleLabel(candidate['role']?.toString() ?? ''),
                          ),
                          onChanged: _saving
                              ? null
                              : (checked) {
                                  final id =
                                      candidate['user_id']?.toString() ?? '';
                                  if (id.isEmpty) return;
                                  if (checked == true && _selected.length >= 3) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('承認者は最大3名です'),
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() {
                                    if (checked == true) {
                                      if (!_selected.contains(id)) {
                                        _selected.add(id);
                                      }
                                    } else {
                                      _selected.remove(id);
                                    }
                                  });
                                },
                        ),
                      const SizedBox(height: 12),
                      Text(
                        '現在 ${_selected.length}/3 名選択',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? '保存中…' : '承認者を保存'),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _roleLabel(String role) => switch (role) {
        'owner' => 'オーナー',
        'admin' => '管理者',
        'manager' => 'サブ管理者',
        _ => role,
      };
}
