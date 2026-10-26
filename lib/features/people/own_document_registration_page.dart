import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'worker_document_repository.dart';
import 'worker_document_change_flow.dart';
import 'worker_document_change_repository.dart';
import '../shared/resource_registration_card.dart';
import '../common/data_date_labels.dart';

import 'worker_document_scope.dart';
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
    bool requireEmptyAttachment = false,
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

abstract interface class OwnDocumentChangeGateway implements OwnDocumentRegistrationGateway {
  String? get actorId;
  bool get isCurrentActor;
  Future<String> changeCompanyId();
  WorkerDocumentChangeRepository createChangeRepository();
  Future<String> signedUrl(String path);
}

class _OwnDocumentRepositoryGateway
    implements OwnDocumentRegistrationGateway, OwnDocumentPhotoGateway, OwnDocumentChangeGateway {
  _OwnDocumentRepositoryGateway(this.repository) : actorId = repository.actorId;
  final WorkerDocumentRepository repository;
  @override
  final String? actorId;

  @override
  bool get isCurrentActor => actorId != null && actorId == repository.actorId;
  @override
  Future<String> changeCompanyId() async => (await repository.membership()).companyId;
  @override
  WorkerDocumentChangeRepository createChangeRepository() => repository.createChangeRepository();

  @override
  bool get photoEditingAvailable => repository.photoEditingAvailable;

  @override
  Future<String> signedUrl(String path) async {
    if (actorId == null || actorId != repository.actorId) throw StateError('Session changed');
    final url = await repository.createSignedAttachmentUrl(path);
    if (actorId != repository.actorId) throw StateError('Session changed');
    return url;
  }

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
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    if (actorId == null || actorId != repository.actorId) throw StateError('Session changed');
    final data = await repository.loadOwnDocuments();
    if (actorId != repository.actorId) throw StateError('Session changed');
    return data;
  }

  @override
  Future<void> saveOwnDocument({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    Uint8List? attachmentBytes,
    String? originalFilename,
    bool requireEmptyAttachment = false,
  }) => repository.saveOwnDocument(
    requirementId: requirementId,
    expiresAt: expiresAt,
    notes: notes,
    attachmentBytes: attachmentBytes,
    originalFilename: originalFilename,
    requireEmptyAttachment: requireEmptyAttachment,
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
        _requirements = (data['requirements'] ?? const <Map<String, dynamic>>[])
            .where((row) => row['is_active'] != false)
            .toList(growable: false);
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

  Future<bool> _changeRegistered(Map<String, dynamic>? row) async {
    if (!workerDocumentHasRegisteredContent(row)) return false;
    try {
    final gateway = _repository;
    if (gateway is! OwnDocumentChangeGateway) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('書類変更申請は準備中です。')));
      return true;
    }
    final actor = gateway.actorId;
    if (actor == null || !gateway.isCurrentActor) return true;
    final changes = gateway.createChangeRepository();
    try {
      final companyId = await gateway.changeCompanyId();
      if (!mounted || !changes.isCurrentActor || !gateway.isCurrentActor) return true;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkerDocumentChangePage(
        repository: changes, actor: actor, companyId: companyId, row: row!,
        signedUrl: gateway.signedUrl,
        isCurrent: () => mounted && gateway.isCurrentActor,
      )));
    } finally { await changes.dispose(); }
    if (mounted) await _load();
    return true;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('変更申請を開けません。接続とログイン状態を確認してください。')));
      return true;
    }
  }

  Future<void> _registerDocument({String? initialRequirementId}) async {
    final repository = _repository;
    if (repository == null || _requirements.isEmpty || _saving) return;

    if (initialRequirementId != null && await _changeRegistered(_statusFor(initialRequirementId))) return;
    if (!mounted) return;

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

    var requirementId =
        initialRequirementId ?? candidates.first['id']?.toString();
    DateTime? expiresAt;
    final notes = TextEditingController();
    var attachPhoto = false;
    final photoEditingAvailable =
        repository is! OwnDocumentPhotoGateway ||
        repository.photoEditingAvailable;

    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => Theme(
        data: _registrationTheme(dialogContext),
        child: StatefulBuilder(
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
                      style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _documentRegistrationStep(
                    '①', '書類種類', requirementId == null ? '必須' : '選択済み',
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
                    onChanged: (value) => setDialogState(() {
                      requirementId = value;
                      attachPhoto = false;
                    }),
                  )),
                  const SizedBox(height: 8),
                  _documentRegistrationStep(
                    '②', '有効期限', expiresAt == null ? '任意' : '設定済み',
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
                  )),
                  const SizedBox(height: 8),
                  _documentRegistrationStep(
                    '③', '備考', '任意',
                    TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: '備考'),
                    maxLines: 2,
                  )),
                  const SizedBox(height: 8),
                  if (!photoEditingAvailable)
                    const Text(
                      '複数写真は準備中です。会社で写真の送信が許可された書類のみ、写真未登録なら1枚を初回登録できます。保存済みの写真は保持します。',
                    ),
                  _documentRegistrationStep(
                    '④', '添付', attachPhoto ? '次に選択' : '任意',
                    CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('写真を添付する'),
                    value: attachPhoto,
                    onChanged:
                        !photoEditingAvailable &&
                            workerDocumentPaths(_statusFor(requirementId ?? ''))
                                .isNotEmpty
                        ? null
                        : (value) =>
                              setDialogState(() => attachPhoto = value ?? false),
                  )),
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
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('⑤ '), Text('登録')]),
              ),
            ],
          ),
        ),
      ),
    );
    notes.dispose();
    if (draft == null || !mounted) return;

    final requirement = draft['requirementId'] as String;
    if (await _changeRegistered(_statusFor(requirement))) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      if (repository is OwnDocumentPhotoGateway &&
          repository.photoEditingAvailable &&
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
        final source = await showModalBottomSheet<String>(
          context: context,
          builder: (sheetContext) => Theme(
            data: _registrationTheme(sheetContext),
            child: SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('カメラで撮影'),
                    onTap: () => Navigator.pop(sheetContext, 'camera'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('写真から選ぶ'),
                    onTap: () => Navigator.pop(sheetContext, 'gallery'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('PDFを選ぶ'),
                    onTap: () => Navigator.pop(sheetContext, 'pdf'),
                  ),
                ],
              ),
            ),
          ),
        );
        if (source == null || !mounted) return;
        if (source == 'pdf') {
          final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
          if (file == null || !mounted) return;
          final bytes = await file.readAsBytes();
          if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
            throw const FormatException('PDFファイルを選択してください。');
          }
          attachmentBytes = bytes;
          originalFilename = file.name;
        } else {
          final picked = widget.pickPhoto != null
              ? await widget.pickPhoto!(source == 'camera' ? ImageSource.camera : ImageSource.gallery)
              : await _picker.pickImage(
                  source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
                  imageQuality: 88,
                  maxWidth: 2400,
                );
          if (picked == null || !mounted) return;
          attachmentBytes = await picked.readAsBytes();
          originalFilename = picked.name;
        }
        if (!mounted) return;
      }

      await repository.saveOwnDocument(
        requirementId: requirement,
        expiresAt: draft['expiresAt'] as DateTime?,
        notes: draft['notes'] as String,
        attachmentBytes: attachmentBytes,
        originalFilename: originalFilename,
        requireEmptyAttachment:
            repository is OwnDocumentPhotoGateway &&
            !repository.photoEditingAvailable &&
            attachmentBytes != null,
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
    if (gateway is OwnDocumentChangeGateway && await _changeRegistered(row)) return;
    if (!mounted) return;
    if (gateway is! OwnDocumentPhotoGateway || _saving) return;
    final photos = await editWorkerDocumentPhotos(
      context,
      paths: workerDocumentPaths(row),
      signedUrl: gateway.signedUrl,
      canEdit: gateway.photoEditingAvailable && !workerDocumentHasRegisteredContent(row),
      allowNewPhotos: !workerDocumentHasRegisteredContent(row),
      uploadNotice: [resourceDocumentReviewLabel(row['status']),
        if ((row['expires_at']?.toString() ?? '').isNotEmpty) '期限 ${row['expires_at']}',
      ].join('\n'),
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

  ThemeData _registrationTheme(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return theme.copyWith(
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontSize: 18),
        titleMedium: text.titleMedium?.copyWith(fontSize: 14),
        titleSmall: text.titleSmall?.copyWith(fontSize: 13),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 14),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 14),
        bodySmall: text.bodySmall?.copyWith(fontSize: 12),
        labelLarge: text.labelLarge?.copyWith(fontSize: 14),
        labelMedium: text.labelMedium?.copyWith(fontSize: 12),
        labelSmall: text.labelSmall?.copyWith(fontSize: 11),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14)),
        ),
      ),
    );
  }

  void _showRegistrationHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => Theme(
        data: _registrationTheme(context),
        child: AlertDialog(
          title: const Text('自分の書類を登録'),
          content: const Text(
            '見出し・一覧・登録フォームの文字を小さめに揃えています。iPhoneの文字サイズ設定による拡大は利用できます。'
            '\n\n写真は表面・裏面・追加写真をまとめて保存できます。写真をタップすると拡大表示できます。'
            '自社・取引会社で共用の書類は、一度の登録を両方で使います。再撮影は不要です。'
            '一覧の「確認・編集」で、写真の追加・差し替え・並べ替え・一覧からの削除ができます。'
            '小さい画像・PDFを押すと、その場で拡大できます。下の「書類を登録」から既存の書類を登録します。'
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

    return Theme(
      data: _registrationTheme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '書類登録',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
        bottomNavigationBar: ResourceRegistrationFooter(
          label: '書類を登録',
          onPressed: _loading || _saving || _requirements.isEmpty || _worker == null
            ? null : _registerDocument,
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
                        subtitle: const Text(
                          'ログイン中の本人の書類だけを表示します',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    if (_repository is OwnDocumentPhotoGateway &&
                        !(_repository as OwnDocumentPhotoGateway)
                            .photoEditingAvailable)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          '複数写真は準備中です。会社で写真の送信が許可された書類のみ、写真未登録なら1枚を初回登録できます。現在の試験登録は会社が許可した運転免許証に限られます。',
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
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: requirements.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final requirement = requirements[index];
                          final id = requirement['id']?.toString() ?? '';
                          final status = _statusFor(id);
                          final paths = workerDocumentPaths(status);
                          final needsRegistration =
                              status == null ||
                              (paths.isEmpty &&
                                  _repository is OwnDocumentPhotoGateway &&
                                  !(_repository as OwnDocumentPhotoGateway)
                                      .photoEditingAvailable);
                          final label = needsRegistration ? '未登録' : '登録済み';
                          final gateway = _repository;
                          final attachments = [
                            for (var i = 0; i < paths.length; i++)
                              signedResourceAttachment(label: '${i + 1}',
                                path: paths[i], signedUrl: gateway is OwnDocumentPhotoGateway
                                  ? gateway.signedUrl : (_) async => throw StateError('Attachment unavailable')),
                          ];
                          final action = _saving ? null : needsRegistration
                            ? () => _registerDocument(initialRequirementId: id)
                            : gateway is OwnDocumentPhotoGateway
                              ? () => _editPhotos(status)
                              : () => _registerDocument(initialRequirementId: id);
                          final dates = DataDateLabels.labels(createdAt: status?['created_at'],
                            updatedAt: status?['updated_at']);
                          return ResourceRegistrationCard(
                            key: ValueKey('own-document:${gateway is _OwnDocumentRepositoryGateway ? gateway.actorId : ''}:${_worker?['id']}:$id'),
                            title: requirement['name']?.toString() ?? '書類',
                            icon: Icons.description_outlined,
                            registered: !needsRegistration,
                            statusLabel: label,
                            dateLabel: dates.isEmpty ? '' : dates.first,
                            detailLabel: [if (status != null) resourceDocumentReviewLabel(status['status']),
                              workerDocumentScopeLabel(requirement['scope']),
                              if ((status?['expires_at']?.toString() ?? '').isNotEmpty) '期限 ${status?['expires_at']}',
                              if (paths.length > 2) '添付 ${paths.length}件（詳細で確認）'].join(' / '),
                            attachments: attachments,
                            onAction: action,
                            onOpenDetail: action,
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}



Widget _documentRegistrationStep(
    String number, String label, String status, Widget child) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF1976D2), width: 1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(number, style: const TextStyle(
              color: Color(0xFF1976D2), fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Expanded(child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold))),
          Text(status, style: TextStyle(
              color: status == '選択済み' || status == '設定済み'
                  ? Colors.green.shade700 : Colors.black54, fontSize: 12)),
        ]),
        child,
      ],
    ),
  );
}
