import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../international/language_controller.dart';
import '../../data/supabase_backend.dart';
import 'admin_saved_qualification_photo_submission_repository.dart';
import 'qualification_photo_management_runtime_page.dart';
import 'qualification_certificate_repository.dart';

const registeredQualificationChangeNotice =
    '登録後の変更には承認が必要です。変更申請の準備が整うまで編集できません。';

class QualificationCertificatePage extends StatefulWidget {
  const QualificationCertificatePage({
    super.key,
    this.initialQualificationId,
    this.repository,
  });
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
  final _queryController = TextEditingController();

  List<Map<String, dynamic>> _masters = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _qualifications = [];
  bool _loading = true;
  bool _canManage = false;
  String _query = '';
  String? _busyId;
  String? _error;
  String? _companyId;
  final _managementScope = ValueNotifier(const AdminSavedQualificationPhotoSubmissionScope(
    actorId: null, companyId: null, targetId: null, active: false,
  ));

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? QualificationCertificateRepository.maybeCreate();
    _actor = _repository?.currentUserId;
    _revoked = _actor == null;
    _authSubscription = _repository?.authChanges.listen((state) {
      if (state.session?.user.id != _actor) _revoke();
    }, onError: (Object error) => _revoke());
    _load();
  }

  void _revoke() {
    if (!mounted || _revoked) return;
    _disableManagementScope();
    setState(() {
      _revoked = true;
      _generation++;
      _masters = [];
      _workers = [];
      _qualifications = [];
      _canManage = false;
      _loading = false;
      _busyId = null;
      _error = null;
      _query = '';
      _queryController.clear();
    });
  }

  bool get _scopeActive =>
      mounted &&
      !_revoked &&
      _actor != null &&
      _repository?.currentUserId == _actor;

  @override
  void didUpdateWidget(covariant QualificationCertificatePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQualificationId != widget.initialQualificationId ||
        oldWidget.repository != widget.repository) {
      _disableManagementScope();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _disableManagementScope();
    _managementScope.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _disableManagementScope();
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
        _companyId = data['company_id'] as String?;
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
      if (!_scopeActive || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
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
              row['id']?.toString() != widget.initialQualificationId) {
            return false;
          }
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

  void _disableManagementScope() {
    _managementScope.value = const AdminSavedQualificationPhotoSubmissionScope(
      actorId: null, companyId: null, targetId: null, active: false,
    );
  }

  Future<void> _managePhotos(Map<String, dynamic> row, String qualification, String holder) async {
    if (!_scopeActive || !_canManage) { return; }
    _managementScope.value = AdminSavedQualificationPhotoSubmissionScope(
      actorId: _actor, companyId: _companyId, targetId: row['id']?.toString(),
      active: _scopeActive && _companyId != null,
    );
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
        QualificationPhotoManagementRuntimePage(
          scope: _managementScope,
          qualificationName: qualification,
          holderName: holder,
          enabled: adminSavedPhotoManagementEnabled,
          client: adminSavedPhotoManagementEnabled && SupabaseBackend.isInitialized
              ? SupabaseBackend.client : null,
          signedUrl: _repository?.createSignedUrl,
        )));
    } finally {
      if (mounted) { _disableManagementScope(); }
    }
    if (mounted && _scopeActive) { await _load(); }
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StreamBuilder<AuthState>(
        stream: repository.authChanges,
        builder: (context, snapshot) {
          SkoLanguageController.watch(context);
          if (!_scopeActive ||
              repository.currentUserId != actor ||
              snapshot.hasError ||
              (snapshot.hasData && snapshot.data?.session?.user.id != actor)) {
            sheetRevoked = true;
          }
          if (sheetRevoked) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('ログイン状態が変わりました。画面を閉じて開き直してください。'),
              ),
            );
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
                    Text(workerName),
                    if ((row['certificate_number']?.toString() ?? '')
                        .isNotEmpty)
                      Text('証明書番号: ${row['certificate_number']}'),
                    if ((row['expires_at']?.toString() ?? '').isNotEmpty)
                      Text('有効期限: ${row['expires_at']}'),
                    if (_canManage) ...[
                      const SizedBox(height: 12),
                      Text(
                        SkoLanguageController.tr(
                          registeredQualificationChangeNotice,
                        ),
                      ),
                    ],
                    if (_canManage) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit_note),
                        label: const Text('写真の変更申請'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          unawaited(_managePhotos(row, qualificationName, workerName));
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    _sideSection(
                      title: '表面',
                      path: row['attachment_path']?.toString() ?? '',
                      repository: repository,
                    ),
                    const SizedBox(height: 18),
                    _sideSection(
                      title: '裏面（ない場合は登録不要）',
                      path: row['attachment_back_path']?.toString() ?? '',
                      repository: repository,
                    ),
                    for (final path
                        in QualificationCertificateRepository.extraPaths(
                          row,
                        )) ...[
                      const SizedBox(height: 18),
                      _sideSection(
                        title:
                            '追加写真 ${QualificationCertificateRepository.extraPaths(row).indexOf(path) + 3}',
                        path: path,
                        repository: repository,
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
          ],
        ),
      ),
    );
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
