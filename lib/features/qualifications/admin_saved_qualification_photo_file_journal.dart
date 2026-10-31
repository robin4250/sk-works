import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'admin_saved_qualification_photo_contract.dart';

/// Private flushed intent files; no tokens or image bytes. Follows the existing
/// application-support pending-file pattern without editing shared stores.
class FileAdminSavedQualificationPhotoJournal {
  FileAdminSavedQualificationPhotoJournal({
    required this.currentActor,
    required this.requireScope,
    Future<Directory> Function()? directory,
    this.legacyRead,
    this.afterFlush,
  }) : directory = directory ?? getApplicationSupportDirectory;
  final String? Function() currentActor;
  final void Function() requireScope;
  final Future<Directory> Function() directory;
  final Future<String?> Function(String)? legacyRead;
  final Future<void> Function()? afterFlush;
  static final _queues = <String, Future<void>>{};
  static final _key = RegExp(
    r'^sko\.admin\.qualification\.saved\.v1\.([0-9a-f-]{36})\.([0-9a-f-]{36})\.([0-9a-f-]{36})(?:\.receipt\.([0-9a-f-]{36}))?$',
  );
  RegExpMatch _bound(String key) {
    requireScope();
    final match = _key.firstMatch(key);
    if (match == null ||
        ![
          match[1],
          match[2],
          match[3],
        ].every(AdminSavedQualificationPhotoCapability.isUuid) ||
        (match[4] != null &&
            !AdminSavedQualificationPhotoCapability.isUuid(match[4])) ||
        match[1] != currentActor()) {
      throw StateError('資格申請の保存対象が変わりました。');
    }
    return match;
  }

