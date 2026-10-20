// Real SQLite fixture through a Python stdlib subprocess. No mobile/network data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_sqlite_pending_store.dart';

const key =
    'sko.admin.qualification.photos.pending.v1.'
    '00000000-0000-0000-0000-000000000001.'
    '00000000-0000-0000-0000-000000000002';
int checks = 0;
void check(bool ok, String label) {
  if (!ok) {
    throw StateError(label);
  }
  checks++;
}

Future<void> refuses(Future<Object?> Function() call, String label) async {
  try {
    await call();
  } catch (_) {
    checks++;
    return;
  }
  throw StateError('Expected failure: $label');
}

class Connection implements AdminQualificationSqliteConnection {
  Connection._(this.process) {
    lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    process.stderr.drain<void>();
  }
  final Process process;
  late final StreamIterator<String> lines;
  Future<void> tail = Future.value();
  String? kill;
  String? killSql;
  bool invalidated = false;
  bool transactionActive = false;
  @override
  void invalidate() {
    invalidated = true;
  }

  bool lostCommitAck = false;
  bool lostBeginAck = false;
  Completer<void>? beginEntered;
  Completer<void>? releaseBegin;
  final executed = <String>[];
  Future<void> Function()? afterCommit;
  static Future<Connection> open(String root) async => Connection._(
    await Process.start('python3', [
      'tool/qualification_photo_sqlite_fixture.py',
      root,
      '$root/pending.sqlite3',
    ]),
  );
  @override
  Future<T> exclusive<T>(Future<T> Function() operation) async {
    final previous = tail;
    final done = Completer<void>();
    tail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  Future<Map<String, dynamic>> request(
    String sql,
    List<Object?> parameters,
  ) async {
    if (invalidated) {
      throw StateError('Connection invalidated');
    }
    executed.add(sql);
    process.stdin.writeln(
      jsonEncode({
        'sql': sql,
        'parameters': parameters,
        if (sql == killSql) 'kill': kill,
      }),
    );
    await process.stdin.flush();
    if (!await lines.moveNext()) {
      throw StateError('Fixture process terminated');
    }
    final result = jsonDecode(lines.current) as Map<String, dynamic>;
    if (result.containsKey('error')) {
      throw StateError(result['error'] as String);
    }
    if (sql == 'BEGIN IMMEDIATE' && lostBeginAck) {
      lostBeginAck = false;
      beginEntered?.complete();
      await releaseBegin?.future;
      throw StateError('Synthetic begin response loss');
    }
    if (sql == 'COMMIT' && afterCommit != null) {
      await afterCommit!();
    }
    if (sql == 'COMMIT' && lostCommitAck) {
      lostCommitAck = false;
      throw StateError('Synthetic commit response loss');
    }
    return result;
  }

  @override
  Future<int> execute(String sql, List<Object?> parameters) async {
    if (transactionActive) {
      throw StateError('Outer connection used inside transaction');
    }
    return (await request(sql, parameters))['changed'] as int;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    if (transactionActive) {
      throw StateError('Outer connection used inside transaction');
    }
    return ((await request(sql, parameters))['rows'] as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(AdminQualificationSqliteExecutor transaction) operation,
  ) async {
    // Fixture bridge owns transactions; a mobile adapter instead calls the
    // plugin's transaction API and wraps only its supplied Transaction object.
    if (transactionActive) {
      throw StateError('Nested transaction');
    }
    final executor = _TransactionExecutor(this);
    transactionActive = true;
    try {
      await request('BEGIN IMMEDIATE', const []);
      final result = await operation(executor);
      await request('COMMIT', const []);
      return result;
    } catch (error, stack) {
      try {
        await request('ROLLBACK', const []);
      } catch (_) {
        // Keep original error, including unknown BEGIN or COMMIT outcomes.
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      executor.active = false;
      transactionActive = false;
    }
  }

  Future<void> close() async {
    await process.stdin.close();
    await process.exitCode;
    await lines.cancel();
  }
}

class _TransactionExecutor implements AdminQualificationSqliteExecutor {
  _TransactionExecutor(this.connection);
  final Connection connection;
  bool active = true;
  void checkActive() {
    if (!active || !connection.transactionActive) {
      throw StateError('Transaction executor expired');
    }
  }

  @override
  Future<int> execute(String sql, List<Object?> parameters) async {
    checkActive();
    return (await connection.request(sql, parameters))['changed'] as int;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    checkActive();
    return ((await connection.request(sql, parameters))['rows'] as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
  }
}

Future<void> main() async {
  final directory = await Directory('/tmp')
      .createTemp('sko-qualification-sqlite-');
  final connections = <Connection>[];
  Future<Connection> open() async {
    final connection = await Connection.open(directory.path);
    connections.add(connection);
    return connection;
  }

  try {
    final a = await open();
    final b = await open();
    final first = SqliteAdminSavedQualificationPhotoPendingStore(a);
    final second = SqliteAdminSavedQualificationPhotoPendingStore(b);
    check(await first.read(key) == null, 'empty real database');
    check(await second.read(key) == null, 'second process initialized');
    const original = '{"z":1,"a":{"two":2,"one":1},"paths":["b","a"]}';
    const next = '{"revision":2}';
    check(
      SqliteAdminSavedQualificationPhotoPendingStore.canonicalJson(original) ==
          '{"a":{"one":1,"two":2},"paths":["b","a"],"z":1}',
      'canonical objects retain array order',
    );
    final insert = await Future.wait([
      first.compareAndSet(key, null, original),
      second.compareAndSet(key, null, next),
    ]);
    check(
      insert.where((v) => v).length == 1,
      'two processes insert one winner',
    );
    final current = await first.read(key);
    check(
      current == (insert.first ? original : next),
      'exact repository bytes read back',
    );
    final update = await Future.wait([
      first.compareAndSet(key, current, '{"revision":3}'),
      second.compareAndSet(key, current, '{"revision":4}'),
    ]);
    check(
      update.where((v) => v).length == 1,
      'two processes update one winner',
    );
    final updated = await second.read(key);
    final deletion = await Future.wait([
      first.compareAndSet(key, updated, null),
      second.compareAndSet(key, updated, null),
    ]);
    check(
      deletion.where((v) => v).length == 1,
      'two processes delete one winner',
    );
    check(await first.read(key) == null, 'delete readback');
    await refuses(
      () async =>
          SqliteAdminSavedQualificationPhotoPendingStore(await open())
              .compareAndSet(key, null, null),
      'null ownership transition',
    );
    await refuses(
      () => first.compareAndSet('other', null, '{}'),
      'foreign namespace',
    );
    await refuses(
      () => first.compareAndSet(key, null, '[]'),
      'nonobject command',
    );
    check(await first.compareAndSet(key, null, original), 'restore baseline');
    a.lostCommitAck = true;
    await refuses(
      () => first.compareAndSet(key, original, next),
      'lost commit acknowledgement throws',
    );
    await refuses(
      () => first.read(key),
      'uncertain store requires new connection',
    );
    await refuses(
      () => SqliteAdminSavedQualificationPhotoPendingStore(a).read(key),
      'new Store cannot reuse invalid connection',
    );
    check(
      await second.read(key) == next,
      'uncertain commit durable on other process',
    );
    // Kill before COMMIT rolls back the UPDATE; kill after it retains the UPDATE.
    for (final timing in ['before', 'after']) {
      final process = await open();
      final store = SqliteAdminSavedQualificationPhotoPendingStore(process);
      final expected = await store.read(key);
      process.killSql = 'COMMIT';
      process.kill = timing;
      final replacement = jsonEncode({'kill': timing});
      await refuses(
        () => store.compareAndSet(key, expected, replacement),
        'kill $timing commit throws',
      );
      check(
        await process.process.exitCode == (timing == 'before' ? 71 : 72),
        'actual subprocess kill boundary',
      );
      final restarted = SqliteAdminSavedQualificationPhotoPendingStore(
        await open(),
      );
      check(
        await restarted.read(key) ==
            (timing == 'before' ? expected : replacement),
        'restart $timing commit recovery',
      );
    }
    // Separate store objects sharing a connection still use its exclusive gate.
    final shared = await open();
    final sharedOne = SqliteAdminSavedQualificationPhotoPendingStore(shared);
    final sharedTwo = SqliteAdminSavedQualificationPhotoPendingStore(shared);
    final sharedBefore = await sharedOne.read(key);
    final sharedResults = await Future.wait([
      sharedOne.compareAndSet(key, sharedBefore, '{"shared":1}'),
      sharedTwo.compareAndSet(key, sharedBefore, '{"shared":2}'),
    ]);
    check(
      sharedResults.where((v) => v).length == 1,
      'same connection stores serialize transactions',
    );
    // A competing committed change between commit and readback fails closed.
    final racing = await open();
    final racingStore = SqliteAdminSavedQualificationPhotoPendingStore(racing);
    final racingBefore = await racingStore.read(key);
    racing.afterCommit = () async {
      await b.execute(
        'UPDATE qualification_photo_pending_v1 SET value = ? WHERE key = ?',
        [
          SqliteAdminSavedQualificationPhotoPendingStore.canonicalJson(
            jsonEncode({'version': 1, 'command_json': '{"competing":true}'}),
          ),
          key,
        ],
      );
    };
    await refuses(
      () => racingStore.compareAndSet(key, racingBefore, '{"attempt":1}'),
      'commit readback mismatch throws',
    );
    check(
      await second.read(key) == '{"competing":true}',
      'competing committed command not overwritten',
    );
    // A real outstanding writer must not be treated as a false CAS success.
    await b.execute('BEGIN IMMEDIATE', []);
    final blocked = SqliteAdminSavedQualificationPhotoPendingStore(
      await open(),
    );
    await refuses(
      () => blocked.compareAndSet(key, '{"competing":true}', '{}'),
      'real SQLITE_BUSY throws',
    );
    await b.execute('ROLLBACK', []);
    // BEGIN succeeded in SQLite, but its acknowledgement is unavailable. The
    // transaction owner must rollback/invalidate before releasing queued users.
    final uncertainBegin = await open();
    final beginStore = SqliteAdminSavedQualificationPhotoPendingStore(
      uncertainBegin,
    );
    final otherStore = SqliteAdminSavedQualificationPhotoPendingStore(
      uncertainBegin,
    );
    final beginBefore = await beginStore.read(key);
    uncertainBegin.lostBeginAck = true;
    uncertainBegin.beginEntered = Completer<void>();
    uncertainBegin.releaseBegin = Completer<void>();
    final failedBegin = beginStore.compareAndSet(
      key,
      beginBefore,
      '{"must_not_write":true}',
    );
    final failureCheck = refuses(() async {
      try {
        await failedBegin;
      } catch (error) {
        check(
          error.toString().contains('Synthetic begin response loss'),
          'original BEGIN error retained',
        );
        rethrow;
      }
      return null;
    }, 'lost BEGIN acknowledgement throws');
    await uncertainBegin.beginEntered!.future;
    final queuedRead = refuses(
      () => otherStore.read(key),
      'queued other Store read rejected',
    );
    final queuedWrite = refuses(
      () => otherStore.compareAndSet(key, beginBefore, '{}'),
      'queued other Store mutation rejected',
    );
    uncertainBegin.releaseBegin!.complete();
    await Future.wait([failureCheck, queuedRead, queuedWrite]);
    check(
      uncertainBegin.invalidated,
      'BEGIN uncertainty invalidates connection',
    );
    check(
      uncertainBegin.executed.last == 'ROLLBACK',
      'rollback attempted before releasing queue',
    );
    check(
      !uncertainBegin.executed.any((sql) => sql.startsWith('UPDATE')),
      'no mutation after unknown BEGIN',
    );
    await refuses(
      () =>
          SqliteAdminSavedQualificationPhotoPendingStore(uncertainBegin)
              .read(key),
      'fresh Store on old connection refused',
    );
    final beginRecovered = SqliteAdminSavedQualificationPhotoPendingStore(
      await open(),
    );
    check(
      await beginRecovered.read(key) == beginBefore,
      'fresh connection recovers original committed record',
    );
    check(
      await beginRecovered.compareAndSet(
        key,
        beginBefore,
        '{"recovered":true}',
      ),
      'fresh connection can CAS after rollback',
    );
    final owner = await open();
    await refuses(
      () => owner.transaction((transaction) => owner.query('SELECT 1', [])),
      'owner rejects outer connection during callback',
    );
    AdminQualificationSqliteExecutor? expired;
    await owner.transaction((transaction) async {
      expired = transaction;
      check(
        (await transaction.query('SELECT 1 AS value', [])).single['value'] == 1,
        'callback receives working transaction executor',
      );
    });
    await refuses(
      () => expired!.query('SELECT 1', []),
      'executor cannot escape transaction lifetime',
    );
    final gated = await open();
    final gatedStore = SqliteAdminSavedQualificationPhotoPendingStore(gated);
    final gatedBefore = await gatedStore.read(key);
    final commitEntered = Completer<void>();
    final commitRelease = Completer<void>();
    gated.afterCommit = () async {
      commitEntered.complete();
      await commitRelease.future;
    };
    bool completed = false;
    final completion = gatedStore
        .compareAndSet(key, gatedBefore, '{"owner_commit":true}')
        .then((result) {
          completed = true;
          return result;
        });
    await commitEntered.future;
    check(
      !completed,
      'callback result is not store success before transaction Future completes',
    );
    check(
      await second.read(key) == '{"owner_commit":true}',
      'other connection sees actual commit while ack is gated',
    );
    commitRelease.complete();
    check(
      await completion,
      'store succeeds after owner commit Future and readback',
    );
    await b.execute('PRAGMA synchronous=NORMAL', []);
    await refuses(
      () => second.read(key),
      'configuration weakened after initialization',
    );
    await b.execute('PRAGMA synchronous=FULL', []);
    await b.execute('PRAGMA read_uncommitted=ON', []);
    await refuses(
      () => second.read(key),
      'isolation weakened after initialization',
    );
    await b.execute('PRAGMA read_uncommitted=OFF', []);
    await b.execute(
      'UPDATE qualification_photo_pending_v1 SET value = ? WHERE key = ?',
      ['{"version":1, "command_json":"{}"}', key],
    );
    await refuses(
      () => second.read(key),
      'noncanonical stored envelope refused',
    );
    stdout.writeln(
      'PASS $checks real SQLite assertions: process CAS, canonical envelope, commit uncertainty, before/after commit kill and restart, configuration fail closed',
    );
  } finally {
    for (final connection in connections) {
      try {
        await connection.close();
      } catch (_) {
        connection.process.kill();
      }
    }
    await directory.delete(recursive: true);
  }
}
