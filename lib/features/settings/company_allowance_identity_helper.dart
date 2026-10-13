import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/supabase_backend.dart';
import 'company_allowance_identity_repository.dart';

/// Separate actor/company journal; never shares the payroll-rate pending namespace.
class CompanyAllowanceIdentityPending {
  const CompanyAllowanceIdentityPending({required this.companyId, required this.actorId,
    required this.expectedVersion, required this.adoption, required this.slots, required this.stableIds});
  final String companyId;
  final String actorId;
  final int expectedVersion;
  final bool adoption;
  final List<CompanyAllowanceSlot> slots;
  final Map<String, String> stableIds;
  Map<String, dynamic> toJson() => {'company_id': companyId, 'actor_id': actorId,
    'expected_version': expectedVersion, 'adoption': adoption, 'slots': slots.map((s) => s.toJson()).toList(), 'stable_ids': stableIds};
  factory CompanyAllowanceIdentityPending.parse(dynamic raw, String companyId, String actorId) {
    final value = allowanceIdentityObject(raw);
    if (value['company_id'] != companyId || value['actor_id'] != actorId ||
        value['expected_version'] is! int || value['expected_version'] < 0 || value['adoption'] is! bool || value['slots'] is! List || value['stable_ids'] is! Map) {
      throw const FormatException('手当の保存確認情報を読み込めません');
    }
    final slots = (value['slots'] as List).map(CompanyAllowanceSlot.parse).toList();
    if (slots.length != 3 || slots.map((s) => s.slot).toSet().length != 3) {
      throw const FormatException('保存確認する手当が不足しています');
    }
    final ids = Map<String, String>.from(value['stable_ids'] as Map);
    return CompanyAllowanceIdentityPending(companyId: companyId, actorId: actorId,
      expectedVersion: value['expected_version'] as int, adoption: value['adoption'] as bool, slots: slots, stableIds: ids);
  }
  bool matches(Map<String, dynamic> history) {
    if (history['company_id'] != companyId || history['actor_id'] != actorId || history['version'] != expectedVersion + 1 ||
        history['event'] != (adoption ? 'adopt' : 'settings_update') || history['after_value'] is! List) {
      return false;
    }
    final items = (history['after_value'] as List).map(allowanceIdentityObject).toList();
    final active = slots.where((s) => s.active).toList();
    if (items.length != active.length) {
      return false;
    }
    for (final slot in active) {
      final candidates = items.where((item) => item['slot'] == slot.slot).toList();
      if (candidates.length != 1 || !allowanceIdentityEqual(CompanyAllowanceSlot.parse(candidates.single).toJson(), slot.toJson())) {
        return false;
      }
      final stable = stableIds[slot.slot.toString()];
      if (stable != null && candidates.single['id'] != stable) {
        return false;
      }
    }
    return true;
  }
}

abstract class CompanyAllowanceIdentityPendingStore {
  Future<CompanyAllowanceIdentityPending?> read(String companyId);
  Future<void> write(CompanyAllowanceIdentityPending pending);
  Future<void> clear(CompanyAllowanceIdentityPending pending);
  String actorId();
}

class FileCompanyAllowanceIdentityPendingStore implements CompanyAllowanceIdentityPendingStore {
  FileCompanyAllowanceIdentityPendingStore({String? Function()? currentActor, Future<Directory> Function()? directory})
    : _currentActor = currentActor ?? (() => SupabaseBackend.client.auth.currentUser?.id),
      _directory = directory ?? getApplicationSupportDirectory;
  final String? Function() _currentActor;
  final Future<Directory> Function() _directory;
  String? _boundActor;
  static final Map<String, Future<void>> _locks = {};
  @override
  String actorId() {
    final actor = _currentActor();
    if (actor == null || actor.isEmpty || (_boundActor != null && _boundActor != actor)) {
      throw StateError('手当設定の利用者を確認できません');
    }
    _boundActor = actor;
    return actor;
  }
  String _key(String companyId) => jsonEncode([actorId(), companyId]);
  Future<File> _file(String key) async {
    final directory = await _directory();
    final folder = Directory('${directory.path}/company-allowance-identity-pending-v1');
    await folder.create(recursive: true);
    return File('${folder.path}/${sha256.convert(utf8.encode(key))}.json');
  }
  Future<T> _locked<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key] ?? Future<void>.value();
    final done = Completer<void>();
    final current = done.future;
    _locks[key] = current;
    await previous;
    RandomAccessFile? lock;
    try {
      final file = await _file(key);
      lock = await File('${file.path}.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      return await action();
    } finally {
      try {
        await lock?.close();
      } finally {
        done.complete();
        if (identical(_locks[key], current)) {
          _locks.remove(key);
        }
      }
    }
  }
  Future<File> _record(String key, String companyId) async {
    final file = await _file(key);
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) {
      if (await file.exists()) {
        throw const FormatException('手当の保存確認情報が競合しています');
      }
      CompanyAllowanceIdentityPending.parse(jsonDecode(await temporary.readAsString()), companyId, actorId());
      if (key != _key(companyId)) {
        throw StateError('利用者が変わりました');
      }
      await temporary.rename(file.path);
    }
    return file;
  }
  @override
  Future<CompanyAllowanceIdentityPending?> read(String companyId) async {
    final key = _key(companyId);
    return _locked(key, () async {
      final file = await _record(key, companyId);
      if (key != _key(companyId)) {
        throw StateError('利用者が変わりました');
      }
      if (!await file.exists()) {
        return null;
      }
      final result = CompanyAllowanceIdentityPending.parse(jsonDecode(await file.readAsString()), companyId, actorId());
      if (key != _key(companyId)) {
        throw StateError('利用者が変わりました');
      }
      return result;
    });
  }
  @override
  Future<void> write(CompanyAllowanceIdentityPending pending) async {
    final key = _key(pending.companyId);
    if (pending.actorId != actorId()) {
      throw StateError('保存する利用者が違います');
    }
    return _locked(key, () async {
      final file = await _record(key, pending.companyId);
      if (key != _key(pending.companyId) || await file.exists()) {
        throw StateError('先の手当保存を確認してください');
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(pending.toJson()), flush: true);
      if (key != _key(pending.companyId)) {
        throw StateError('利用者が変わりました');
      }
      await temporary.rename(file.path);
      if (key != _key(pending.companyId)) {
        throw StateError('利用者が変わりました');
      }
    });
  }
  @override
  Future<void> clear(CompanyAllowanceIdentityPending pending) async {
    final key = _key(pending.companyId);
    return _locked(key, () async {
      final file = await _record(key, pending.companyId);
      if (!await file.exists()) {
        throw StateError('保存確認情報が見つかりません');
      }
      final raw = jsonDecode(await file.readAsString());
      if (key != _key(pending.companyId) || !allowanceIdentityEqual(raw, pending.toJson())) {
        throw StateError('確認対象の手当保存が変わりました');
      }
      await file.delete();
    });
  }
}