  Future<void> _regular(String path, {bool absent = true}) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        !(absent && type == FileSystemEntityType.notFound)) {
      throw StateError('資格申請の保存場所を確認できません。');
    }
  }

  Future<File> _file(String key) async {
    _bound(key);
    final root = await directory();
    _bound(key);
    var type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await root.create(recursive: true);
      type = await FileSystemEntity.type(root.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory)
      throw StateError('資格申請の保存場所を確認できません。');
    final canonical = await root.resolveSymbolicLinks();
    _bound(key);
    final folder = Directory('$canonical/qualification-admin-photo-pending-v1');
    type = await FileSystemEntity.type(folder.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await folder.create();
      type = await FileSystemEntity.type(folder.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory)
      throw StateError('資格申請の保存場所を確認できません。');
    return File('${folder.path}/${sha256.convert(utf8.encode(key))}.json');
  }

  Future<T> _locked<T>(String key, Future<T> Function(File) action) async {
    final file = await _file(key);
    _bound(key);
    final previous = _queues[file.path] ?? Future<void>.value();
    final gate = Completer<void>();
    _queues[file.path] = gate.future;
    await previous;
    RandomAccessFile? lock;
    try {
      await _regular('${file.path}.lock');
      lock = await File('${file.path}.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      _bound(key);
      final legacy = await legacyRead?.call(key);
      _bound(key);
      if (legacy != null) throw StateError('以前の資格申請情報を保持しています。再送せず確認してください。');
      final result = await action(file);
      _bound(key);
      return result;
    } finally {
      try {
        await lock?.close();
      } finally {
        gate.complete();
        if (identical(_queues[file.path], gate.future))
          _queues.remove(file.path);
      }
    }
  }

  String _checksum(String key, String value) =>
      sha256.convert(utf8.encode('$key\u0000$value')).toString();
  Map<String, dynamic> _record(String key, String value) {
    final m = _bound(key);
    final raw = jsonDecode(value);
    if (raw is! Map ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['actor_id'] != m[1] ||
        raw['company_id'] != m[2] ||
        raw['target_id'] != m[3] ||
        !AdminSavedQualificationPhotoCapability.isUuid(
          raw['request_id'] as String?,
        ) ||
        (m[4] != null && raw['request_id'] != m[4])) {
      throw StateError('資格申請の保存内容を照合できません。');
    }
    return Map<String, dynamic>.from(raw);
  }

  String _encode(String key, String value) {
    _record(key, value);
    return jsonEncode({
      'storage_schema': 1,
      'key': key,
      'value': value,
      'sha256': _checksum(key, value),
    });
  }

  Future<String> _decodeFile(File file, String key) async {
    await _regular(file.path, absent: false);
    _bound(key);
    if (await file.length() > 262144) throw StateError('資格申請の保存内容を確認できません。');
    final raw = jsonDecode(await file.readAsString());
    _bound(key);
    const fields = {'storage_schema', 'key', 'value', 'sha256'};
    if (raw is! Map ||
        raw.length != fields.length ||
        !raw.keys.every(fields.contains) ||
        raw['storage_schema'] is! int ||
        raw['storage_schema'] != 1 ||
        raw['key'] != key ||
        raw['value'] is! String ||
        raw['sha256'] != _checksum(key, raw['value'] as String)) {
      throw StateError('資格申請の保存内容を照合できません。');
    }
    _record(key, raw['value'] as String);
    return raw['value'] as String;
  }

  Future<String?> _read(File file, String key) async {
    await _regular(file.path);
    await _regular('${file.path}.tmp');
    _bound(key);
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) {
      // A competing or interrupted replacement is never silently discarded.
      if (await file.exists())
        throw StateError('資格申請の保存記録が競合しています。再送せず確認してください。');
      await _decodeFile(temp, key);
      final handle = await temp.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      _bound(key);
      await temp.rename(file.path);
      _bound(key);
    }
    return await file.exists() ? await _decodeFile(file, key) : null;
  }

  String _canonical(Object? value) {
    Object? normalize(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: normalize(value[k])};
      }
      if (value is List) return value.map(normalize).toList();
      return value;
    }

    return jsonEncode(normalize(value));
  }

  void _sameIntent(String key, String before, String after) {
    final old = _record(key, before), next = _record(key, after);
    if (_canonical({...old}..remove('stage')) !=
            _canonical({...next}..remove('stage')) ||
        (const ['approved', 'rejected'].contains(old['stage']) &&
            old['stage'] != next['stage'])) {
      throw StateError('保存済みの資格申請が変わりました。');
    }
  }

  Future<String?> read(String key) => _locked(key, (file) => _read(file, key));
  Future<void> write(String key, String value) => _locked(key, (file) async {
    final old = await _read(file, key);
    if (old != null) {
      if (key.contains('.receipt.')) {
        if (old != value) throw StateError('確定済みの資格申請を上書きできません。');
        return;
      }
      _sameIntent(key, old, value);
    }
    final temp = File('${file.path}.tmp');
    await temp.create(exclusive: true);
    // Recheck after claiming the unique temporary name; never replace a newer intent.
    final present = await file.exists() ? await _decodeFile(file, key) : null;
    if (present != null) {
      if (key.contains('.receipt.')) {
        if (present != value) throw StateError('確定済みの資格申請が変わりました。');
      } else {
        _sameIntent(key, present, value);
      }
    } else if (old != null) {
      throw StateError('資格申請の保存記録が変わりました。');
    }
    await temp.writeAsString(_encode(key, value), flush: true);
    _bound(key);
    if (await _decodeFile(temp, key) != value)
      throw StateError('資格申請の保存内容が一致しません。');
    await afterFlush?.call();
    _bound(key);
    await temp.rename(file.path);
    _bound(key);
    if (await _decodeFile(file, key) != value)
      throw StateError('資格申請の保存内容が一致しません。');
  });
  Future<void> clear(String key) => _locked(key, (file) async {
    final active = await _read(file, key);
    if (active == null) throw StateError('確認対象の資格申請がありません。');
    final record = _record(key, active);
    final receiptKey = '$key.receipt.${record['request_id']}';
    final receiptFile = await _file(receiptKey);
    final saved = await _read(receiptFile, receiptKey);
    if (saved == null) throw StateError('確定した資格申請の記録がありません。');
    final receipt = _record(receiptKey, saved);
    if (!const ['approved', 'rejected'].contains(receipt['stage']))
      throw StateError('申請結果は未確定です。');
    _sameIntent(key, active, jsonEncode(receipt));
    _bound(key);
    await file.delete();
    _bound(key);
  });
}
