import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'personal_vault_page.dart';

/// Candidate RPCs are authenticated and own-only on the server. No service key.
class PersonalVaultRepository {
  PersonalVaultRepository(this._client, {Stream<AuthState>? authChanges})
      : _authChanges = authChanges;
  final SupabaseClient _client;
  final Stream<AuthState>? _authChanges;
  static final _uuid = RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$');
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  String _session() {
    final session = _client.auth.currentSession;
    if (session == null || session.accessToken.isEmpty || session.isExpired) {
      throw StateError('ログイン状態を確認してください。');
    }
    return session.accessToken;
  }
  Future<T> _read<T>(Future<T> Function(_VaultReadSession) operation) async {
    final token = _session();
    final actor = _client.auth.currentUser!.id;
    final scope = _VaultReadSession(_client, actor, token,
      _authChanges ?? _client.auth.onAuthStateChange);
    try {
      await scope.check();
      return await operation(scope);
    } finally {
      await scope.close();
    }
  }
  static List<PersonalVaultEntry> parseMine(Object? raw) {
    if (raw is! List) { throw const FormatException('書類一覧を確認できません。'); }
    final seen = <String>{};
    return List.unmodifiable(raw.map((row) {
      if (row is! Map || row['manifest_id'] is! String || !_uuid.hasMatch(row['manifest_id'] as String) ||
          row['artifact_key'] is! String || !_hash.hasMatch(row['artifact_key'] as String) ||
          !['own_attendance','own_payroll'].contains(row['kind']) ||
          row['source_company_id'] is! String || !_uuid.hasMatch(row['source_company_id'] as String) ||
          row['completed_at'] is! String || DateTime.tryParse(row['completed_at'] as String) == null) {
        throw const FormatException('保管済み書類の応答を確認できません。');
      }
      final id = '${row['manifest_id']}:${row['artifact_key']}';
      if (!seen.add(id)) { throw const FormatException('保管済み書類が重複しています。'); }
      return PersonalVaultEntry(id: id,
        label: row['kind']=='own_payroll' ? '給与明細' : '本人出勤表',
        sourceCompanyLabel: '元の会社の記録', periodLabel: '保管済みPDF');
    }));
  }
  Future<List<PersonalVaultEntry>> loadMine() async {
    return _read((scope) async {
      final rows = await _client.rpc('personal_vault24_list_mine')
          .setHeader('Authorization', 'Bearer ${scope.token}');
      await scope.check();
      return parseMine(rows);
    });
  }
  Future<Uint8List> downloadMine(PersonalVaultEntry entry) async {
    return _read((scope) async {
    final parts = entry.id.split(':');
    if (parts.length != 2 || !_uuid.hasMatch(parts[0]) || !_hash.hasMatch(parts[1])) {
      throw const FormatException('本人書類のIDを確認できません。');
    }
    final result = await _client.rpc('personal_vault24_item_mine',
      params: {'mid': parts[0], 'artifact': parts[1]})
        .setHeader('Authorization', 'Bearer ${scope.token}');
    await scope.check();
    if (result is! List || result.length != 1 || result.single is! Map) {
      throw StateError('本人の保管済み書類を確認できません。');
    }
    final item = result.single as Map;
    final owner = scope.actor;
    final path = 'personal-vault/$owner/${parts[1]}.pdf';
    if (item['object_path'] != path || item['object_version'] is! String ||
        (item['object_version'] as String).isEmpty || item['pdf_hash'] is! String ||
        !_hash.hasMatch(item['pdf_hash'] as String) || item['byte_length'] is! int ||
        (item['byte_length'] as int) < 1 || (item['byte_length'] as int) > 52428800) {
      throw StateError('本人PDFの保存記録を確認できません。');
    }
    final bytes = await _client.storage.from('personal-pdf-vault').download(path);
    await scope.check();
    if (bytes.length != item['byte_length'] || sha256.convert(bytes).toString() != item['pdf_hash']) {
      throw StateError('保存されたPDFの整合性を確認できません。');
    }
    return bytes;
    });
  }
}

/// Per-read history only. It does not serialize global SDK mutations or detect
/// SDK restores which emit no events and return to the same token (silent ABA).
class _VaultReadSession {
  _VaultReadSession(this.client, this.actor, this.token, Stream<AuthState> events) {
    subscription = events.listen((state) {
      if (state.event == AuthChangeEvent.signedOut ||
          state.session?.user.id != actor || state.session?.accessToken != token) {
        invalid = true;
      }
    }, onError: (Object _) { invalid = true; }, onDone: () { invalid = true; });
  }
  final SupabaseClient client;
  final String actor, token;
  late final StreamSubscription<AuthState> subscription;
  bool invalid = false;
  Future<void> check() async {
    // Drain already queued Auth history before accepting a response, including
    // A -> B -> A where currentSession already looks unchanged.
    await Future<void>.delayed(Duration.zero);
    final current = client.auth.currentSession;
    if (invalid || current == null || current.isExpired ||
        current.user.id != actor || current.accessToken != token) {
      throw StateError('ログイン状態が変更されました。');
    }
  }
  Future<void> close() => subscription.cancel();
}
