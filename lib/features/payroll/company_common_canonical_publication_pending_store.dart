import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'company_common_canonical_publication_command.dart';

class CommonPayrollCanonicalPublicationPending {
  CommonPayrollCanonicalPublicationPending({required this.actorId, required this.command}) {
    if (!canonicalPublicationUuid(actorId)) {
      throw const FormatException('給与適用の本人情報を確認できません');
    }
  }
  static const kind = 'company_common_payroll_publish_v2';
  final String actorId;
  final CommonPayrollCanonicalPublicationCommand command;
  String get companyId => command.companyId;
  Map<String, dynamic> toJson() => {
    'schema': 1, 'kind': kind, 'actor_id': actorId,
    'company_id': companyId, 'request_id': command.requestId,
    'command': command.params,
  };
  factory CommonPayrollCanonicalPublicationPending.parse(Object? raw) {
    const keys = {'schema', 'kind', 'actor_id', 'company_id', 'request_id', 'command'};
    if (raw is! Map || raw.length != keys.length || !keys.every(raw.containsKey) ||
        raw['schema'] != 1 || raw['kind'] != kind ||
        !canonicalPublicationUuid(raw['actor_id'])) {
      throw const FormatException('給与適用の確認記録を読み取れません');
    }
    final command = CommonPayrollCanonicalPublicationCommand.fromParams(raw['command']);
    if (raw['company_id'] != command.companyId || raw['request_id'] != command.requestId) {
      throw const FormatException('給与適用の確認記録が一致しません');
    }
    return CommonPayrollCanonicalPublicationPending(
      actorId: raw['actor_id'] as String, command: command,
    );
  }
}

abstract interface class CommonPayrollCanonicalPublicationPendingStore {
  Future<CommonPayrollCanonicalPublicationPending?> read(String actorId, String companyId);
  Future<void> write(CommonPayrollCanonicalPublicationPending pending);
  Future<void> clear(CommonPayrollCanonicalPublicationPending pending);
}

/// Different type, directory and schema from registration/save pending records.
/// No network dependency or automatic resend; corrupt/unknown records fail closed.
class FileCommonPayrollCanonicalPublicationPendingStore
    implements CommonPayrollCanonicalPublicationPendingStore {
  FileCommonPayrollCanonicalPublicationPendingStore({
    required this.currentActor, Future<Directory> Function()? directory,
  }) : directory = directory ?? getApplicationSupportDirectory;
  final String? Function() currentActor;
  final Future<Directory> Function() directory;
  static final Map<String, Future<void>> _queues = {};

  void _actor(String actor) {
    if (!canonicalPublicationUuid(actor) || currentActor() != actor) {
      throw StateError('ログイン情報が変更されました');
    }
  }
  Future<T> _locked<T>(String actor, String company, Future<T> Function(File) action) async {
    _actor(actor);
    if (!canonicalPublicationUuid(company)) throw const FormatException('会社を確認できません');
    final root = await directory();
    _actor(actor);
    final folder = Directory('${root.path}/company-common-payroll-publication-pending-v2');
    await folder.create(recursive: true);
    final name = sha256.convert(utf8.encode(jsonEncode([actor, company]))).toString();
    final file = File('${folder.path}/$name.json');
    final complete = Completer<T>();
    final previous = _queues[file.path] ?? Future<void>.value();
    final next = previous.then((_) async {
      RandomAccessFile? lock;
      try {
        lock = await File('${file.path}.lock').open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        _actor(actor);
        final result = await action(file);
        _actor(actor);
        complete.complete(result);
      } catch (error, stack) {
        complete.completeError(error, stack);
      } finally {
        try { await lock?.close(); } catch (_) { /* Result already retained. */ }
      }
    });
    _queues[file.path] = next;
    unawaited(next.whenComplete(() {
      if (identical(_queues[file.path], next)) _queues.remove(file.path);
    }));
    return complete.future;
  }

  Future<CommonPayrollCanonicalPublicationPending?> _read(File file, String actor, String company) async {
    final temporary = File('${file.path}.tmp');
    if (await file.exists() && await temporary.exists()) {
      throw StateError('給与適用の確認記録が重複しています。結果を確認してください');
    }
    if (!await file.exists() && await temporary.exists()) await temporary.rename(file.path);
    if (!await file.exists()) return null;
    if (await file.length() > 262144) throw const FormatException('給与適用の確認記録が大きすぎます');
    final pending = CommonPayrollCanonicalPublicationPending.parse(jsonDecode(await file.readAsString()));
    if (pending.actorId != actor || pending.companyId != company) {
      throw const FormatException('給与適用の確認記録の所有者が一致しません');
    }
    return pending;
  }
  @override Future<CommonPayrollCanonicalPublicationPending?> read(String actorId, String companyId) =>
      _locked(actorId, companyId, (file) => _read(file, actorId, companyId));
  @override Future<void> write(CommonPayrollCanonicalPublicationPending pending) =>
      _locked(pending.actorId, pending.companyId, (file) async {
        if (await _read(file, pending.actorId, pending.companyId) != null) {
          throw StateError('先の給与適用結果を確認してください');
        }
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(canonicalPublicationJson(pending.toJson()), flush: true);
        await temporary.rename(file.path);
      });
  @override Future<void> clear(CommonPayrollCanonicalPublicationPending pending) =>
      _locked(pending.actorId, pending.companyId, (file) async {
        final old = await _read(file, pending.actorId, pending.companyId);
        if (old == null || canonicalPublicationJson(old.toJson()) != canonicalPublicationJson(pending.toJson())) {
          throw StateError('給与適用の確認記録が一致しません');
        }
        await file.delete();
      });
}
