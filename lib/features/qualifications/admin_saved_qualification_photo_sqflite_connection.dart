import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'admin_saved_qualification_photo_sqlite_pending_store.dart';
import 'admin_saved_qualification_photo_private_path.dart';

/// Disconnected native binding. Open only the factory's fixed private DB path.
/// Each instance owns a distinct native connection (singleInstance: false).
class SqfliteAdminQualificationConnection
    implements AdminQualificationSqliteConnection {
  SqfliteAdminQualificationConnection._(this._database);
  final Database _database;
  final Object _zone = Object();
  Future<void> _tail = Future.value();
  Future<void>? _closed;
  bool _invalid = false;
  bool _transactionActive = false;
  _ExclusiveLease? _activeLease;

  static Future<SqfliteAdminQualificationConnection> open({
    required String canonicalPrivateSupportRoot,
    required String databasePath,
  }) async {
    await verifyPrivatePath(canonicalPrivateSupportRoot, databasePath);
    final database = await openDatabase(databasePath, singleInstance: false);
    try {
      await verifyPrivatePath(canonicalPrivateSupportRoot, databasePath);
      return SqfliteAdminQualificationConnection._(database);
    } catch (error, stack) {
      try {
        await database.close();
      } catch (_) {
        // Keep the confinement failure even if cleanup also fails.
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Future<void> verifyPrivatePath(String root, String path) =>
      verifyAdminQualificationPrivatePath(root, path);

  void _check() {
    if (_invalid) {
      throw StateError('Qualification SQLite connection invalidated');
    }
  }

  /// Available to lifecycle owners/tests; invalidate is synchronous, close waits
  /// for the entire connection queue, including the active plugin transaction.
  Future<void> get closed => _closed ?? Future.value();
  @override
  void invalidate() {
    if (_invalid) {
      return;
    }
    _invalid = true;
    _closed = _tail.then((_) => _database.close());
    // The original Future remains observable through closed. Prevent an unhandled
    // async exception for lifecycle callers whose API is deliberately synchronous.
    unawaited(_closed!.catchError((Object _) {}));
  }

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) async {
    final inherited = Zone.current[_zone];
    if (inherited is _ExclusiveLease) {
      _check();
      if (!inherited.active || !identical(inherited, _activeLease)) {
        throw StateError('Qualification SQLite exclusive lease expired');
      }
      return operation();
    }
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    final lease = _ExclusiveLease();
    try {
      _check();
      _activeLease = lease;
      return await runZoned(operation, zoneValues: {_zone: lease});
    } finally {
      lease.active = false;
      _activeLease = null;
      done.complete();
    }
  }

  @override
  Future<int> execute(String sql, List<Object?> parameters) =>
      exclusive(() async {
        _check();
        if (_transactionActive) {
          throw StateError('Use the transaction executor inside its callback');
        }
        final result = await _execute(_database, sql, parameters);
        _check();
        return result;
      });
  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) => exclusive(() async {
    _check();
    if (_transactionActive) {
      throw StateError('Use the transaction executor inside its callback');
    }
    final result = await _database.rawQuery(sql, parameters);
    _check();
    return result;
  });
  @override
  Future<T> transaction<T>(
    Future<T> Function(AdminQualificationSqliteExecutor) operation,
  ) => exclusive(() async {
    _check();
    if (_transactionActive) {
      throw StateError('Nested qualification transaction');
    }
    _transactionActive = true;
    try {
      final result = await _database.transaction((transaction) async {
        final executor = _SqfliteTransactionExecutor(transaction, _check);
        try {
          _check();
          return await operation(executor);
        } finally {
          // End the lease before sqflite sends COMMIT or waits for its ACK.
          executor.active = false;
        }
      }, exclusive: true);
      _check();
      return result;
    } catch (error, stack) {
      invalidate();
      Error.throwWithStackTrace(error, stack);
    } finally {
      _transactionActive = false;
    }
  });
}

Future<int> _execute(
  DatabaseExecutor executor,
  String sql,
  List<Object?> parameters,
) async {
  final statement = sql.trimLeft().split(RegExp(r'\s+')).first.toUpperCase();
  if (const {
    'BEGIN',
    'COMMIT',
    'END',
    'ROLLBACK',
    'SAVEPOINT',
    'RELEASE',
  }.contains(statement)) {
    throw ArgumentError('Transaction control belongs to sqflite');
  }
  if (const {'INSERT', 'UPDATE', 'DELETE'}.contains(statement)) {
    return executor.rawUpdate(sql, parameters);
  }
  await executor.execute(sql, parameters);
  return 0;
}

class _SqfliteTransactionExecutor implements AdminQualificationSqliteExecutor {
  _SqfliteTransactionExecutor(this.transaction, this.connectionCheck);
  final Transaction transaction;
  final void Function() connectionCheck;
  bool active = true;
  void _check() {
    connectionCheck();
    if (!active) {
      throw StateError('Qualification transaction executor expired');
    }
  }

  @override
  Future<int> execute(String sql, List<Object?> parameters) async {
    _check();
    final result = await _execute(transaction, sql, parameters);
    _check();
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    _check();
    final result = await transaction.rawQuery(sql, parameters);
    _check();
    return result;
  }
}

class _ExclusiveLease {
  bool active = true;
}
