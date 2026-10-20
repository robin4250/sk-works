import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_saved_qualification_photo_sqflite_connection.dart';
import 'admin_saved_qualification_photo_store_factory.dart';
import 'admin_saved_qualification_photo_submission_repository.dart';
import 'qualification_photo_session_rpc_supabase.dart';

/// Unconnected bootstrap. A product page must explicitly own scope/lifecycle
/// streams and dispose this runtime. Construction performs no RPC or path work.
class QualificationPhotoMobileRuntime {
  QualificationPhotoMobileRuntime({
    required SupabaseClient client,
    required AdminSavedQualificationPhotoSubmissionScope Function() scope,
    required Stream<AdminSavedQualificationPhotoSubmissionScope> scopeChanges,
    required bool Function() foreground,
    required Stream<bool> foregroundChanges,
    bool enabled = false,
  }) : this.forTesting(
         client: client,
         scope: scope,
         scopeChanges: scopeChanges,
         foreground: foreground,
         foregroundChanges: foregroundChanges,
         supportDirectory: getApplicationSupportDirectory,
         enabled: enabled,
       );

  /// Replaces only the authoritative directory provider, never the DB path,
  /// native adapter, RPC transport or factory confinement checks.
  QualificationPhotoMobileRuntime.forTesting({
    required SupabaseClient client,
    required AdminSavedQualificationPhotoSubmissionScope Function() scope,
    required Stream<AdminSavedQualificationPhotoSubmissionScope> scopeChanges,
    required bool Function() foreground,
    required Stream<bool> foregroundChanges,
    required Future<Directory> Function() supportDirectory,
    bool enabled = false,
  }) : _client = client,
       _scope = scope,
       _scopeChanges = scopeChanges,
       _foreground = foreground,
       _foregroundChanges = foregroundChanges,
       _supportDirectory = supportDirectory,
       _enabled = enabled;

  final SupabaseClient _client;
  final AdminSavedQualificationPhotoSubmissionScope Function() _scope;
  final Stream<AdminSavedQualificationPhotoSubmissionScope> _scopeChanges;
  final bool Function() _foreground;
  final Stream<bool> _foregroundChanges;
  final Future<Directory> Function() _supportDirectory;
  final bool _enabled;
  QualificationPhotoSessionRpcSupabase? _rpc;
  AdminQualificationPhotoStoreFactory? _factory;
  SqfliteAdminQualificationConnection? _native;
  AdminSavedQualificationPhotoSubmissionRepository? _repository;
  StreamSubscription<AdminSavedQualificationPhotoSubmissionScope>? _revocation;
  Future<AdminSavedQualificationPhotoSubmissionRepository>? _opening;
  Future<void>? _cleanup;
  Future<void>? _disposing;
  bool _closed = false;

  Future<AdminSavedQualificationPhotoSubmissionRepository> open() {
    if (!_enabled || _closed) {
      return Future.error(StateError('Qualification photo runtime is closed'));
    }
    return _opening ??= _start();
  }

  void _check() {
    if (!_enabled || _closed || _rpc?.scope().active != true) {
      throw StateError('Qualification photo runtime scope changed');
    }
  }

  Future<String> _canonicalize(String path) async {
    _check();
    final result = await Directory(path).resolveSymbolicLinks();
    _check();
    return result;
  }

  Future<String> _canonicalSupportRoot() async {
    _check();
    final directory = await _supportDirectory();
    _check();
    return _canonicalize(directory.path);
  }

  Future<AdminSavedQualificationPhotoSubmissionRepository> _start() async {
    try {
      final rpc = QualificationPhotoSessionRpcSupabase(
        client: _client,
        scope: _scope,
        scopeChanges: _scopeChanges,
        foreground: _foreground,
        foregroundChanges: _foregroundChanges,
        enabled: true,
      );
      _rpc = rpc;
      _revocation = rpc.scopeChanges.listen((scope) {
        if (!scope.active && !_closed) {
          unawaited(dispose().catchError((Object _) {}));
        }
      });
      _check();
      // Fresh dedicated capability/readiness must succeed before path access.
      await rpc.authorization();
      _check();
      final root = await _canonicalSupportRoot();
      _check();
      final factory = AdminQualificationPhotoStoreFactory(
        canonicalSupportRoot: root,
        supportRoot: _canonicalSupportRoot,
        canonicalizeRoot: _canonicalize,
        open: (path) async {
          _check();
          final native = await SqfliteAdminQualificationConnection.open(
            canonicalPrivateSupportRoot: root,
            databasePath: path,
          );
          // Own a late native result before checking disposal/scope changes.
          _native = native;
          _check();
          return native;
        },
        scope: rpc.scope,
        scopeChanges: rpc.scopeChanges,
      );
      _factory = factory;
      final store = await factory.create();
      _check();
      final repository = AdminSavedQualificationPhotoSubmissionRepository(
        scope: rpc.scope,
        scopeChanges: rpc.scopeChanges,
        authorization: rpc.authorization,
        rpc: rpc.rpc,
        store: store,
        enabled: true,
      );
      _repository = repository;
      _check();
      return repository;
    } catch (error, stack) {
      _closed = true;
      _rpc?.invalidate();
      try {
        await _closeResources();
      } catch (_) {
        // Retain the bootstrap failure; dispose still exposes cleanup failure.
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _closeResources() => _cleanup ??= _closeAll();

  Future<void> _closeAll() async {
    Object? failure;
    StackTrace? failureStack;
    Future<void> attempt(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await attempt(() async { await _revocation?.cancel(); });
    await attempt(() async { await _repository?.dispose(); });
    await attempt(() async { await _factory?.dispose(); });
    await attempt(() async { await _rpc?.dispose(); });
    await attempt(() async {
      final native = _native;
      if (native != null) {
        native.invalidate();
        await native.closed;
      }
    });
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
  }

  Future<void> dispose() {
    _closed = true;
    _rpc?.invalidate();
    return _disposing ??= _disposeAfterOpen();
  }

  Future<void> _disposeAfterOpen() async {
    // Wait for an in-flight provider/native open to return before final cleanup.
    // Never acknowledge, clear or delete an uncertain pending submission.
    try {
      await _opening;
    } catch (_) {
      // The original error is retained by open().
    }
    await _closeResources();
  }
}
