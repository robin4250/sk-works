import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../people/worker_document_photo_editor.dart';
import '../people/worker_document_photos.dart';
import 'own_qualification_photo_contract.dart';
import 'own_qualification_photo_submission_repository.dart';

import 'qualification_cloud_repository.dart';
import '../shared/resource_registration_card.dart';


class OwnQualificationRegistrationPage extends StatefulWidget {
  const OwnQualificationRegistrationPage({super.key, this.repository, this.photoRepository, this.pickAttachments});

  @visibleForTesting
  final QualificationCloudRepository? repository;
  @visibleForTesting
  final OwnQualificationPhotoSubmissionRepository? photoRepository;
  @visibleForTesting
  final Future<List<WorkerDocumentPhoto>?> Function(BuildContext context, List<WorkerDocumentPhoto> current)? pickAttachments;

  @override
  State<OwnQualificationRegistrationPage> createState() =>
      _OwnQualificationRegistrationPageState();
}

class _OwnQualificationRegistrationPageState
    extends State<OwnQualificationRegistrationPage> {
  late final _repository = widget.repository ?? QualificationCloudRepository.maybeCreate();
  late final _photoRepository = widget.photoRepository ??
      OwnQualificationPhotoSubmissionRepository.maybeCreate();
  OwnQualificationPhotoCapability _photoCapability =
      OwnQualificationPhotoCapability.unavailable;
  Map<String, dynamic>? _pendingPhotos;
  List<Map<String, dynamic>> _photoSubmissions = const [];
  String? _photoError;
  bool _photoBusy = false;
  int _loadGeneration = 0;
  final _searchController = TextEditingController();

  Map<String, dynamic>? _worker;
  List<Map<String, dynamic>> _masters = const [];
  List<Map<String, dynamic>> _qualifications = const [];
  String _query = '';
  bool _loading = true;
  bool _registrationDialogOpen = false;
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
    final generation = ++_loadGeneration;
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
      if (!mounted ||
          generation != _loadGeneration ||
          actor == null ||
          actor != repository.currentUserId) {
        return;
      }
      setState(() {
        _worker = Map<String, dynamic>.from(data['worker'] as Map);
        _masters = List<Map<String, dynamic>>.from(data['masters'] as List);
        _qualifications = List<Map<String, dynamic>>.from(
          data['qualifications'] as List,
        );
        _loading = false;
      });
      await _loadPhotoWorkspace(actor, generation);
    } catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          actor != repository.currentUserId) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadPhotoWorkspace(String actor, int generation) async {
    final repository = _photoRepository;
    if (repository == null) return;
    try {
      final capability = await repository.capability();
      if (!mounted ||
          generation != _loadGeneration ||
          repository.actor != actor) {
        return;
      }
      final pending = await repository.pending();
      if (!mounted ||
          generation != _loadGeneration ||
          repository.actor != actor) {
        return;
      }
      final submissions = capability.available
          ? await repository.submissions()
          : <Map<String, dynamic>>[];
      if (!mounted ||
          generation != _loadGeneration ||
          repository.actor != actor) {
        return;
      }
      setState(() {
        _photoCapability = capability;
        _pendingPhotos = pending;
        _photoSubmissions = submissions;
        _photoError = null;
      });
    } catch (_) {
      if (!mounted ||
          generation != _loadGeneration ||
          repository.actor != actor) {
        return;
      }
      setState(() {
        _photoCapability = OwnQualificationPhotoCapability.unavailable;
        _photoError = '写真申請の利用状況を確認できません。保存済み写真と資格情報登録は利用できます。';
      });
    }
  }

  Future<void> _editPhotos(Map<String, dynamic> row) async {
    final repository = _photoRepository;
    final cloud = _repository;
    if (repository == null ||
        cloud == null ||
        !_photoCapability.available ||
        _photoBusy ||
        _pendingPhotos != null) {
      return;
    }
    final actor = repository.actor;
    final photos = QualificationCloudRepository.ownPhotoAttachments(row);
    final selection = await editWorkerDocumentPhotos(
      context,
      paths: photos.map((photo) => photo.path).toList(),
      signedUrl: (path) => cloud.createOwnQualificationPhotoUrl(
        qualificationId: row['id'].toString(),
        storagePath: path,
      ),
      allowNewPhotos: _photoCapability.uploadAllowed,
      uploadNotice: [
        ...resourceQualificationMetadata(row),
        _photoCapability.uploadAllowed
          ? '写真の変更は申請として送信し、承認後に登録内容へ反映します。資格名・番号などの情報は変更しません。'
          : '新しい資格証写真の送信は停止中です。保存済み写真の並べ替え・一覧からの削除だけを申請できます。承認後に反映し、写真ファイルは履歴に保持します。',
      ].join('\n'),
    );
    if (!mounted ||
        actor == null ||
        repository.actor != actor ||
        selection == null) {
      return;
    }
    setState(() => _photoBusy = true);
    try {
      final result = await repository.submitSelection(
        row: row,
        photos: selection,
      );
      if (!mounted || repository.actor != actor) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.status == 'approved'
                ? '写真の変更は承認済みです。'
                : '写真申請を送信しました。会社の管理者・承認担当者が「承認待ち」→「資格写真の承認待ち」で確認します。承認後に反映します。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted || repository.actor != actor) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('写真申請を確認してください: $error')));
    } finally {
      if (mounted && repository.actor == actor) {
        setState(() => _photoBusy = false);
        await _load();
      }
    }
  }

  Future<void> _recoverPhotos() async {
    final repository = _photoRepository;
    if (repository == null || _photoBusy || !_photoCapability.available) return;
    final actor = repository.actor;
    final requestId = _pendingPhotos?['request_id'] as String?;
    if (requestId == null) return;
    setState(() => _photoBusy = true);
    try {
      final result = await repository.recover(expectedRequestId: requestId);
      if (!mounted || actor == null || repository.actor != actor) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.status == 'approved'
                ? '写真の変更は承認済みです。'
                : result.status == 'rejected'
                ? (result.cancelled ? '未送信の写真申請の取消を確認しました。' : '写真申請は却下されています。')
                : '同じ写真申請の送信を確認しました。承認待ちです。',
          ),
        ),
      );
    } catch (_) {
      if (mounted && repository.actor == actor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('写真申請を確認できませんでした。写真を再送せず同じ申請を再確認してください。'),
          ),
        );
      }
    } finally {
      if (mounted && repository.actor == actor) {
        setState(() => _photoBusy = false);
        await _load();
      }
    }
  }

  Future<void> _cancelPendingPhotos() async {
    final repository = _photoRepository;
    if (repository == null || _photoBusy || !_photoCapability.available) return;
    final actor = repository.actor;
    final requestId = _pendingPhotos?['request_id'] as String?;
    if (requestId == null) return;
    if (actor == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未送信の写真申請を取り消す'),
        content: const Text(
          'サーバーで本人の下書きと確認できた場合だけ取り消します。承認待ち・承認済みの申請と登録済み写真は変更しません。写真ファイルは削除しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('下書きを取り消す'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || actor != repository.actor) return;
    setState(() => _photoBusy = true);
    try {
      await repository.cancelDraft(expectedRequestId: requestId);
      if (!mounted || actor != repository.actor) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未送信の写真申請を取り消しました。新しい申請を作成できます。')),
      );
    } catch (_) {
      if (mounted && actor == repository.actor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('本人の下書きの取消結果を確認できませんでした。保留を解除せず同じ申請を再確認してください。'),
          ),
        );
      }
    } finally {
      if (mounted && actor == repository.actor) {
        setState(() => _photoBusy = false);
        await _load();
      }
    }
  }

  String? _photoStatus(String targetId) {
    final rows = _photoSubmissions
        .where((row) => row['target_id'] == targetId)
        .toList();
    if (rows.isEmpty) return null;
    return switch (rows.first['status']) {
      'pending' => '写真変更：承認待ち',
      'approved' => '写真変更：承認済み',
      'rejected' =>
        rows.first['photo_cancelled'] == true
            ? '写真申請：下書き取消済み'
            : '写真変更：却下（登録内容は保持）',
      _ => '写真変更：状態を確認してください',
    };
  }

  Future<void> _addQualification({String? initialMasterId}) async {
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

    var masterId = filteredMasters.any((m) => m['id']?.toString() == initialMasterId)
      ? initialMasterId : filteredMasters.first['id']?.toString();
    final certificateController = TextEditingController();
    final issuerController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? issuedAt;
    DateTime? expiresAt;
    List<WorkerDocumentPhoto> selectedAttachments = [];

    setState(() => _registrationDialogOpen = true);
    Future<dynamic>? dialogCompleted;
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        dialogCompleted ??= ModalRoute.of(dialogContext)?.completed;
        return StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          constraints: const BoxConstraints(maxWidth: 560),
          title: const Text('自分の資格を登録'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
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
                isExpanded: true,
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: !_photoCapability.available ||
                          !_photoCapability.uploadAllowed || _pendingPhotos != null
                      ? null
                      : () async {
                          final selected = widget.pickAttachments != null
                              ? await widget.pickAttachments!(dialogContext, selectedAttachments)
                              : await editWorkerDocumentPhotos(
                            dialogContext,
                            paths: const [],
                            signedUrl: (_) async => '',
                            initialPhotos: selectedAttachments,
                          );
                          if (!dialogContext.mounted || selected == null) return;
                          setDialogState(() => selectedAttachments = selected);
                        },
                  icon: const Icon(Icons.attach_file),
                  label: Text('資格証を選択（${selectedAttachments.length}件）'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('資格情報の登録後、資格証を変更申請として送信します。承認後に反映されます。送信が停止中の場合は登録後に追加できます。'),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: '備考'),
                  maxLines: 2,
                ),
              ],
            ),
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
                      'attachments': selectedAttachments,
                    }),
              child: const Text('登録'),
            ),
          ],
        ),
        );
      },
    );

    void disposeDraft() {
      certificateController.dispose();
      issuerController.dispose();
      notesController.dispose();
      if (mounted) {
        setState(() => _registrationDialogOpen = false);
      }
    }
    final completed = dialogCompleted;
    if (completed == null) {
      disposeDraft();
    } else {
      unawaited(completed.then((_) => disposeDraft()));
    }
    if (draft == null) return;

    try {
      final inserted = await repository.insertOwnQualification(
        qualificationMasterId: draft['masterId'] as String,
        certificateNumber: draft['certificateNumber'] as String,
        issuer: draft['issuer'] as String,
        issuedAt: draft['issuedAt'] as DateTime?,
        expiresAt: draft['expiresAt'] as DateTime?,
        notes: draft['notes'] as String,
      );
      if (!mounted) return;
      final attachments = draft['attachments'] as List<WorkerDocumentPhoto>;
      if (attachments.isNotEmpty) {
        final photoRepository = _photoRepository;
        try {
          if (photoRepository == null) throw StateError('資格証の申請を利用できません。');
          await photoRepository.submitSelection(row: inserted, photos: attachments);
        } catch (_) {
          if (!mounted) return;
          await _load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('資格情報は登録済みです。資格証の申請結果を一覧で確認してください。'),
          ));
          return;
        }
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(attachments.isEmpty ? '自分の資格を登録しました' : '資格情報を登録し、資格証を申請しました。'),
      ));
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
                    if (index == 0)
                      for (final metadata in resourceQualificationMetadata(row)) Text(metadata),
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
                        if (photos[index].path.toLowerCase().endsWith('.pdf')) {
                          return OutlinedButton.icon(
                            onPressed: () async {
                              if (actor != repository.currentUserId) return;
                              try {
                                if (!await launchUrl(
                                  Uri.parse(snapshot.data!),
                                  mode: LaunchMode.externalApplication,
                                )) {
                                  throw StateError('PDFを開けませんでした。');
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('PDFを開けませんでした。'),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDFを開く'),
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
      resizeToAvoidBottomInset: !_registrationDialogOpen,
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
      bottomNavigationBar: ResourceRegistrationFooter(
        label: '資格を登録',
        onPressed: _loading || _masters.isEmpty || _worker == null
          ? null : _addQualification,
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
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _photoError ??
                                (!_photoCapability.available
                                    ? '資格証写真の変更申請は準備中です。登録済み写真と資格情報登録は利用できます。'
                                    : _photoCapability.uploadAllowed
                                    ? '資格証写真の変更は申請し、承認後に反映します。'
                                    : '新しい資格証写真の送信は停止中です。登録済み写真の並べ替え・削除申請は利用できます。'),
                          ),
                          if (_pendingPhotos != null) ...[
                            const SizedBox(height: 8),
                            const Text(
                              '送信結果が未確認の写真申請があります。写真を再送せず同じ申請を確認してください。',
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _photoBusy || !_photoCapability.available
                                  ? null
                                  : _recoverPhotos,
                              icon: const Icon(Icons.refresh),
                              label: const Text('保留中の写真申請を再確認'),
                            ),
                            TextButton(
                              onPressed:
                                  _photoBusy || !_photoCapability.available
                                  ? null
                                  : _cancelPendingPhotos,
                              child: const Text('未送信の下書きを取り消す'),
                            ),
                          ],
                          if (_photoBusy) const LinearProgressIndicator(),
                        ],
                      ),
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
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: qualifications.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
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
                              final unregistered = row['_unregistered'] == true;
                              final title = master?['name']?.toString() ?? '資格';
                              final repository = _repository;
                              final actor = repository?.currentUserId;
                              Future<String> signedUrl(String path) async {
                                if (repository == null || actor == null || actor != repository.currentUserId) {
                                  throw StateError('Session changed');
                                }
                                final url = await repository.createOwnQualificationPhotoUrl(
                                  qualificationId: row['id'].toString(), storagePath: path);
                                if (actor != repository.currentUserId) throw StateError('Session changed');
                                return url;
                              }
                              final attachments = [
                                signedResourceAttachment(label: '表面',
                                  path: row['attachment_path']?.toString(), signedUrl: signedUrl,
                                  known: unregistered || row.containsKey('attachment_path')),
                                signedResourceAttachment(label: '裏面',
                                  path: row['attachment_back_path']?.toString(), signedUrl: signedUrl,
                                  known: unregistered || row.containsKey('attachment_back_path')),
                              ];
                              final canEdit = !_photoBusy && _photoCapability.available && _pendingPhotos == null;
                              return ResourceRegistrationCard(
                                key: ValueKey('own-qualification:${_worker?['id']}:${row['id'] ?? row['qualification_master_id']}'),
                                title: title, icon: Icons.badge_outlined, registered: !unregistered,
                                dateLabel: [
                                  if ((row['issued_at']?.toString() ?? '').isNotEmpty)
                                    '取得日 ${row['issued_at']}',
                                  ((master?['category']?.toString() ?? '').trim().isEmpty)
                                    ? '区分未設定'
                                    : master!['category'].toString().trim(),
                                ].join(' / '),
                                statusLabel: unregistered ? '未登録' : '登録済み',
                                detailLabel: [...resourceQualificationMetadata(row),
                                  if (_photoStatus(row['id'].toString()) != null) _photoStatus(row['id'].toString())!,
                                  if (photos.length > 2) '添付 ${photos.length}件（詳細で確認）'].join(' / '),
                                attachments: attachments,
                                onAction: unregistered
                                  ? () => _addQualification(initialMasterId: row['qualification_master_id']?.toString())
                                  : canEdit ? () => _editPhotos(row) : () => _previewPhotos(row, title),
                                onOpenDetail: unregistered
                                  ? () => _addQualification(initialMasterId: row['qualification_master_id']?.toString())
                                  : canEdit ? () => _editPhotos(row) : () => _previewPhotos(row, title),
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

