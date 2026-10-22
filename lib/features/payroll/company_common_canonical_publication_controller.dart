import 'package:supabase_flutter/supabase_flutter.dart';
import 'company_common_canonical_publication_command.dart';
import 'company_common_canonical_publication_pending_store.dart';
import 'company_common_canonical_publication_repository.dart';

/// One approved publish attempt. Restored/unknown commands have a read-only
/// receipt path, never an automatic publish retry or replacement request ID.
class CommonPayrollCanonicalPublicationController {
  CommonPayrollCanonicalPublicationController({required this.companyId,
    required this.repository, required this.store})
      : actorId = repository.actorId, _session = repository.sessionKey;
  final String companyId;
  final String? actorId, _session;
  final CommonPayrollCanonicalPublicationRepository repository;
  final CommonPayrollCanonicalPublicationPendingStore store;
  CommonPayrollCanonicalPublicationPending? _pending;
  CommonPayrollCanonicalPublicationPending? get pending => _pending;
  bool _busy = false, _loaded = false;
  bool get busy => _busy;
  bool get ready => _loaded && !_busy && _pending == null;
  void _current() {
    if (actorId == null || _session == null || repository.actorId != actorId || repository.sessionKey != _session) {
      throw StateError('ログイン情報が変更されました');
    }
  }
  Future<void> load() async {
    if (_busy) throw StateError('給与反映の確認中です');
    _current();
    _busy = true;
    try {
      final saved = await store.read(actorId!, companyId);
      _current();
      _pending = saved;
      _loaded = true;
    } finally { _busy = false; }
  }
  Future<CommonPayrollCanonicalPublicationResult> publish(CommonPayrollCanonicalPublicationCommand command) async {
    _current();
    if (!ready || command.companyId != companyId) throw StateError('先の給与反映結果を確認してください');
    _busy = true;
    final saved = CommonPayrollCanonicalPublicationPending(actorId: actorId!, command: command);
    _pending = saved;
    try {
      // Persistence must finish before the sole publish call is issued.
      await store.write(saved);
      _current();
      CommonPayrollCanonicalPublicationResult result;
      try {
        result = await repository.publish(command);
      } catch (error) {
        // Only an explicit PostgreSQL rejection of this first live attempt is
        // known rolled back. Receipt-read failures and transport errors cannot
        // establish that an earlier publish did not commit.
        if (_knownRollback(error)) {
          _current();
          await store.clear(saved);
          _pending = null;
        }
        rethrow;
      }
      _current();
      await store.clear(saved);
      _current();
      _pending = null;
      return result;
    } finally { _busy = false; }
  }
  Future<CommonPayrollCanonicalPublicationResult?> lookup() async {
    _current();
    final saved = _pending;
    if (!_loaded || _busy || saved == null) throw StateError('給与反映の確認記録がありません');
    _busy = true;
    try {
      final result = await repository.receipt(saved.command);
      _current();
      if (result == null) return null;
      await store.clear(saved);
      _current();
      _pending = null;
      return result;
    } finally { _busy = false; }
  }
  static bool _knownRollback(Object error) => error is PostgrestException && const {
    '42501', '40001', '22023', '55000', '54000', '23505', 'P0001', 'PGRST202',
  }.contains(error.code);
}
