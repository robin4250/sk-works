import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_saved_qualification_photo_draft_page.dart';
import 'admin_saved_qualification_photo_prepare.dart';
import 'admin_saved_qualification_photo_submission_repository.dart';
import 'qualification_photo_mobile_runtime.dart';

const adminSavedPhotoManagementEnabled = bool.fromEnvironment(
  'SKO_ADMIN_SAVED_PHOTO_MANAGEMENT',
  defaultValue: false,
);

/// Defaults OFF until the dedicated backend contract and mobile rollout pass.
/// Changes saved photo references through approval requests, never the record or
/// Storage objects. The selected dataset's authoritative scope comes from caller.
class QualificationPhotoManagementRuntimePage extends StatefulWidget {
  const QualificationPhotoManagementRuntimePage({
    super.key,
    required this.scope,
    required this.qualificationName,
    required this.holderName,
    this.client,
    this.signedUrl,
    this.enabled = false,
  });
  final ValueListenable<AdminSavedQualificationPhotoSubmissionScope> scope;
  final String qualificationName, holderName;
  final SupabaseClient? client;
  final Future<String> Function(String)? signedUrl;
  final bool enabled;

  @override
  State<QualificationPhotoManagementRuntimePage> createState() =>
      _QualificationPhotoManagementRuntimePageState();
}

