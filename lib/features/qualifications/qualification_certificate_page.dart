import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'qualification_certificate_repository.dart';

class QualificationCertificatePage extends StatefulWidget {
  const QualificationCertificatePage({super.key, this.initialQualificationId, this.repository});
  @visibleForTesting
  final QualificationCertificateRepository? repository;
  final String? initialQualificationId;

  @override
  State<QualificationCertificatePage> createState() =>
      _QualificationCertificatePageState();
}

class _QualificationCertificatePageState
    extends State<QualificationCertificatePage> {
  late final QualificationCertificateRepository? _repository;
  StreamSubscription<AuthState>? _authSubscription;
  late final String? _actor;
  bool _revoked = false;
  int _generation = 0;
  final _picker = ImagePicker();
  final _queryController = TextEditingController();

  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _qualifications = [];
  bool _loading = true;
  bool _canManage = false;
  bool _extraPhotosAvailable = false;
  String _query = '';
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? QualificationCertificateRepository.maybeCreate();
    _actor = _repository?.currentUserId;
    _revoked = _actor == null;
    _authSubscription = _repository?.authChanges.listen((state) {
      if (state.session?.user.id != _actor) _revoke();
    }, onError: (Object error) => _revoke());
    _load();
  }

  void _revoke() {
    if (!mounted || _revoked) return;
    setState(() {
      _revoked = true;
      _generation++;
      _masters = [];
      _workers = [];
      _qualifications = [];
      _canManage = false;
      _busyId = null;
      _error = null;
      _query = '';
      _queryController.clear();
    });
  }

  bool get _scopeActive => mounted && !_revoked &&
      _actor != null && _repository?.currentUserId == _actor;

  @override
  void dispose() {
    _authSubscription?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final repository = _repository;
    if (_revoked) return;
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
      if (!_scopeActive || generation != _generation) return;
      setState(() {
        _canManage = values[1] as bool;
        _extraPhotosAvailable = data['supports_extra_photos'] == true;
        _masters = List<Map<String, dynamic>>.from(data['masters'] as List);
        _workers = List<Map<String, dynamic>>.from(data['workers'] as List);
        _qualifications = List<Map<String, dynamic>>.from(
          data['qualifications'] as List,
        );
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!_scopeActive || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_revoked) {
      return Scaffold(
        appBar: AppBar(title: const Text('資格証写真')),
        body: const Center(child: Text('ログイン状態が変わりました。画面を閉じて開き直してください。')),
      );
    }
    final masterById = {
      for (final row in _masters) row['id']?.toString() ?? '': row,
    };
    final workerById = {
      for (final row in _workers) row['id']?.toString() ?? '': row,
    };
    final needle = _query.trim().toLowerCase();
    final filtered = _qualifications
        .where((row) {
          if (widget.initialQualificationId != null &&
              row['id']?.toString() != widget.initialQualificationId) { return false; }
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
    if (repository == null || !_scopeActive) return;
    final actor = _actor;
    var sheetRevoked = false;
    final front = row['attachment_path']?.toString() ?? '';
    final back = row['attachment_back_path']?.toString() ?? '';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StreamBuilder<AuthState>(
        stream: repository.authChanges,
        builder: (context, snapshot) {
          if (!_scopeActive || repository.currentUserId != actor || snapshot.hasError ||
              (snapshot.hasData && snapshot.data?.session?.user.id != actor)) {
            sheetRevoked = true;
          }
          if (sheetRevoked) {
            return const SafeArea(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('ログイン状態が変わりました。画面を閉じて開き直してください。'),
            ));
          }
          return SafeArea(
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
                if (!_extraPhotosAvailable) ...[
                  const SizedBox(height: 18),
                  const Text('追加写真の保存は準備中です。表面・裏面は引き続き確認できます。'),
                ],
                if (_canManage && _extraPhotosAvailable) ...[
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
          );
        },
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
    if (repository == null || !_scopeActive || !_canManage || _busyId != null || !_extraPhotosAvailable) return;
    final files = multiple
        ? await _picker.pickMultiImage(imageQuality: 88, maxWidth: 2400)
        : [if (await _pickExtra(source) case final XFile file) file];
    if (files.isEmpty || !_scopeActive) return;
    setState(() => _busyId = row['id'].toString());
    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        if (!_scopeActive) return;
        final updated = await repository.uploadExtraCertificate(
          qualificationId: row['id'].toString(),
          workerId: row['worker_id'].toString(),
          bytes: bytes,
          originalFilename: file.name,
          replacingPath: replacingPath,
        );
        if (!_scopeActive) return;
        _replaceRow(updated);
      }
      if (_scopeActive) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('追加写真を保存しました')));
      }
    } catch (error) {
      if (_scopeActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('追加写真の保存を確認できません。再読み込みしてください: $error')),
        );
      }
    } finally {
      if (_scopeActive) setState(() => _busyId = null);
    }
  }

  Future<XFile?> _pickExtra(ImageSource source) =>
      _picker.pickImage(source: source, imageQuality: 88, maxWidth: 2400);

  Future<void> _removeExtra(Map<String, dynamic> row, String path) async {
    final repository = _repository;
    if (repository == null || !_scopeActive || !_canManage || _busyId != null || !_extraPhotosAvailable) return;
    setState(() => _busyId = row['id'].toString());
    try {
      final updated = await repository.removeExtraCertificate(
        qualificationId: row['id'].toString(),
        storagePath: path,
      );
      if (_scopeActive) _replaceRow(updated);
    } catch (error) {
      if (_scopeActive) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('写真を削除できませんでした: $error')));
      }
    } finally {
      if (_scopeActive) setState(() => _busyId = null);
    }
  }

  Future<void> _pickAndUpload(
    Map<String, dynamic> row,
    ImageSource source, {
    required bool back,
  }) async {
    final repository = _repository;
    if (repository == null || !_scopeActive || !_canManage) return;
    final id = row['id']?.toString();
    final workerId = row['worker_id']?.toString();
    if (id == null || workerId == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2400,
    );
    if (picked == null || !_scopeActive) return;

    if (_scopeActive) setState(() => _busyId = id);
    try {
      final bytes = await picked.readAsBytes();
      if (!_scopeActive) return;
      final updated = back
          ? await repository.uploadCertificateBack(
              qualificationId: id,
              workerId: workerId,
              bytes: bytes,
              originalFilename: picked.name,
            )
          : await repository.uploadCertificate(
              qualificationId: id,
              workerId: workerId,
              bytes: bytes,
              originalFilename: picked.name,
            );
      if (!_scopeActive) return;
      _replaceRow(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(back ? '資格証の裏面を保存しました' : '資格証の表面を保存しました')),
      );
    } catch (error) {
      if (!_scopeActive) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('資格証画像を保存できませんでした: $error')));
    } finally {
      if (_scopeActive) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(Map<String, dynamic> row, {required bool back}) async {
    final repository = _repository;
    if (repository == null || !_scopeActive || !_canManage) return;
    final id = row['id']?.toString();
    final path = row[back ? 'attachment_back_path' : 'attachment_path']
        ?.toString();
    if (id == null || path == null || path.isEmpty) return;

    if (_scopeActive) setState(() => _busyId = id);
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
      if (!_scopeActive) return;
      _replaceRow(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(back ? '資格証の裏面を削除しました' : '資格証の表面を削除しました')),
      );
    } catch (error) {
      if (!_scopeActive) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('資格証画像を削除できませんでした: $error')));
    } finally {
      if (_scopeActive) setState(() => _busyId = null);
    }
  }

  void _replaceRow(Map<String, dynamic> updated) {
    if (!_scopeActive) return;
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

