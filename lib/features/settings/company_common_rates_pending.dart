import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/supabase_backend.dart';
import 'company_common_rates_repository.dart';

abstract class CompanyCommonRatesPendingStore {
  String actorId();
  Future<CompanyCommonRatesRequest?> read(String companyId);
  Future<void> write(CompanyCommonRatesRequest request);
  Future<void> clear(CompanyCommonRatesRequest request);
}

/// Native app-support storage, isolated by actor AND company. No credentials,
/// employee data or other pending namespaces are read/overwritten here.
class FileCompanyCommonRatesPendingStore implements CompanyCommonRatesPendingStore {
  FileCompanyCommonRatesPendingStore({String? Function()? currentActor,
    Future<Directory> Function()? directory})
    : _currentActor = currentActor ?? (() => SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentUser?.id : null),
      _directory = directory ?? getApplicationSupportDirectory;
  final String? Function() _currentActor;
  final Future<Directory> Function() _directory;
  String? _boundActor;
  static final Map<String, Future<void>> _locks = {};
  @override
  String actorId() {
    final value = _currentActor();
    if (value == null) throw StateError('保存確認する利用者を確認できません');
    final actor = commonRatesUuid(value);
    if (_boundActor != null && _boundActor != actor) throw StateError('利用者が変わりました');
    _boundActor = actor;
    return actor;
  }
  String _key(String companyId) => jsonEncode([actorId(), commonRatesUuid(companyId)]);
  Future<File> _file(String key) async {
    final root = await _directory();
    final directory = Directory('${root.path}/sko-company-common-rates-pending-v1');
    await directory.create(recursive: true);
    return File('${directory.path}/${sha256.convert(utf8.encode(key))}.json');
  }
  Future<T> _locked<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key] ?? Future<void>.value();
    final done = Completer<void>();
    _locks[key] = done.future;
    await previous;
    RandomAccessFile? lock;
    try {
      final file = await _file(key);
      lock = await File('${file.path}.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      return await action();
    } finally {
      try { await lock?.close(); }
      finally {
        done.complete();
        if (identical(_locks[key], done.future)) _locks.remove(key);
      }
    }
  }
  Future<File> _record(String key, String companyId) async {
    final file = await _file(key);
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) {
      if (await file.exists()) throw const FormatException('保存確認情報が競合しています');
      CompanyCommonRatesRequest.parse(jsonDecode(await temporary.readAsString()), companyId, actorId());
      if (_key(companyId) != key) throw StateError('利用者が変わりました');
      await temporary.rename(file.path);
    }
    return file;
  }
  @override
  Future<CompanyCommonRatesRequest?> read(String companyId) async {
    final key = _key(companyId);
    return _locked(key, () async {
      final file = await _record(key, companyId);
      if (_key(companyId) != key) throw StateError('利用者が変わりました');
      if (!await file.exists()) return null;
      final request = CompanyCommonRatesRequest.parse(jsonDecode(await file.readAsString()), companyId, actorId());
      if (_key(companyId) != key) throw StateError('利用者が変わりました');
      return request;
    });
  }
  @override
  Future<void> write(CompanyCommonRatesRequest request) async {
    final key = _key(request.companyId);
    if (request.actorId != actorId()) throw StateError('保存する利用者が違います');
    return _locked(key, () async {
      final file = await _record(key, request.companyId);
      if (_key(request.companyId) != key || await file.exists()) throw StateError('先の保存結果を確認してください');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(request.toJson()), flush: true);
      if (_key(request.companyId) != key) throw StateError('利用者が変わりました');
      await temporary.rename(file.path);
      if (_key(request.companyId) != key ||
          !commonRatesEqual(jsonDecode(await file.readAsString()), request.toJson())) {
        throw StateError('保存確認情報を記録できませんでした');
      }
    });
  }
  @override
  Future<void> clear(CompanyCommonRatesRequest request) async {
    final key = _key(request.companyId);
    return _locked(key, () async {
      final file = await _record(key, request.companyId);
      if (!await file.exists()) throw StateError('保存確認情報がありません');
      final raw = jsonDecode(await file.readAsString());
      if (_key(request.companyId) != key || request.actorId != actorId() || !commonRatesEqual(raw, request.toJson())) {
        throw StateError('保存確認する操作が変わりました');
      }
      await file.delete();
    });
  }
}

