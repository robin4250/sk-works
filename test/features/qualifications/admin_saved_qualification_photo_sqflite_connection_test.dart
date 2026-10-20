import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException, SqflitePlugin;
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_sqflite_connection.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_sqlite_pending_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Linux test host: explicitly register the public mobile methodchannel plugin.
  SqflitePlugin.registerWith();
  const channel = MethodChannel('com.tekartik.sqflite');
  late Directory root;
  late List<MethodCall> calls;
  int nextId = 1;
  Completer<void>? commitEntered;
  Completer<void>? commitRelease;
  bool loseCommit = false;
  bool emulateCas = false;
  String? stored;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sko-sqflite-channel-');
    root = Directory(await root.resolveSymbolicLinks());
    calls = [];
    commitEntered = null;
    commitRelease = null;
    loseCommit = false;
    emulateCas = false;
    stored = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final args = call.arguments as Map?;
          switch (call.method) {
            case 'openDatabase':
              return {'id': nextId++};
            case 'closeDatabase':
              return null;
            case 'getDatabasesPath':
              return root.path;
            case 'query':
              if (emulateCas) {
                final sql = args!['sql'] as String;
                if (sql.contains('journal_mode')) {
                  return [
                    {'journal_mode': 'wal'},
                  ];
                }
                if (sql == 'PRAGMA synchronous') {
                  return [
                    {'synchronous': 2},
                  ];
                }
                if (sql == 'PRAGMA read_uncommitted') {
                  return [
                    {'read_uncommitted': 0},
                  ];
                }
                if (sql.startsWith('SELECT value')) {
                  return stored == null
                      ? []
                      : [
                          {'value': stored},
                        ];
                }
              }
              return [
                {'value': 1},
              ];
            case 'update':
              if (emulateCas) {
                final sql = args!['sql'] as String;
                final parameters = args['arguments'] as List;
                if (sql.startsWith('INSERT')) {
                  if (stored != null) {
                    return 0;
                  }
                  stored = parameters[1] as String;
                } else if (sql.startsWith('UPDATE')) {
                  if (stored != parameters[2]) {
                    return 0;
                  }
                  stored = parameters[0] as String;
                } else if (sql.startsWith('DELETE')) {
                  if (stored != parameters[1]) {
                    return 0;
                  }
                  stored = null;
                }
              }
              return 1;
            case 'execute':
              final sql = args!['sql'] as String;
              if (sql.startsWith('BEGIN')) {
                return {'transactionId': 100};
              }
              if (sql == 'COMMIT') {
                commitEntered?.complete();
                await commitRelease?.future;
                if (loseCommit) {
                  throw PlatformException(
                    code: 'sqlite_error',
                    message: 'commit acknowledgement unavailable',
                  );
                }
              }
              return null;
            default:
              throw StateError('Unexpected sqflite method ${call.method}');
          }
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  Future<SqfliteAdminQualificationConnection> open() =>
      SqfliteAdminQualificationConnection.open(
        canonicalPrivateSupportRoot: root.path,
        databasePath: '${root.path}/sko-qualification-photo-pending-v1.sqlite3',
      );

  test(
    'distinct native connection, transaction executor and affected rows',
    () async {
      final first = await open();
      final second = await open();
      expect(
        calls
            .where((c) => c.method == 'openDatabase')
            .every((c) => (c.arguments as Map)['singleInstance'] == false),
        isTrue,
      );
      AdminQualificationSqliteExecutor? captured;
      expect(
        await first.transaction((txn) async {
          captured = txn;
          return txn.execute('UPDATE test SET value = ?', [1]);
        }),
        1,
      );
      final mutation =
          calls.singleWhere((c) => c.method == 'update').arguments as Map;
      expect(mutation['transactionId'], 100);
      expect(
        calls.any(
          (c) =>
              c.method == 'execute' &&
              ((c.arguments as Map)['sql'] as String).contains(
                'BEGIN EXCLUSIVE',
              ),
        ),
        isTrue,
      );
      await expectLater(captured!.query('SELECT 1', []), throwsStateError);
      first.invalidate();
      second.invalidate();
      await Future.wait([first.closed, second.closed]);
    },
  );
  test(
    'callback lease expires during commit ACK and queued close waits',
    () async {
      final connection = await open();
      commitEntered = Completer<void>();
      commitRelease = Completer<void>();
      AdminQualificationSqliteExecutor? captured;
      final transaction = connection.transaction((txn) async {
        captured = txn;
        return txn.execute('DELETE FROM test', []);
      });
      await commitEntered!.future;
      await expectLater(captured!.query('SELECT 1', []), throwsStateError);
      await expectLater(
        captured!.execute('DELETE FROM test', []),
        throwsStateError,
      );
      final queued = connection.query('SELECT 1', []);
      final queuedCheck = expectLater(queued, throwsStateError);
      connection.invalidate();
      expect(calls.where((c) => c.method == 'closeDatabase'), isEmpty);
      final failureCheck = expectLater(transaction, throwsStateError);
      commitRelease!.complete();
      await Future.wait([queuedCheck, failureCheck, connection.closed]);
      expect(calls.last.method, 'closeDatabase');
      await expectLater(connection.query('SELECT 1', []), throwsStateError);
    },
  );
  test('invalidation during callback await rolls back before commit', () async {
    final connection = await open();
    final sqlFinished = Completer<void>();
    final callbackRelease = Completer<void>();
    final transaction = connection.transaction((executor) async {
      final result = await executor.execute('UPDATE test SET value = ?', [1]);
      sqlFinished.complete();
      await callbackRelease.future;
      return result;
    });
    final failure = expectLater(transaction, throwsStateError);
    await sqlFinished.future;
    connection.invalidate();
    expect(calls.where((call) => call.method == 'closeDatabase'), isEmpty);
    callbackRelease.complete();
    await failure;
    await connection.closed;
    final control = calls
        .where((call) => call.method == 'execute')
        .map((call) => (call.arguments as Map)['sql']);
    expect(control, contains('ROLLBACK'));
    expect(control, isNot(contains('COMMIT')));
    expect(calls.last.method, 'closeDatabase');
  });
  test('unknown commit invalidates all users and closes', () async {
    final connection = await open();
    loseCommit = true;
    await expectLater(
      connection.transaction(
        (txn) => txn.execute('INSERT INTO test VALUES (?)', [1]),
      ),
      throwsA(
        isA<DatabaseException>().having(
          (error) => error.toString(),
          'commit acknowledgement',
          contains('commit acknowledgement unavailable'),
        ),
      ),
    );
    await connection.closed;
    await expectLater(connection.query('SELECT 1', []), throwsStateError);
    expect(calls.last.method, 'closeDatabase');
  });
  test('outer connection cannot be used during callback', () async {
    final connection = await open();
    await expectLater(
      connection.transaction((txn) => connection.query('SELECT 1', [])),
      throwsStateError,
    );
    await connection.closed;
  });
  test(
    'inherited zone cannot reuse exclusive lease after callback ends',
    () async {
      final connection = await open();
      final release = Completer<void>();
      late Future<void> deferred;
      await connection.exclusive(() async {
        deferred = release.future.then((_) async {
          await expectLater(
            connection.query('SELECT late', []),
            throwsStateError,
          );
        });
      });
      final before = calls.length;
      release.complete();
      await deferred;
      expect(calls.length, before);
      expect(await connection.query('SELECT fresh', []), [
        {'value': 1},
      ]);
      connection.invalidate();
      await connection.closed;
    },
  );
  test(
    'core CAS receives affected rows through native update binding',
    () async {
      final connection = await open();
      emulateCas = true;
      final store = SqliteAdminSavedQualificationPhotoPendingStore(connection);
      const key =
          'sko.admin.qualification.photos.pending.v1.'
          '00000000-0000-0000-0000-000000000001.'
          '00000000-0000-0000-0000-000000000002';
      expect(await store.compareAndSet(key, null, '{"revision":1}'), isTrue);
      expect(await store.compareAndSet(key, null, '{"revision":2}'), isFalse);
      expect(
        await store.compareAndSet(key, '{"revision":0}', '{"revision":2}'),
        isFalse,
      );
      expect(
        await store.compareAndSet(key, '{"revision":1}', '{"revision":2}'),
        isTrue,
      );
      expect(await store.read(key), '{"revision":2}');
      expect(await store.compareAndSet(key, '{"revision":2}', null), isTrue);
      expect(await store.read(key), isNull);
      connection.invalidate();
      await connection.closed;
    },
  );
  test('manual transaction SQL is refused', () async {
    final connection = await open();
    await expectLater(
      connection.execute('BEGIN IMMEDIATE', []),
      throwsArgumentError,
    );
    connection.invalidate();
    await connection.closed;
  });
  test(
    'wrong namespace, symlink root and sidecar rejected before native open',
    () async {
      await expectLater(
        SqfliteAdminQualificationConnection.open(
          canonicalPrivateSupportRoot: root.path,
          databasePath: '${root.path}/other.sqlite3',
        ),
        throwsStateError,
      );
      final link = Link('${root.path}/root-link');
      await link.create(root.path);
      await expectLater(
        SqfliteAdminQualificationConnection.open(
          canonicalPrivateSupportRoot: link.path,
          databasePath:
              '${link.path}/sko-qualification-photo-pending-v1.sqlite3',
        ),
        throwsStateError,
      );
      await Link('${root.path}/sko-qualification-photo-pending-v1.sqlite3-wal')
          .create('${root.path}/elsewhere');
      await expectLater(open(), throwsStateError);
      expect(calls.where((c) => c.method == 'openDatabase'), isEmpty);
    },
  );
}
