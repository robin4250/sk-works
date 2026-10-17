import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'company_common_allowance_repository.dart';

abstract interface class CompanyCommonAllowancePendingStore {
  Future<CompanyCommonAllowancePending?> read(String actorId, String companyId);
  Future<void> write(CompanyCommonAllowancePending pending);
  Future<void> clear(CompanyCommonAllowancePending pending);
}

/// An unresolved command is kept in the application's private support folder.
/// It is never shared across accounts, uploaded, or automatically resent.
class FileCompanyCommonAllowancePendingStore implements CompanyCommonAllowancePendingStore {
  FileCompanyCommonAllowancePendingStore({required this.currentActor, Future<Directory> Function()? directory}) : directory = directory ?? getApplicationSupportDirectory;
  final String? Function() currentActor;
  final Future<Directory> Function() directory;
  static final Map<String, Future<void>> _queues = {};
  Future<T> _locked<T>(String actor, String company, Future<T> Function(File) action) async {
    if (actor.isEmpty || company.isEmpty || currentActor() != actor) throw StateError('ログイン情報が変更されました');
    final root = await directory();
    final folder = Directory('${root.path}/company-common-allowance-pending-v1');
    await folder.create(recursive: true);
    final name = sha256.convert(utf8.encode(jsonEncode([actor, company]))).toString();
    final file = File('${folder.path}/$name.json');
    final previous = _queues[file.path] ?? Future<void>.value();
    final complete = Completer<T>();
    final next = previous.then((_) async {
      RandomAccessFile? lock;
      try {
        lock = await File('${file.path}.lock').open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        if (currentActor() != actor) throw StateError('ログイン情報が変更されました');
        complete.complete(await action(file));
      } catch (error, stack) {
        complete.completeError(error, stack);
      } finally {
        await lock?.close();
      }
    });
    _queues[file.path] = next;
    next.whenComplete(() { if (identical(_queues[file.path], next)) _queues.remove(file.path); });
    return complete.future;
  }
  Future<CompanyCommonAllowancePending?> _read(File file, String actor, String company) async {
    final temporary = File('${file.path}.tmp');
    if (!await file.exists() && await temporary.exists()) await temporary.rename(file.path);
    if (!await file.exists()) return null;
    final pending = CompanyCommonAllowancePending.parse(jsonDecode(await file.readAsString()));
    if (pending.actorId != actor || pending.companyId != company) throw const FormatException('保存確認記録の会社を確認できません');
    return pending;
  }
  @override Future<CompanyCommonAllowancePending?> read(String actorId, String companyId) => _locked(actorId, companyId, (file) => _read(file, actorId, companyId));
  @override Future<void> write(CompanyCommonAllowancePending pending) => _locked(pending.actorId, pending.companyId, (file) async {
    if (await _read(file, pending.actorId, pending.companyId) != null) throw StateError('先の保存結果を確認してください');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(pending.toJson()), flush: true);
    await temporary.rename(file.path);
  });
  @override Future<void> clear(CompanyCommonAllowancePending pending) => _locked(pending.actorId, pending.companyId, (file) async {
    final old = await _read(file, pending.actorId, pending.companyId);
    if (old == null || !commonAllowanceEqual(old.toJson(), pending.toJson())) throw StateError('保存確認記録が一致しません');
    await file.delete();
  });
}
