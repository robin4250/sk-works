import 'dart:async';
import 'dart:io';

import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_store_factory.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_sqlite_pending_store.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '00000000-0000-0000-0000-000000000002';
const target = '00000000-0000-0000-0000-000000000003';
const key = 'sko.admin.qualification.photos.pending.v1.$actor.$company';
const valid = AdminSavedQualificationPhotoSubmissionScope(
  actorId: actor,
  companyId: company,
  targetId: target,
  active: true,
);
const changed = AdminSavedQualificationPhotoSubmissionScope(
  actorId: target,
  companyId: company,
  targetId: target,
  active: true,
);
int checks = 0;
void check(bool value, String label) {
  if (!value) {
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
  throw StateError('Expected refusal: $label');
}

class Connection implements AdminQualificationSqliteConnection {
  bool invalid = false;
  int calls = 0;
  bool failTransaction = false;
  @override
  void invalidate() {
    invalid = true;
  }

  void live() {
    if (invalid) {
      throw StateError('invalid connection');
    }
    calls++;
  }

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) async {
    live();
    return operation();
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(AdminQualificationSqliteExecutor) operation,
  ) async {
    live();
    if (failTransaction) {
      throw StateError('unknown transaction');
    }
    return operation(this);
  }

  @override
  Future<int> execute(String sql, List<Object?> parameters) async {
    live();
    return 0;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    live();
    if (sql.startsWith('SELECT')) {
      return [];
    }
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
    throw StateError(sql);
  }
}

class Fixture {
  final changes =
      StreamController<AdminSavedQualificationPhotoSubmissionScope>.broadcast(
        sync: true,
      );
  AdminSavedQualificationPhotoSubmissionScope scope = valid;
  String selected = '/private/app/support';
  String canonical = '/private/app/support';
  Connection connection = Connection();
  int opened = 0;
  String? openedPath;
  Completer<void>? gate;
  late final factory = make();
  AdminQualificationPhotoStoreFactory make({
    String root = '/private/app/support',
  }) => AdminQualificationPhotoStoreFactory(
    canonicalSupportRoot: root,
    supportRoot: () async => selected,
    canonicalizeRoot: (_) async => canonical,
    open: (path) async {
      opened++;
      openedPath = path;
      await gate?.future;
      return connection;
    },
    scope: () => scope,
    scopeChanges: changes.stream,
  );
  Future<void> close() async {
    await factory.dispose();
    await changes.close();
  }
}

Future<void> run(Future<void> Function(Fixture) body) async {
  final f = Fixture();
  try {
    await body(f);
  } finally {
    await f.close();
  }
}

Future<void> main() async {
  await run((f) async {
    final both = await Future.wait([f.factory.create(), f.factory.create()]);
    check(identical(both.first, both.last), 'one factory creates one store');
    check(f.opened == 1, 'one connection open');
    check(
      f.openedPath ==
          '/private/app/support/sko-qualification-photo-pending-v1.sqlite3',
      'fixed namespace',
    );
    check(await both.first.read(key) == null, 'bound key can read');
    final calls = f.connection.calls;
    await refuses(() => both.first.read('$key-other'), 'other key refused');
    check(f.connection.calls == calls, 'key mismatch sends no SQL');
    f.scope = changed;
    f.changes.add(changed);
    check(f.connection.invalid, 'scope change invalidates connection');
    f.scope = valid;
    f.changes.add(valid);
    await refuses(() => both.first.read(key), 'scope ABA sticky');
    await refuses(() => f.factory.create(), 'scope ABA cannot reopen');
  });
  for (final path in [
    'relative',
    '/',
    '/private/app/support/',
    '/private/../app',
    '/private//app',
    '/private/./app',
    '/private\\app',
    '/private\u0000app',
  ]) {
    await run((f) async {
      await refuses(() async => f.make(root: path), 'invalid root $path');
      check(f.opened == 0, 'invalid root no opener');
    });
  }
  await run((f) async {
    f.selected = '/other/support';
    await refuses(() => f.factory.create(), 'provider identity mismatch');
    check(f.opened == 0, 'different provider no open');
  });
  await run((f) async {
    f.canonical = '/actual/symlink/root';
    await refuses(() => f.factory.create(), 'canonical identity mismatch');
    check(f.opened == 0, 'symlink mismatch no open');
  });
  await run((f) async {
    f.gate = Completer<void>();
    final opening = refuses(
      () => f.factory.create(),
      'late open after scope change',
    );
    await Future<void>.delayed(Duration.zero);
    f.scope = changed;
    f.changes.add(changed);
    f.gate!.complete();
    await opening;
    check(f.connection.invalid, 'late connection invalidated');
  });
  await run((f) async {
    final store = await f.factory.create();
    f.connection.failTransaction = true;
    await refuses(
      () => store.compareAndSet(key, null, '{}'),
      'unknown transaction',
    );
    check(f.connection.invalid, 'unknown transaction invalidates raw');
    await refuses(() => store.read(key), 'old store invalid');
    final second = f.make();
    try {
      await refuses(
        () => second.create(),
        'raw connection reuse across factory',
      );
    } finally {
      await second.dispose();
    }
  });
  await run((f) async {
    final first = await f.factory.create();
    await f.factory.dispose();
    await refuses(() => first.read(key), 'disposed store no use');
    f.connection = Connection();
    final fresh = f.make();
    try {
      check(
        await (await fresh.create()).read(key) == null,
        'new factory with fresh connection allowed',
      );
    } finally {
      await fresh.dispose();
    }
  });
  await run((f) async {
    final store = await f.factory.create();
    f.changes.addError(StateError('scope stream failed'));
    await refuses(() => store.read(key), 'stream error revokes');
  });
  stdout.writeln(
    'PASS $checks factory assertions: fixed path identity, namespace, scope ABA, async open, fresh connection, invalidated reuse refusal',
  );
}
