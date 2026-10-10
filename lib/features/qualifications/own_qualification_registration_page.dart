import 'package:flutter/material.dart';

import 'qualification_cloud_repository.dart';

class OwnQualificationRegistrationPage extends StatefulWidget {
  const OwnQualificationRegistrationPage({super.key});

  @override
  State<OwnQualificationRegistrationPage> createState() =>
      _OwnQualificationRegistrationPageState();
}

class _OwnQualificationRegistrationPageState
    extends State<OwnQualificationRegistrationPage> {
  final _repository = QualificationCloudRepository.maybeCreate();
  final _searchController = TextEditingController();

  Map<String, dynamic>? _worker;
  List<Map<String, dynamic>> _masters = const [];
  List<Map<String, dynamic>> _qualifications = const [];
  String _query = '';
  bool _loading = true;
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
    final actor = repository.currentUserId;
    try {
      final data = await repository.loadOwnQualificationWorkspace();
      if (!mounted || actor == null || actor != repository.currentUserId)
        return;
      setState(() {
        _worker = Map<String, dynamic>.from(data['worker'] as Map);
        _masters = List<Map<String, dynamic>>.from(data['masters'] as List);
        _qualifications = List<Map<String, dynamic>>.from(
          data['qualifications'] as List,
        );
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

  Future<void> _addQualification() async {
    final repository = _repository;
    if (repository == null || _masters.isEmpty) return;

    final filteredMasters = _masters
        .where((row) {
          final needle = _query.trim().toLowerCase();
          if (needle.isEmpty) return true;
          return [
            row['name'],
            row['category'],
            row['issuer'],
          ].whereType<Object>().join(' ').toLowerCase().contains(needle);
        })
        .toList(growable: false);
    if (filteredMasters.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('該当する資格種類がありません')));
      return;
    }

    var masterId = filteredMasters.first['id']?.toString();
    final certificateController = TextEditingController();
    final issuerController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? issuedAt;
    DateTime? expiresAt;

    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('自分の資格を登録'),
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
                  initialValue: masterId,
                  decoration: const InputDecoration(labelText: '資格種類'),
                  items: [
                    for (final row in filteredMasters)
                      DropdownMenuItem(
                        value: row['id']?.toString(),
                        child: Text(row['name']?.toString() ?? '資格'),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => masterId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: certificateController,
                  decoration: const InputDecoration(labelText: '証明書番号'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: issuerController,
                  decoration: const InputDecoration(labelText: '発行元'),
                ),
                const SizedBox(height: 8),
                _DateTile(
                  label: '取得日',
                  value: issuedAt,
                  onTap: () async {
                    final picked = await _pickDate(dialogContext, issuedAt);
                    if (picked != null) {
                      setDialogState(() => issuedAt = picked);
                    }
                  },
                ),
                _DateTile(
                  label: '有効期限',
                  value: expiresAt,
                  onTap: () async {
                    final picked = await _pickDate(dialogContext, expiresAt);
                    if (picked != null) {
                      setDialogState(() => expiresAt = picked);
                    }
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '資格の情報は登録できます。本人による資格証写真の追加・差し替えは現在停止中です。登録済み写真は資格一覧から確認できます。',
                  ),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: '備考'),
                  maxLines: 2,
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
              onPressed: masterId == null
                  ? null
                  : () => Navigator.pop(dialogContext, {
                      'masterId': masterId,
                      'certificateNumber': certificateController.text.trim(),
                      'issuer': issuerController.text.trim(),
                      'issuedAt': issuedAt,
                      'expiresAt': expiresAt,
                      'notes': notesController.text.trim(),
                    }),
              child: const Text('登録'),
            ),
          ],
        ),
      ),
    );

    certificateController.dispose();
    issuerController.dispose();
    notesController.dispose();
    if (draft == null) return;

    try {
      await repository.insertOwnQualification(
        qualificationMasterId: draft['masterId'] as String,
        certificateNumber: draft['certificateNumber'] as String,
        issuer: draft['issuer'] as String,
        issuedAt: draft['issuedAt'] as DateTime?,
        expiresAt: draft['expiresAt'] as DateTime?,
        notes: draft['notes'] as String,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('自分の資格を登録しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('資格を登録できませんでした: $error')));
    }
  }

  Future<void> _previewPhotos(Map<String, dynamic> row, String title) async {
    final repository = _repository;
    if (repository == null) return;
    final photos = QualificationCloudRepository.ownPhotoAttachments(row);
    if (photos.isEmpty) return;
    final actor = repository.currentUserId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: photos.length,
            itemBuilder: (context, index) => Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      photos[index].label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<String>(
                      future: repository.createOwnQualificationPhotoUrl(
                        qualificationId: row['id'].toString(),
                        storagePath: photos[index].path,
                      ),
                      builder: (context, snapshot) {
                        if (actor == null ||
                            actor != repository.currentUserId) {
                          return const Text('ログイン状態が変わりました。画面を開き直してください。');
                        }
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return const Text(
                            '資格証写真を表示できませんでした。資格一覧へ戻って再度開いてください。',
                          );
                        }
                        return InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          child: Image.network(
                            snapshot.data!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Text('資格証写真を表示できませんでした。'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<DateTime?> _pickDate(BuildContext context, DateTime? value) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 30),
    );
  }

  @override
  Widget build(BuildContext context) {
    final masterById = {
      for (final row in _masters) row['id']?.toString() ?? '': row,
    };
    final needle = _query.trim().toLowerCase();
    final qualifications = _qualifications
        .where((row) {
          if (needle.isEmpty) return true;
          final master =
              masterById[row['qualification_master_id']?.toString() ?? ''];
          return [
            master?['name'],
            master?['category'],
            master?['issuer'],
            row['certificate_number'],
            row['issuer'],
          ].whereType<Object>().join(' ').toLowerCase().contains(needle);
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '資格登録',
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
        onPressed: _loading || _masters.isEmpty ? null : _addQualification,
        icon: const Icon(Icons.add_card_outlined),
        label: const Text('資格登録'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _OwnQualificationError(message: _error!, onRetry: _load)
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
                      subtitle: const Text('ログイン中の本人の資格だけを表示します'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '資格種類・証明書番号で検索',
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  Expanded(
                    child: qualifications.isEmpty
                        ? const Center(child: Text('登録済みの資格はありません'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                            itemCount: qualifications.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final row = qualifications[index];
                              final master =
                                  masterById[row['qualification_master_id']
                                          ?.toString() ??
                                      ''];
                              final photos =
                                  QualificationCloudRepository.ownPhotoAttachments(
                                    row,
                                  );
                              return Card(
                                child: ListTile(
                                  onTap: photos.isEmpty
                                      ? null
                                      : () => _previewPhotos(
                                          row,
                                          master?['name']?.toString() ??
                                              '資格証写真',
                                        ),
                                  trailing: photos.isEmpty
                                      ? null
                                      : const Icon(
                                          Icons.photo_library_outlined,
                                        ),
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.badge_outlined),
                                  ),
                                  title: Text(
                                    master?['name']?.toString() ?? '資格',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (photos.isNotEmpty)
                                        '登録写真 ${photos.length}枚（タップして確認）',
                                      if ((row['certificate_number']
                                                  ?.toString() ??
                                              '')
                                          .isNotEmpty)
                                        '証明書 ${row['certificate_number']}',
                                      if ((row['expires_at']?.toString() ?? '')
                                          .isNotEmpty)
                                        '期限 ${row['expires_at']}',
                                      if ((row['issuer']?.toString() ?? '')
                                          .isNotEmpty)
                                        row['issuer'].toString(),
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

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '未設定'
        : '${value!.year}/${value!.month.toString().padLeft(2, '0')}/${value!.day.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(text),
      trailing: const Icon(Icons.calendar_month_outlined),
      onTap: onTap,
    );
  }
}

class _OwnQualificationError extends StatelessWidget {
  const _OwnQualificationError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
