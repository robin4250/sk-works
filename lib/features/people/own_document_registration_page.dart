import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'worker_document_repository.dart';
import 'worker_document_photos.dart';
import 'worker_document_photo_editor.dart';

abstract interface class OwnDocumentRegistrationGateway {
  Future<Map<String, List<Map<String, dynamic>>>> loadAll();

  Future<void> saveOwnDocument({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    Uint8List? attachmentBytes,
    String? originalFilename,
  });
}

abstract interface class OwnDocumentPhotoGateway
    implements OwnDocumentRegistrationGateway {
  bool get photoEditingAvailable;
  Future<String> signedUrl(String path);
  Future<void> savePhotos({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    required List<WorkerDocumentPhoto> photos,
    required List<String> expectedPaths,
  });
  Future<void> editPhotos(
    Map<String, dynamic> row,
    List<WorkerDocumentPhoto> photos,
  );
}

class _OwnDocumentRepositoryGateway
    implements OwnDocumentRegistrationGateway, OwnDocumentPhotoGateway {
  const _OwnDocumentRepositoryGateway(this.repository);
  final WorkerDocumentRepository repository;

  @override
  bool get photoEditingAvailable => repository.photoEditingAvailable;

  @override
  Future<String> signedUrl(String path) =>
      repository.createSignedAttachmentUrl(path);

  @override
  Future<void> savePhotos({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    required List<WorkerDocumentPhoto> photos,
    required List<String> expectedPaths,
  }) => repository.saveOwnDocumentPhotos(
    requirementId: requirementId,
    expiresAt: expiresAt,
    notes: notes,
    photos: photos,
    expectedPaths: expectedPaths,
  );

  @override
  Future<void> editPhotos(
    Map<String, dynamic> row,
    List<WorkerDocumentPhoto> photos,
  ) async {
    await repository.saveAttachmentPhotos(row: row, photos: photos, own: true);
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() =>
      repository.loadOwnDocuments();

  @override
  Future<void> saveOwnDocument({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    Uint8List? attachmentBytes,
    String? originalFilename,
  }) => repository.saveOwnDocument(
    requirementId: requirementId,
    expiresAt: expiresAt,
    notes: notes,
    attachmentBytes: attachmentBytes,
    originalFilename: originalFilename,
  );
}

class OwnDocumentRegistrationPage extends StatefulWidget {
  const OwnDocumentRegistrationPage({super.key, this.gateway, this.pickPhoto});

  final OwnDocumentRegistrationGateway? gateway;
  final Future<XFile?> Function(ImageSource source)? pickPhoto;

  @override
  State<OwnDocumentRegistrationPage> createState() =>
      _OwnDocumentRegistrationPageState();
}

class _OwnDocumentRegistrationPageState
    extends State<OwnDocumentRegistrationPage> {
  OwnDocumentRegistrationGateway? _repository;
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _requirements = const [];
  List<Map<String, dynamic>> _statuses = const [];
  Map<String, dynamic>? _worker;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final repository = widget.gateway == null
        ? WorkerDocumentRepository.maybeCreate()
        : null;
    _repository =
        widget.gateway ??
        (repository == null ? null : _OwnDocumentRepositoryGateway(repository));
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
        _requirements = data['requirements'] ?? const <Map<String, dynamic>>[];
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
    if (repository == null || _requirements.isEmpty || _saving) return;

    final needle = _query.trim().toLowerCase();
    final candidates = _requirements
        .where((row) {
          if (needle.isEmpty) return true;
          return [
            row['name'],
            row['scope'],
          ].whereType<Object>().join(' ').toLowerCase().contains(needle);
        })
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('該当する書類種類がありません')));
      return;
    }

    var requirementId = candidates.first['id']?.toString();
    DateTime? expiresAt;
    final notes = TextEditingController();
    var attachPhoto = false;
    final photoEditingAvailable =
        repository is! OwnDocumentPhotoGateway ||
        repository.photoEditingAvailable;

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
                if (!photoEditingAvailable)
                  const Text(WorkerDocumentRepository.photoPreparationMessage),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('写真を添付する'),
                  value: attachPhoto,
                  onChanged: !photoEditingAvailable
                      ? null
                      : (value) =>
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
    if (draft == null || !mounted) return;

    final requirement = draft['requirementId'] as String;
    setState(() => _saving = true);
    try {
      if (repository is OwnDocumentPhotoGateway &&
          widget.pickPhoto == null &&
          draft['attachPhoto'] == true) {
        final photos = await editWorkerDocumentPhotos(
          context,
          paths: workerDocumentPaths(_statusFor(requirement)),
          signedUrl: repository.signedUrl,
        );
        if (photos == null || !mounted) return;
        await repository.savePhotos(
          requirementId: requirement,
          expiresAt: draft['expiresAt'] as DateTime?,
          notes: draft['notes'] as String,
          photos: photos,
          expectedPaths: workerDocumentPaths(_statusFor(requirement)),
        );
        if (!mounted) return;
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('自分の書類を登録しました')));
        }
        return;
      }
      Uint8List? attachmentBytes;
      String? originalFilename;
      if (draft['attachPhoto'] == true) {
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('カメラで撮影'),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('写真から選ぶ'),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
        if (source == null || !mounted) return;
        final picked = widget.pickPhoto != null
            ? await widget.pickPhoto!(source)
            : await _picker.pickImage(
                source: source,
                imageQuality: 88,
                maxWidth: 2400,
              );
        if (picked == null || !mounted) return;
        attachmentBytes = await picked.readAsBytes();
        originalFilename = picked.name;
        if (!mounted) return;
      }

      await repository.saveOwnDocument(
        requirementId: requirement,
        expiresAt: draft['expiresAt'] as DateTime?,
        notes: draft['notes'] as String,
        attachmentBytes: attachmentBytes,
        originalFilename: originalFilename,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('自分の書類を登録しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('書類を登録できませんでした: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editPhotos(Map<String, dynamic> row) async {
    final gateway = _repository;
    if (gateway is! OwnDocumentPhotoGateway || _saving) return;
    final photos = await editWorkerDocumentPhotos(
      context,
      paths: workerDocumentPaths(row),
      signedUrl: gateway.signedUrl,
      canEdit: gateway.photoEditingAvailable,
    );
    if (photos == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await gateway.editPhotos(row, photos);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('写真を保存できませんでした: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showRegistrationHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自分の書類を登録'),
        content: const Text(
          '写真は表面・裏面・追加写真をまとめて保存できます。写真をタップすると拡大表示できます。'
          '一覧の書類をタップすると、写真の追加・差し替え・並べ替え・一覧からの削除ができます。'
          '写真の選択や撮影をキャンセルした場合は保存しません。'
          '\n\n写真の送信や登録に失敗した場合は、登録成功として扱いません。'
          '送信結果が不明な場合は、書類一覧を再読み込みして確認してください。'
          'すでに保存した写真は、この画面の差し替えで削除しません。'
          '\n\n新しい写真の送信は、会社が試験登録を許可した運転免許証に限られます。'
          'その他の書類は写真の送信停止中です。保存済み写真の確認はできます。'
          '失敗表示が出た場合は登録完了ではありません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final requirements = _requirements
        .where((row) {
          if (needle.isEmpty) return true;
          return [
            row['name'],
            row['scope'],
          ].whereType<Object>().join(' ').toLowerCase().contains(needle);
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '書類登録',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '書類登録のヘルプ',
            onPressed: _showRegistrationHelp,
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _saving || _requirements.isEmpty
            ? null
            : _registerDocument,
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
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final requirement = requirements[index];
                        final id = requirement['id']?.toString() ?? '';
                        final status = _statusFor(id);
                        final paths = workerDocumentPaths(status);
                        final label =
                            status?['status']?.toString() == 'verified'
                            ? '確認済み'
                            : status?['status']?.toString() == 'submitted'
                            ? '提出済み'
                            : '未登録';
                        return Card(
                          child: ListTile(
                            onTap:
                                status == null ||
                                    _saving ||
                                    _repository is! OwnDocumentPhotoGateway
                                ? null
                                : () => _editPhotos(status),
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
                                if (paths.isNotEmpty)
                                  '画像あり${paths.length > 1 ? '（${paths.length}枚）' : ''}'
                                else if (status?['status'] == 'submitted')
                                  '写真未添付',
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
