import 'package:supabase_flutter/supabase_flutter.dart';
import 'trade_document_confirmation_model.dart';
import 'trade_document_confirmation_pending_store.dart';
import 'trade_document_confirmation_repository.dart';

class TradeConfirmationController {
  TradeConfirmationController({required this.repository, required this.store,
    required this.kind, required this.parentId}) : actorId = repository.actorId, _token = repository.sessionKey;
  final TradeConfirmationRepository repository;
  final TradeConfirmationPendingStore store;
  final String kind, parentId;
  final String? actorId, _token;
  bool busy = false, loaded = false;
  TradeConfirmationPending? pending;
  void verify() {
    if (actorId == null || _token == null || actorId != repository.actorId || _token != repository.sessionKey) {
      throw StateError('ログイン情報が変わりました。書類を開き直してください。');
    }
  }
  Future<void> load() async {
    verify(); if (busy) throw StateError('書類を確認中です'); busy = true;
    try { final saved = await store.read(actorId!, kind, parentId); verify(); pending = saved; loaded = true; }
    finally { busy = false; }
  }
  Future<TradeConfirmationResult> confirm(TradeConfirmationDescriptor expected) async {
    verify();
    if (!loaded || busy || pending != null || expected.actorId != actorId ||
        expected.kind != kind || expected.parentId != parentId) {
      throw StateError('前の書類確認の結果を確認してください');
    }
    busy = true;
    final saved = TradeConfirmationPending(TradeConfirmationCommand(expected: expected,
      requestId: TradeConfirmationCommand.newRequestId()));
    pending = saved;
    try {
      await store.write(saved); verify();
      TradeConfirmationResult result;
      try { result = await repository.confirm(saved.command); }
      catch (error) {
        if (error is PostgrestException && const {'42501', '40001', '22023', '55000', '0A000', 'P0001', '23505', 'PGRST202'}.contains(error.code)) {
          verify(); await store.clear(saved); verify(); pending = null;
        }
        rethrow;
      }
      verify(); await store.clear(saved); verify(); pending = null; return result;
    } finally { busy = false; }
  }
  Future<TradeConfirmationResult?> lookup() async {
    verify(); final saved = pending;
    if (!loaded || busy || saved == null) throw StateError('書類確認の記録がありません');
    busy = true;
    try {
      final result = await repository.receipt(saved.command); verify();
      if (result == null) return null;
      await store.clear(saved); verify(); pending = null; return result;
    } finally { busy = false; }
  }
}
