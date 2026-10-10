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
  bool _canManage = false;
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
      final values = await Future.wait([
        repository.loadAll(),
        repository.canManageCertificates(),
      ]);
      final data = values[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _canManage = values[1] as bool;
        _masters = List<Map<String, dynamic>>.from(data['masters'] as List);
        _workers = List<Map<String, dynamic>>.from(data['workers'] as List);
        _qualifications = List<Map<String, dynamic>>.from(
          data['qualifications'] as List,
        );
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
    final filtered = _qualifications
        .where((row) {
          final master =
              masterById[row['qualification_master_id']?.toString() ?? ''];
          final worker = workerById[row['worker_id']?.toString() ?? ''];
          if (needle.isEmpty) return true;
          final haystack = [
            master?['name'],
            worker?['name'],
            row['certificate_number'],
          ].whereType<Object>().join(' ').toLowerCase();
          return haystack.contains(needle);
        })
        .toList(growable: false);

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
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = filtered[index];
                        final master =
                            masterById[row['qualification_master_id']
                                    ?.toString() ??
                                ''];
                        final worker =
                            workerById[row['worker_id']?.toString() ?? ''];
                        final attachment =
                            row['attachment_path']?.toString() ?? '';
                        final backAttachment =
                            row['attachment_back_path']?.toString() ?? '';
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
                                attachment.isEmpty ? '表面未登録' : '表面登録済み',
                                backAttachment.isEmpty ? '裏面なし' : '裏面登録済み',
                                if (QualificationCertificateRepository.extraPaths(
                                  row,
                                ).isNotEmpty)
                                  '追加${QualificationCertificateRepository.extraPaths(row).length}枚',
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
    final front = row['attachment_path']?.toString() ?? '';
    final back = row['attachment_back_path']?.toString() ?? '';

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
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(workerName),
                if ((row['certificate_number']?.toString() ?? '')
                    .isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('証明書番号: ${row['certificate_number']}'),
                ],
                if ((row['expires_at']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('有効期限: ${row['expires_at']}'),
                ],
                const SizedBox(height: 18),
                _sideSection(
                  title: '表面',
                  path: front,
                  repository: repository,
                  onCamera: _canManage
                      ? () {
                          Navigator.pop(sheetContext);
                          _pickAndUpload(row, ImageSource.camera, back: false);
                        }
                      : null,
                  onGallery: _canManage
                      ? () {
                          Navigator.pop(sheetContext);
                          _pickAndUpload(row, ImageSource.gallery, back: false);
                        }
                      : null,
                  onRemove: _canManage && front.isNotEmpty
                      ? () {
                          Navigator.pop(sheetContext);
                          _remove(row, back: false);
                        }
                      : null,
                ),
                const SizedBox(height: 18),
                _sideSection(
                  title: '裏面（ない場合は登録不要）',
                  path: back,
                  repository: repository,
                  onCamera: _canManage
                      ? () {
                          Navigator.pop(sheetContext);
                          _pickAndUpload(row, ImageSource.camera, back: true);
                        }
                      : null,
                  onGallery: _canManage
                      ? () {
                          Navigator.pop(sheetContext);
                          _pickAndUpload(row, ImageSource.gallery, back: true);
                        }
                      : null,
                  onRemove: _canManage && back.isNotEmpty
                      ? () {
                          Navigator.pop(sheetContext);
                          _remove(row, back: true);
                        }
                      : null,
                ),
                for (final path
                    in QualificationCertificateRepository.extraPaths(row)) ...[
                  const SizedBox(height: 18),
                  _sideSection(
                    title:
                        '追加写真 ${QualificationCertificateRepository.extraPaths(row).indexOf(path) + 3}',
                    path: path,
                    repository: repository,
                    onCamera: _canManage
                        ? () {
                            Navigator.pop(sheetContext);
                            _uploadExtra(
                              row,
                              ImageSource.camera,
                              replacingPath: path,
                            );
                          }
                        : null,
                    onGallery: _canManage
                        ? () {
                            Navigator.pop(sheetContext);
                            _uploadExtra(
                              row,
                              ImageSource.gallery,
                              replacingPath: path,
                            );
                          }
                        : null,
                    onRemove: _canManage
                        ? () {
                            Navigator.pop(sheetContext);
                            _removeExtra(row, path);
                          }
                        : null,
                  ),
                ],
                if (_canManage) ...[
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _uploadExtra(row, ImageSource.gallery, multiple: true);
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('追加写真を選ぶ（複数可）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _uploadExtra(row, ImageSource.camera);
                    },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('追加写真を撮影'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideSection({
    required String title,
    required String path,
    required QualificationCertificateRepository repository,
    required VoidCallback? onCamera,
    required VoidCallback? onGallery,
    required VoidCallback? onRemove,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (path.isNotEmpty)
              FutureBuilder<String>(
                future: repository.createSignedUrl(path),
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
                      child: Text('資格証画像を表示できませんでした。'),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      snapshot.data!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('資格証画像を表示できませんでした。'),
                      ),
                    ),
                  );
                },
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('資格証写真はまだ登録されていません。'),
              ),
            if (_canManage) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(path.isEmpty ? 'カメラで撮影' : '撮り直す'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(path.isEmpty ? '写真から選ぶ' : '写真から差し替える'),
              ),
            ],
            if (onRemove != null)
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('この面の画像を削除'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadExtra(
    Map<String, dynamic> row,
    ImageSource source, {
    String? replacingPath,
    bool multiple = false,
  }) async {
    final repository = _repository;
    if (repository == null || _busyId != null) return;
    final files = multiple
        ? await _picker.pickMultiImage(imageQuality: 88, maxWidth: 2400)
        : [if (await _pickExtra(source) case final XFile file) file];
    if (files.isEmpty || !mounted) return;
    setState(() => _busyId = row['id'].toString());
    try {
      for (final file in files) {
        final updated = await repository.uploadExtraCertificate(
          qualificationId: row['id'].toString(),
          workerId: row['worker_id'].toString(),
          bytes: await file.readAsBytes(),
          originalFilename: file.name,
          replacingPath: replacingPath,
        );
        if (!mounted) return;
        _replaceRow(updated);
      }
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('追加写真を保存しました')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('追加写真の保存を確認できません。再読み込みしてください: $error')),
        );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<XFile?> _pickExtra(ImageSource source) =>
      _picker.pickImage(source: source, imageQuality: 88, maxWidth: 2400);

  Future<void> _removeExtra(Map<String, dynamic> row, String path) async {
    final repository = _repository;
    if (repository == null || _busyId != null) return;
    setState(() => _busyId = row['id'].toString());
    try {
      final updated = await repository.removeExtraCertificate(
        qualificationId: row['id'].toString(),
        storagePath: path,
      );
      if (mounted) _replaceRow(updated);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('写真を削除できませんでした: $error')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _pickAndUpload(
    Map<String, dynamic> row,
    ImageSource source, {
    required bool back,
  }) async {
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
      final updated = back
          ? await repository.uploadCertificateBack(
              qualificationId: id,
              workerId: workerId,
              bytes: await picked.readAsBytes(),
              originalFilename: picked.name,
            )
          : await repository.uploadCertificate(
              qualificationId: id,
              workerId: workerId,
              bytes: await picked.readAsBytes(),
              originalFilename: picked.name,
            );
      if (!mounted) return;
      _replaceRow(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(back ? '資格証の裏面を保存しました' : '資格証の表面を保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('資格証画像を保存できませんでした: $error')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(Map<String, dynamic> row, {required bool back}) async {
    final repository = _repository;
    if (repository == null) return;
    final id = row['id']?.toString();
    final path = row[back ? 'attachment_back_path' : 'attachment_path']
        ?.toString();
    if (id == null || path == null || path.isEmpty) return;

    if (mounted) setState(() => _busyId = id);
    try {
      final updated = back
          ? await repository.removeCertificateBack(
              qualificationId: id,
              storagePath: path,
            )
          : await repository.removeCertificate(
              qualificationId: id,
              storagePath: path,
            );
      if (!mounted) return;
      _replaceRow(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(back ? '資格証の裏面を削除しました' : '資格証の表面を削除しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('資格証画像を削除できませんでした: $error')));
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