class _QualificationPhotoManagementRuntimePageState
    extends State<QualificationPhotoManagementRuntimePage>
    with WidgetsBindingObserver {
  final _contexts = StreamController<AdminSavedQualificationPhotoSubmissionScope>.broadcast(sync: true);
  final _lifecycle = StreamController<bool>.broadcast(sync: true);
  final _draftScope = ValueNotifier(const AdminSavedQualificationPhotoScope());
  late final AdminSavedQualificationPhotoSubmissionScope _initial;
  QualificationPhotoMobileRuntime? _runtime;
  AdminSavedQualificationPhotoSubmissionRepository? _repository;
  AdminSavedQualificationPhotoSubmissionResult? _result;
  String? _pending, _token, _message;
  StreamSubscription<AuthState>? _auth;
  bool _foreground = false, _revoked = false, _busy = false, _loaded = false;

  @override
  void initState() {
    super.initState();
    _initial = widget.scope.value;
    if (!widget.enabled) {
      _message = '写真の変更申請は準備中です。現在は利用できません。';
      return;
    }
    widget.scope.addListener(_scopeChanged);
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final client = widget.client;
    _token = client?.auth.currentSession?.accessToken;
    if (client == null || widget.signedUrl == null || !_scopeMatches || !_foreground) {
      _revoked = true;
      _message = '会社・対象・ログイン状態を確認できません。元の画面から開き直してください。';
      return;
    }
    _auth = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          event.session?.user.id != _initial.actorId ||
          event.session?.accessToken != _token) {
        if (mounted) { setState(_invalidate); }
      }
    }, onError: (Object _) {
      if (mounted) { setState(_invalidate); }
    }, onDone: () {
      if (mounted) { setState(_invalidate); }
    });
    _draftScope.value = AdminSavedQualificationPhotoScope(
      companyId: _initial.companyId, actorId: _initial.actorId,
    );
    _runtime = QualificationPhotoMobileRuntime(
      client: client,
      scope: () => widget.scope.value,
      scopeChanges: _contexts.stream,
      foreground: () => _foreground,
      foregroundChanges: _lifecycle.stream,
      enabled: true,
    );
    unawaited(_run(_load));
  }

  bool get _scopeMatches {
    final now = widget.scope.value;
    final session = widget.client?.auth.currentSession;
    return !_revoked && now.active && _initial.active &&
        now.actorId == _initial.actorId &&
        now.companyId == _initial.companyId &&
        now.targetId == _initial.targetId &&
        session != null && !session.isExpired &&
        session.user.id == _initial.actorId &&
        session.accessToken == _token;
  }

  void _check() {
    if (!mounted) { throw StateError('画面が閉じられました。'); }
    if (!_scopeMatches || !_foreground) {
      _invalidate();
      throw StateError('写真やログイン状態が変わりました。元の画面から開き直してください。');
    }
  }

  void _invalidate() {
    if (_contexts.isClosed) { return; }
    _revoked = true;
    _draftScope.value = const AdminSavedQualificationPhotoScope();
    _contexts.add(const AdminSavedQualificationPhotoSubmissionScope(
      actorId: null, companyId: null, targetId: null, active: false,
    ));
    final runtime = _runtime;
    if (runtime != null) {
      unawaited(runtime.dispose().catchError((Object _) {}));
    }
  }

  void _scopeChanged() {
    _contexts.add(widget.scope.value);
    if (!_scopeMatches && mounted) {
      setState(() {
        _invalidate();
        _message = '会社・対象・ログイン状態が変わりました。元の画面から開き直してください。';
      });
    }
  }

  @override
  void didUpdateWidget(covariant QualificationPhotoManagementRuntimePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.client != widget.client ||
        oldWidget.enabled != widget.enabled) {
      oldWidget.scope.removeListener(_scopeChanged);
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _lifecycle.add(_foreground);
    if (!_foreground && mounted) {
      setState(() {
        _invalidate();
        _message = '画面を離れたため操作を停止しました。元の画面から開き直してください。';
      });
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || _revoked || !widget.enabled) { return; }
    setState(() { _busy = true; _message = null; });
    try {
      _check();
      await operation();
      _check();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = _revoked
              ? '操作を停止しました。元の画面から開き直してください。'
              : '処理を確認できません。保留中の申請を再確認してください。対応状況によっては現在利用できません。';
        });
      }
    } finally {
      if (mounted) { setState(() => _busy = false); }
    }
  }

  Future<void> _load() async {
    _loaded = false;
    final repository = _repository ??= await _runtime!.open();
    _check();
    final pending = await repository.pendingRequestId();
    _check();
    setState(() { _pending = pending; _result = null; _loaded = true; });
    if (pending != null) {
      final result = await repository.recover(expectedRequestId: pending);
      _check();
      setState(() => _result = result);
    }
  }

  Future<List<String>> _savedPaths() async {
    _check();
    // Query only the selected company/qualification under the captured token.
    final row = await widget.client!
        .from('worker_qualifications')
        .select('id, company_id, attachment_path, attachment_back_path, attachment_extra_paths')
        .eq('company_id', _initial.companyId!)
        .eq('id', _initial.targetId!)
        .single()
        .setHeader('Authorization', 'Bearer $_token');
    _check();
    if (row['company_id'] != _initial.companyId || row['id'] != _initial.targetId) {
      throw StateError('資格の対象が変わりました。');
    }
    final paths = <String>[
      for (final value in [row['attachment_path'], row['attachment_back_path']])
        if (value is String && value.isNotEmpty) value,
      ...(row['attachment_extra_paths'] as List? ?? const []).cast<String>(),
    ];
    if (paths.isEmpty || paths.length > 20 ||
        paths.any((p) => p.trim().isEmpty) || paths.toSet().length != paths.length) {
      throw StateError('保存済み写真を確認できません。');
    }
    return List.unmodifiable(paths);
  }

  Future<String> _photoUrl(String path) async {
    _check();
    final reader = widget.signedUrl;
    if (reader == null) { throw StateError('写真表示を利用できません。'); }
    final url = await reader(path);
    _check();
    return url;
  }

  Widget _photo(BuildContext context, String path) => FutureBuilder<String>(
    future: _photoUrl(path),
    builder: (context, snapshot) {
      if (snapshot.hasError) { return const Center(child: Text('写真を表示できません。')); }
      if (!snapshot.hasData) { return const Center(child: CircularProgressIndicator()); }
      return Image.network(snapshot.data!, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(child: Text('写真を表示できません。')));
    },
  );

  String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _prepare() async {
    final authorization = await _runtime!.authorization();
    _check();
    final baseline = await _savedPaths();
    _check();
    if (!mounted) { return; }
    final draft = await Navigator.of(context).push<AdminSavedQualificationPhotoDraft>(
      MaterialPageRoute(builder: (_) => AdminSavedQualificationPhotoDraftPage(
        capability: authorization.capability,
        companyId: _initial.companyId!, actorId: _initial.actorId!,
        targetId: _initial.targetId!, savedPaths: baseline, scope: _draftScope,
        photoBuilder: _photo,
      )),
    );
    _check();
    if (draft == null) { return; }
    final current = await _savedPaths();
    _check();
    final latest = await _runtime!.authorization();
    _check();
    final command = AdminSavedQualificationPhotoPrepare.fromDraft(
      draft: draft, capability: latest.capability, readiness: latest.readiness,
      requestId: _requestId(), scopeActive: true,
      currentCompanyId: _initial.companyId, currentActorId: _initial.actorId,
      currentTargetId: _initial.targetId, currentSavedPaths: current,
    );
    try {
      final result = await _repository!.prepare(command: command, currentSavedPaths: current);
      _check();
      setState(() { _pending = command.requestId; _result = result; });
    } catch (_) {
      // prepare may have persisted its fixed identity before an uncertain HTTP.
      _pending = command.requestId;
      rethrow;
    }
  }

  Future<void> _action({required bool cancel}) async {
    final id = _pending;
    if (id == null) { return; }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cancel ? '下書きを取り消しますか？' : '写真の変更を申請しますか？'),
        content: Text(cancel ? '保存済みの正式な写真は変更されません。' : '承認後に写真の変更が反映されます。資格登録そのものは削除しません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(cancel ? '下書きを取り消す' : '変更を申請')),
        ],
      ),
    );
    _check();
    if (confirmed != true) { return; }
    final result = cancel
        ? await _repository!.cancelDraft(expectedRequestId: id)
        : await _repository!.submit(expectedRequestId: id);
    _check();
    setState(() => _result = result);
  }

  void _help() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('資格写真の変更申請'),
        content: const SingleChildScrollView(child: ExpansionTile(
          title: Text('操作と保留中の申請について'),
          children: [Padding(
            padding: EdgeInsets.all(12),
            child: Text('残す写真と順番を選び、下書きを保存してから明示的に申請します。すべて外すと添付写真の除外申請になります。資格登録そのものや共有済み写真を直接削除しません。送信結果が不明な場合は新しく申請せず、同じ保留中の申請を再確認します。確定した申請は取り消せません。承認には別の正規権限が必要です。会社・対象・ログインの変更やバックグラウンド移行時は画面を開き直してください。準備中の場合は利用できません。'),
          )],
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
      ),
    );
  }

  @override
  void dispose() {
    widget.scope.removeListener(_scopeChanged);
    unawaited(_auth?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _draftScope.dispose();
    final runtime = _runtime;
    if (runtime != null) {
      unawaited(runtime.dispose().catchError((Object _) {}));
    }
    unawaited(_contexts.close());
    unawaited(_lifecycle.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.enabled && !_revoked && !_busy && _repository != null;
    final status = switch (_result?.status) {
      'draft' => '未送信の下書き',
      'pending' => '承認待ち',
      'approved' => '承認済み',
      'rejected' => _result?.cancelled == true ? '下書き取消済み' : '差戻し',
      _ => '結果未確認',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('資格写真の変更申請'), actions: [
        IconButton(tooltip: 'ヘルプ', onPressed: _help, icon: const Icon(Icons.help_outline)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.qualificationName, style: Theme.of(context).textTheme.titleLarge),
        Text('保有者: ${widget.holderName}'),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_message!)),
        if (_pending != null) ...[
          Text('保留中の申請: $status'),
          if (_result?.reason != null) Text(_result!.reason!),
          OutlinedButton(onPressed: allowed ? () => _run(_load) : null, child: const Text('同じ申請を再確認')),
          if (_result?.status == 'draft') ...[
            FilledButton(onPressed: allowed ? () => _run(() => _action(cancel: false)) : null, child: const Text('変更を申請')),
            TextButton(onPressed: allowed ? () => _run(() => _action(cancel: true)) : null, child: const Text('下書きを取り消す')),
          ],
          QualificationPhotoAcknowledgementButton(
            status: _result?.status,
            onPressed: allowed ? () => _run(() async {
              final id = _pending!;
              final latest = await _repository!.recover(expectedRequestId: id);
              _check();
              setState(() => _result = latest);
              if (latest.status != 'approved' && latest.status != 'rejected') {
                throw StateError('承認待ちの申請は保留を閉じられません。');
              }
              await _repository!.acknowledge(expectedRequestId: id);
              _check();
              setState(() { _pending = null; _result = null; });
            }) : null,
          ),
        ] else if (widget.enabled && !_revoked)
          FilledButton(onPressed: allowed && _loaded ? () => _run(_prepare) : null, child: const Text('残す写真を選ぶ')),
        if (widget.enabled && !_revoked && _repository != null && !_loaded && !_busy)
          OutlinedButton(onPressed: () => _run(_load), child: const Text('保留中の申請を再確認')),
        if (widget.enabled && !_revoked && _repository == null && !_busy)
          const Text('元の画面から開き直してください。'),
      ]),
    );
  }
}

/// Only terminal values from the submission result contract may expose local
/// receipt acknowledgement. Pending retains identity and prevents a new prepare.
class QualificationPhotoAcknowledgementButton extends StatelessWidget {
  const QualificationPhotoAcknowledgementButton({
    super.key, required this.status, required this.onPressed,
  });
  final String? status;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    if (status != 'approved' && status != 'rejected') {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: onPressed,
      child: const Text('確認済みとして保留を閉じる'),
    );
  }
}
