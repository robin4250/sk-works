import 'dart:convert';

import 'admin_saved_qualification_photo_submission_repository.dart';

/// A single local SQLite connection. No application/path/plugin adapter is wired.
/// [exclusive] must serialize all access to this connection, including readers,
/// until its callback completes. Independent connections use SQLite file locks.
abstract interface class AdminQualificationSqliteConnection {
  /// Immediately revoke this connection for all users after an uncertain write.
  /// The adapter must refuse queued/new SQL; recovery opens a fresh connection.
  void invalidate();
  Future<T> exclusive<T>(Future<T> Function() operation);
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  );
  Future<int> execute(String sql, List<Object?> parameters);
}

/// Dedicated local recovery DB only. It must not share a connection with product
/// transactions. The mobile adapter must open one canonical private absolute path.
class SqliteAdminSavedQualificationPhotoPendingStore
    implements AdminSavedQualificationPhotoPendingStore {
  SqliteAdminSavedQualificationPhotoPendingStore(this.connection);
  final AdminQualificationSqliteConnection connection;
  bool _ready = false;
  bool _failed = false;

  static final _key = RegExp(
    r'^sko\.admin\.qualification\.photos\.pending\.v1\.'
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.'
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _table = 'qualification_photo_pending_v1';

  /// JSON has deterministic object-key ordering; array ordering is retained.
  /// The repository's strict command parser still owns scope and schema checks.
  static String canonicalJson(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Pending command must be a JSON object');
    }
    Object? normalize(Object? node) {
      if (node is Map<String, dynamic>) {
        final keys = node.keys.toList()..sort();
        return {for (final key in keys) key: normalize(node[key])};
      }
      if (node is List) {
        return node.map(normalize).toList();
      }
      if (node == null || node is String || node is bool || node is int) {
        return node;
      }
      if (node is double && node.isFinite) {
        return node;
      }
      throw const FormatException('Unsupported JSON value');
    }

    return jsonEncode(normalize(decoded));
  }

  // Keep exact repository bytes: its durable readback compares the original
  // command string. Only the storage envelope is canonicalized; key order inside
  // command_json is deliberately retained rather than changing the repo contract.
  String _envelope(String raw) {
    canonicalJson(raw);
    return canonicalJson(jsonEncode({'version': 1, 'command_json': raw}));
  }

  void _validate(String key) {
    if (!_key.hasMatch(key)) {
      throw const FormatException('Unexpected pending store namespace');
    }
  }

  Future<Object?> _pragma(String name) async {
    final rows = await connection.query('PRAGMA $name', const []);
    if (rows.length != 1 || rows.single.length != 1) {
      throw StateError('Cannot verify SQLite configuration: $name');
    }
    return rows.single.values.single;
  }

  Future<void> _checkConfiguration() async {
    if (await _pragma('journal_mode') != 'wal' ||
        await _pragma('synchronous') != 2 ||
        await _pragma('read_uncommitted') != 0) {
      throw StateError('SQLite durability/isolation configuration unavailable');
    }
  }

  Future<void> _initialize() async {
    if (_failed) {
      throw StateError('Reopen SQLite after an uncertain transaction');
    }
    if (!_ready) {
      await connection.query('PRAGMA journal_mode=WAL', const []);
      await connection.execute('PRAGMA synchronous=FULL', const []);
      await connection.execute('PRAGMA read_uncommitted=OFF', const []);
      await _checkConfiguration();
      await connection.execute(
        'CREATE TABLE IF NOT EXISTS $_table '
        '(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
        const [],
      );
      _ready = true;
    }
    await _checkConfiguration();
  }

  Future<String?> _read(String key) async {
    final rows = await connection.query(
      'SELECT value FROM $_table WHERE key = ?',
      [key],
    );
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length != 1 ||
        rows.single.length != 1 ||
        rows.single['value'] is! String) {
      throw StateError('Invalid SQLite pending record');
    }
    final value = rows.single['value']! as String;
    if (canonicalJson(value) != value) {
      throw const FormatException('Noncanonical pending record');
    }
    final envelope = jsonDecode(value) as Map<String, dynamic>;
    if (envelope.length != 2 ||
        envelope['version'] != 1 ||
        envelope['command_json'] is! String) {
      throw const FormatException('Invalid pending envelope');
    }
    final raw = envelope['command_json'] as String;
    canonicalJson(raw);
    return raw;
  }

  @override
  Future<String?> read(String key) => connection.exclusive(() async {
    _validate(key);
    await _initialize();
    return _read(key);
  });

  @override
  Future<bool> compareAndSet(
    String key,
    String? expected,
    String? replacement,
  ) => connection.exclusive(() async {
    _validate(key);
    final before = expected == null ? null : _envelope(expected);
    final after = replacement == null ? null : _envelope(replacement);
    await _initialize();
    bool committed = false;
    try {
      await connection.execute('BEGIN IMMEDIATE', const []);
      int changed;
      if (before == null && after != null) {
        changed = await connection.execute(
          'INSERT INTO $_table (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO NOTHING',
          [key, after],
        );
      } else if (before != null && after != null) {
        changed = await connection.execute(
          'UPDATE $_table SET value = ? WHERE key = ? AND value = ?',
          [after, key, before],
        );
      } else if (before != null) {
        changed = await connection.execute(
          'DELETE FROM $_table WHERE key = ? AND value = ?',
          [key, before],
        );
      } else {
        // Null -> null does not establish ownership and must not grant a send.
        throw ArgumentError('CAS requires a value transition');
      }
      if (changed != 0 && changed != 1) {
        throw StateError('Unexpected SQLite affected-row count');
      }
      await connection.execute('COMMIT', const []);
      committed = true;
      if (changed == 0) {
        return false;
      }
      if (await _read(key) != replacement) {
        throw StateError('Committed pending record readback mismatch');
      }
      return true;
    } catch (error, stack) {
      _failed = true;
      if (!committed) {
        try {
          await connection.execute('ROLLBACK', const []);
        } catch (_) {
          // Preserve the original failure, including an uncertain commit.
        }
      }
      connection.invalidate();
      Error.throwWithStackTrace(error, stack);
    }
  });
}
