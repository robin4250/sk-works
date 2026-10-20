import 'dart:async';

import 'admin_saved_qualification_photo_contract.dart';
import 'admin_saved_qualification_photo_sqlite_pending_store.dart';
import 'admin_saved_qualification_photo_submission_repository.dart';

/// No plugin imports. ApplicationSupportDirectory, real-path resolution and a
/// transaction-owning SQLite connector must be provided by a mobile bootstrap.
/// Every isolate must use that same authoritative provider; this class cannot
/// prove another isolate's configuration. No actor-specific database filenames.
class AdminQualificationPhotoStoreFactory {
  AdminQualificationPhotoStoreFactory({
    required String canonicalSupportRoot,
    required Future<String> Function() supportRoot,
    required Future<String> Function(String) canonicalizeRoot,
    required Future<AdminQualificationSqliteConnection> Function(String) open,
    required AdminSavedQualificationPhotoSubmissionScope Function() scope,
    required Stream<AdminSavedQualificationPhotoSubmissionScope> scopeChanges,
  }) : _root = _validateRoot(canonicalSupportRoot),
       _supportRoot = supportRoot,
       _canonicalize = canonicalizeRoot,
       _open = open,
       _scope = scope,
       _initial = scope() {
    _check();
    _subscription = scopeChanges.listen(
      (value) {
        if (!_matches(value)) {
          _revoke();
        }
      },
      onError: (Object _) => _revoke(),
      onDone: _revoke,
    );
  }

  static final Expando<bool> _claimed = Expando(
    'qualificationSQLiteConnection',
  );
  final String _root;
  final Future<String> Function() _supportRoot;
  final Future<String> Function(String) _canonicalize;
  final Future<AdminQualificationSqliteConnection> Function(String) _open;
  final AdminSavedQualificationPhotoSubmissionScope Function() _scope;
  final AdminSavedQualificationPhotoSubmissionScope _initial;
  late final StreamSubscription<AdminSavedQualificationPhotoSubmissionScope>
  _subscription;
  _GuardedConnection? _connection;
  Future<AdminSavedQualificationPhotoPendingStore>? _pending;
  bool _revoked = false;

  /// This fixed namespace is shared by all actor/company keys inside SQLite.
  String get databasePath =>
      '$_root/sko-qualification-photo-pending-v1.sqlite3';

  static String _validateRoot(String path) {
    if (!path.startsWith('/') ||
        path == '/' ||
        path.endsWith('/') ||
        path.contains('\\') ||
        path.codeUnits.any((unit) => unit < 32 || unit == 127) ||
        path
            .split('/')
            .skip(1)
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException(
        'Canonical private support directory required',
      );
    }
    return path;
  }

  bool _matches(AdminSavedQualificationPhotoSubmissionScope value) =>
      value.active &&
      _initial.active &&
      value.actorId == _initial.actorId &&
      value.companyId == _initial.companyId &&
      value.targetId == _initial.targetId;

  void _revoke() {
    _revoked = true;
    _connection?.invalidate();
  }

  void _check() {
    if (_revoked ||
        !_matches(_scope()) ||
        !AdminSavedQualificationPhotoCapability.isUuid(_initial.actorId) ||
        !AdminSavedQualificationPhotoCapability.isUuid(_initial.companyId) ||
        !AdminSavedQualificationPhotoCapability.isUuid(_initial.targetId)) {
      _revoke();
      throw StateError('Qualification store scope changed');
    }
  }

  Future<AdminSavedQualificationPhotoPendingStore> create() {
    _check();
    return _pending ??= _create();
  }

  Future<AdminSavedQualificationPhotoPendingStore> _create() async {
    try {
      final selected = _validateRoot(await _supportRoot());
      _check();
      if (selected != _root || await _canonicalize(selected) != _root) {
        throw StateError('Application support path identity changed');
      }
      _check();
      final raw = await _open(databasePath);
      // Claim before checking scope: an opener must never hand this connection
      // to a subsequent factory, including after failed or uncertain setup.
      if (_claimed[raw] == true) {
        throw StateError('SQLite connection object already claimed');
      }
      _claimed[raw] = true;
      final guarded = _GuardedConnection(raw, _check);
      _connection = guarded;
      _check();
      return _ScopedStore(
        SqliteAdminSavedQualificationPhotoPendingStore(guarded),
        _check,
        'sko.admin.qualification.photos.pending.v1.${_initial.actorId}.${_initial.companyId}',
      );
    } catch (_) {
      _revoke();
      rethrow;
    }
  }

  Future<void> dispose() async {
    _revoke();
    await _subscription.cancel();
  }
}

class _ScopedStore implements AdminSavedQualificationPhotoPendingStore {
  _ScopedStore(this.store, this.check, this.key);
  final AdminSavedQualificationPhotoPendingStore store;
  final void Function() check;
  final String key;
  void checkKey(String value) {
    check();
    if (value != key) {
      throw StateError('Pending record scope mismatch');
    }
  }

  @override
  Future<String?> read(String key) async {
    checkKey(key);
    final result = await store.read(key);
    check();
    return result;
  }

  @override
  Future<bool> compareAndSet(
    String key,
    String? expected,
    String? replacement,
  ) async {
    checkKey(key);
    final result = await store.compareAndSet(key, expected, replacement);
    check();
    return result;
  }
}

class _GuardedConnection implements AdminQualificationSqliteConnection {
  _GuardedConnection(this.inner, this.scopeCheck);
  final AdminQualificationSqliteConnection inner;
  final void Function() scopeCheck;
  bool _invalid = false;
  void _check() {
    if (_invalid) {
      throw StateError('SQLite connection invalidated');
    }
    scopeCheck();
  }

  @override
  void invalidate() {
    if (!_invalid) {
      _invalid = true;
      inner.invalidate();
    }
  }

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) =>
      inner.exclusive(() async {
        _check();
        final result = await operation();
        _check();
        return result;
      });
  @override
  Future<int> execute(String sql, List<Object?> parameters) async {
    _check();
    final result = await inner.execute(sql, parameters);
    _check();
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    _check();
    final result = await inner.query(sql, parameters);
    _check();
    return result;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(AdminQualificationSqliteExecutor) operation,
  ) async {
    _check();
    final result = await inner.transaction((executor) async {
      _check();
      return operation(_GuardedExecutor(executor, _check));
    });
    _check();
    return result;
  }
}

class _GuardedExecutor implements AdminQualificationSqliteExecutor {
  _GuardedExecutor(this.inner, this.check);
  final AdminQualificationSqliteExecutor inner;
  final void Function() check;
  @override
  Future<int> execute(String sql, List<Object?> parameters) async {
    check();
    final result = await inner.execute(sql, parameters);
    check();
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    check();
    final result = await inner.query(sql, parameters);
    check();
    return result;
  }
}
