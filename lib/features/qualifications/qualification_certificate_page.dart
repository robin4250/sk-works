import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'qualification_certificate_repository.dart';

class QualificationCertificatePage extends StatefulWidget {
  const QualificationCertificatePage({super.key});

  @override
  State<QualificationCertificatePage> createState() =>
      _QualificationCertificatePageState();
}

class _QualificationCertificatePageState
    extends State<QualificationCertificatePage> {
  final _repository = QualificationCertificateRepository.maybeCreate();
  final _picker = ImagePicker();
  final _queryController = TextEditingController();

  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _qualifications = [];
  bool _loading = true;
  String _query = '';
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Supabase接続が利用できません。';
      });
      return;
    }

    try {
      final data = await repository.loadAll();
      if (!mounted) return;
      setState(() {
        _masters = List<Map<String, dynamic>>.from(data['masters'] as List);
        _workers = List<Map<String, dynamic>>.from(data['workers'] as List);
        _qualifications =
            List<Map<String, dynamic>>.from(data['qualifications'] as List);
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

  @override
  Widget build(BuildContext context) {
    final masterById = {
      for (final row in _masters) row['id']?.toString() ?? '': row,
    };
    final workerById = {
      for (final row in _workers) row['id']?.toString() ?? '': row,
    };
    final needle = _query.trim().toLowerCase();
    final filtered = _qualifications.where((row) {
      final master = masterById[row['qualification_master_id']?.toString() ?? ''];
      final worker = workerById[row['worker_id']?.toString() ?? ''];
      if (needle.isEmpty) return true;
      final haystack = [
        master?['name'],
        worker?['name'],
        row['certificate_number'],
      ].whereType<Object>().join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('資格証写真'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _queryController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '資格名・保有者・証明書番号で検索',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : filtered.isEmpty
                          ? const _EmptyState()
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final row = filtered[index];
                                final master = masterById[
                                    row['qualification_master_id']?.toString() ?? ''];
                                final worker = workerById[
                                    row['worker_id']?.toString() ?? ''];
                                final attachment =
                                    row['attachment_path']?.toString() ?? '';
                                final busy = _busyId == row['id']?.toString();
                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      child: busy
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              attachment.isEmpty
                                                  ? Icons.document_scanner_outlined
                                                  : Icons.verified_outlined,
                                            ),
                                    ),
                                    title: Text(
                                      master?['name']?.toString() ?? '資格',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                        worker?['name']?.toString() ?? '保有者不明',
                                        attachment.isEmpty ? '写真未登録' : '写真登録済み',
                                      ].join(' / '),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    enabled: !busy,
                                    onTap: busy
                                        ? null
                                        : () => _showActions(
                                              row,
                                              master?['name']?.toString() ?? '資格',
                                              worker?['name']?.toString() ?? '保有者不明',
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

  Future<void> _showActions(
    Map<String, dynamic> row,
    String qualificationName,
    String workerName,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    final attachment = row['attachment_path']?.toString() ?? '';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  qualificationName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(workerName),
                if ((row['certificate_number']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('証明書番号: ${row['certificate_number']}'),
                ],
                if ((row['expires_at']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('有効期限: ${row['expires_at']}'),
                ],
                const SizedBox(height: 16),
                if (attachment.isNotEmpty) ...[
                  FutureBuilder<String>(
                    future: repository.createSignedUrl(attachment),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('資格証写真を表示できませんでした。'),
                        );
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('資格証写真を表示できませんでした。'),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _pickAndUpload(row, ImageSource.camera);
                    },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('撮り直す'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _pickAndUpload(row, ImageSource.gallery);
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('写真から差し替える'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _remove(row);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('資格証写真を削除'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _pickAndUpload(row, ImageSource.camera);
                    },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('カメラで撮影'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _pickAndUpload(row, ImageSource.gallery);
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('写真から選ぶ'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(
    Map<String, dynamic> row,
    ImageSource source,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    final id = row['id']?.toString();
    final workerId = row['worker_id']?.toString();
    if (id == null || workerId == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2400,
    );
    if (picked == null) return;

    if (mounted) setState(() => _busyId = id);
    try {
      final updated = await repository.uploadCertificate(
        qualificationId: id,
        workerId: workerId,
        bytes: await picked.readAsBytes(),
        originalFilename: picked.name,
      );
      if (!mounted) return;
      _replaceRow(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資格証写真を保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('資格証写真を保存できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final repository = _repository;
    if (repository == null) return;
    final id = row['id']?.toString();
    final path = row['attachment_path']?.toString();
    if (id == null || path == null || path.isEmpty) return;

    if (mounted) setState(() => _busyId = id);
    try {
      final updated = await repository.removeCertificate(
        qualificationId: id,
        storagePath: path,
      );
      if (!mounted) return;
      _replaceRow(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資格証写真を削除しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('資格証写真を削除できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _replaceRow(Map<String, dynamic> updated) {
    final id = updated['id']?.toString();
    if (id == null) return;
    setState(() {
      final index = _qualifications.indexWhere(
        (row) => row['id']?.toString() == id,
      );
      if (index >= 0) _qualifications[index] = updated;
    });
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '登録済みの資格がありません。\n先に「資格管理」で資格を登録してください。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('再試行')),
          ],
        ),
      ),
    );
  }
}
