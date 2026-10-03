import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'worker_document_repository.dart';

class OwnDocumentRegistrationPage extends StatefulWidget {
  const OwnDocumentRegistrationPage({super.key});

  @override
  State<OwnDocumentRegistrationPage> createState() =>
      _OwnDocumentRegistrationPageState();
}

class _OwnDocumentRegistrationPageState
    extends State<OwnDocumentRegistrationPage> {
  final _repository = WorkerDocumentRepository.maybeCreate();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _requirements = const [];
  List<Map<String, dynamic>> _statuses = const [];
  Map<String, dynamic>? _worker;
  bool _loading = true;
  String? _error;
  String _query = '';

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
        _error = 'クラウド接続を確認できません。';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repository.loadAll();
      final workers = data['workers'] ?? const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _worker = workers.isEmpty ? null : workers.first;
        _requirements =
            data['requirements'] ?? const <Map<String, dynamic>>[];
        _statuses = data['statuses'] ?? const <Map<String, dynamic>>[];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Map<String, dynamic>? _statusFor(String requirementId) {
    for (final row in _statuses) {
      if (row['requirement_id']?.toString() == requirementId) return row;
    }
    return null;
  }

  Future<void> _registerDocument() async {
    final repository = _repository;
    if (repository == null || _requirements.isEmpty) return;

    final needle = _query.trim().toLowerCase();
    final candidates = _requirements.where((row) {
      if (needle.isEmpty) return true;
      return [row['name'], row['scope']]
          .whereType<Object>()
          .join(' ')
          .toLowerCase()
          .contains(needle);
    }).toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('該当する書類種類がありません')),
      );
      return;
    }

    var requirementId = candidates.first['id']?.toString();
    DateTime? expiresAt;
    final notes = TextEditingController();
    var attachPhoto = false;

    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('自分の書類を登録'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '登録者：${_worker?['name'] ?? '本人'}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: requirementId,
                  decoration: const InputDecoration(labelText: '書類種類'),
                  items: [
                    for (final row in candidates)
                      DropdownMenuItem<String>(
                        value: row['id']?.toString(),
                        child: Text(row['name']?.toString() ?? '書類'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => requirementId = value),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('有効期限'),
                  subtitle: Text(
                    expiresAt == null
                        ? '未設定'
                        : '${expiresAt!.year}/${expiresAt!.month.toString().padLeft(2, '0')}/${expiresAt!.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: expiresAt ?? now,
                      firstDate: DateTime(1950),
                      lastDate: DateTime(now.year + 30),
                    );
                    if (picked != null) {
                      setDialogState(() => expiresAt = picked);
                    }
                  },
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: '備考'),
                  maxLines: 2,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('登録後に写真を添付する'),
                  value: attachPhoto,
                  onChanged: (value) =>
                      setDialogState(() => attachPhoto = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: requirementId == null
                  ? null
                  : () => Navigator.pop(dialogContext, {
                        'requirementId': requirementId,
                        'expiresAt': expiresAt,
                        'notes': notes.text.trim(),
                        'attachPhoto': attachPhoto,
                      }),
              child: const Text('登録'),
            ),
          ],
        ),
      ),
    );
    notes.dispose();
    if (draft == null) return;

    final requirement = draft['requirementId'] as String;
    try {
      await repository.updateOwnStatus(
        requirementId: requirement,
        expiresAt: draft['expiresAt'] as DateTime?,
        notes: draft['notes'] as String,
      );
      await _load();
      if (!mounted) return;

      if (draft['attachPhoto'] == true) {
        final status = _statusFor(requirement);
        if (status != null) {
          final source = await showModalBottomSheet<ImageSource>(
            context: context,
            builder: (sheetContext) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('カメラで撮影'),
                    onTap: () =>
                        Navigator.pop(sheetContext, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('写真から選ぶ'),
                    onTap: () =>
                        Navigator.pop(sheetContext, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          );
          if (source != null) {
            final picked = await _picker.pickImage(
              source: source,
              imageQuality: 88,
              maxWidth: 2400,
            );
            if (picked != null) {
              await repository.uploadOwnAttachment(
                statusId: status['id'].toString(),
                requirementId: requirement,
                bytes: await picked.readAsBytes(),
                originalFilename: picked.name,
              );
              await _load();
            }
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自分の書類を登録しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('書類を登録できませんでした: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final requirements = _requirements.where((row) {
      if (needle.isEmpty) return true;
      return [row['name'], row['scope']]
          .whereType<Object>()
          .join(' ')
          .toLowerCase()
          .contains(needle);
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '書類登録',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _requirements.isEmpty ? null : _registerDocument,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('書類登録'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : Column(
                    children: [
                      Card(
                        margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(
                            _worker?['name']?.toString() ?? '本人',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text('ログイン中の本人の書類だけを表示します'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '書類種類で検索',
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                          itemCount: requirements.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final requirement = requirements[index];
                            final id = requirement['id']?.toString() ?? '';
                            final status = _statusFor(id);
                            final label = status?['status']?.toString() ==
                                        'verified'
                                    ? '確認済み'
                                    : status?['status']?.toString() ==
                                            'submitted'
                                        ? '提出済み'
                                        : '未登録';
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.description_outlined),
                                ),
                                title: Text(
                                  requirement['name']?.toString() ?? '書類',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    label,
                                    if ((status?['expires_at']?.toString() ?? '')
                                        .isNotEmpty)
                                      '期限 ${status!['expires_at']}',
                                    if ((status?['attachment_path']?.toString() ??
                                            '')
                                        .isNotEmpty)
                                      '画像あり',
                                  ].join(' / '),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
