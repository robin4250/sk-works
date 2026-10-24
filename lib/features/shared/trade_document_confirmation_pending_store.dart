import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'trade_document_confirmation_model.dart';

class TradeConfirmationPending {
  TradeConfirmationPending(this.command);
  final TradeConfirmationCommand command;
  Map<String, dynamic> toJson() => {'schema': 1, 'kind': 'trade_document_confirmation_v1',
    'request_id': command.requestId, 'expected_command': command.expected.value};
  factory TradeConfirmationPending.parse(Object? raw) {
    const keys = {'schema', 'kind', 'request_id', 'expected_command'};
    if (raw is! Map || raw.length != keys.length || !keys.every(raw.containsKey) ||
        raw['schema'] != 1 || raw['kind'] != 'trade_document_confirmation_v1' || raw['request_id'] is! String) {
      throw const FormatException('書類確認の記録を読み取れません');
    }
    return TradeConfirmationPending(TradeConfirmationCommand(
      expected: TradeConfirmationDescriptor.parse(raw['expected_command']), requestId: raw['request_id'] as String));
  }
}

abstract interface class TradeConfirmationPendingStore {
  Future<TradeConfirmationPending?> read(String actor, String kind, String parent);
  Future<void> write(TradeConfirmationPending pending);
  Future<void> clear(TradeConfirmationPending pending);
}

/// Separate from attachment saves and financial approval histories. No tokens,
/// stamp images, retry instructions or replaceable request IDs are persisted.
class FileTradeConfirmationPendingStore implements TradeConfirmationPendingStore {
  FileTradeConfirmationPendingStore({required this.currentActor, Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;
  final String? Function() currentActor;
  final Future<Directory> Function() directory;
  static final Map<String, Future<void>> _queues = {};
  void _actor(String actor) {
    if (!tradeConfirmationUuid(actor) || currentActor() != actor) throw StateError('ログイン情報が変更されました');
  }
  Future<T> _locked<T>(String actor, String kind, String parent, Future<T> Function(File) action) async {
    _actor(actor);
    if (!const {'invoice', 'payment_certificate'}.contains(kind) || !tradeConfirmationUuid(parent)) {
      throw const FormatException('確認する書類を識別できません');
    }
    final root = await directory(); _actor(actor);
    final folder = Directory('${root.path}/trade-document-confirmation-pending-v1');
    await folder.create(recursive: true);
    final name = sha256.convert(utf8.encode(jsonEncode([actor, kind, parent])));
    final file = File('${folder.path}/$name.json');
    final complete = Completer<T>();
    final previous = _queues[file.path] ?? Future<void>.value();
    final next = previous.then((_) async {
      RandomAccessFile? lock;
      try {
        lock = await File('${file.path}.lock').open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive); _actor(actor);
        final result = await action(file); _actor(actor);
        complete.complete(result);
      } catch (error, stack) { complete.completeError(error, stack); }
      finally { try { await lock?.close(); } catch (_) { /* Retain recorded outcome. */ } }
    });
    _queues[file.path] = next;
    unawaited(next.whenComplete(() { if (identical(_queues[file.path], next)) _queues.remove(file.path); }));
    return complete.future;
  }
  Future<TradeConfirmationPending?> _read(File file, String actor, String kind, String parent) async {
    final temporary = File('${file.path}.tmp');
    if (await file.exists() && await temporary.exists()) throw StateError('書類確認の記録が重複しています');
    if (!await file.exists() && await temporary.exists()) await temporary.rename(file.path);
    if (!await file.exists()) return null;
    if (await file.length() > 65536) throw const FormatException('書類確認の記録が大きすぎます');
    final pending = TradeConfirmationPending.parse(jsonDecode(await file.readAsString()));
    final e = pending.command.expected;
    if (e.actorId != actor || e.kind != kind || e.parentId != parent) {
      throw const FormatException('書類確認の記録の所有者が一致しません');
    }
    return pending;
  }
  @override Future<TradeConfirmationPending?> read(String actor, String kind, String parent) =>
    _locked(actor, kind, parent, (file) => _read(file, actor, kind, parent));
  @override Future<void> write(TradeConfirmationPending pending) {
    final e = pending.command.expected;
    return _locked(e.actorId, e.kind, e.parentId, (file) async {
      if (await _read(file, e.actorId, e.kind, e.parentId) != null) throw StateError('前の書類確認の結果を確認してください');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(tradeConfirmationJson(pending.toJson()), flush: true);
      await temporary.rename(file.path);
    });
  }
  @override Future<void> clear(TradeConfirmationPending pending) {
    final e = pending.command.expected;
    return _locked(e.actorId, e.kind, e.parentId, (file) async {
      final old = await _read(file, e.actorId, e.kind, e.parentId);
      if (old == null || tradeConfirmationJson(old.toJson()) != tradeConfirmationJson(pending.toJson())) {
        throw StateError('書類確認の記録が一致しません');
      }
      await file.delete();
    });
  }
}
