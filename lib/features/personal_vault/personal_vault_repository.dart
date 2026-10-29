import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'personal_vault_page.dart';
import 'personal_vault_pdf_download.dart';

/// Candidate RPCs are authenticated and own-only on the server. No service key.
class PersonalVaultRepository {
  PersonalVaultRepository(this._client, {Stream<AuthState>? authChanges,
    http.Client Function()? downloadClientFactory})
      : _authChanges = authChanges,
        _download = PersonalVaultPdfDownload(clientFactory: downloadClientFactory);
  final SupabaseClient _client;
  final Stream<AuthState>? _authChanges;
  final PersonalVaultPdfDownload _download;
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
  Future<Uint8List> downloadMine(PersonalVaultEntry entry) =>
      _read((scope) => _downloadMine(scope, entry));

  /// Holds Auth history through the preview/native handoff, including lazy
  /// callbacks. Invalidation ends the logical operation even if a platform
  /// future never settles. Bytes already given to the OS cannot be recalled.
  Future<T> withOwnPdf<T>(PersonalVaultEntry entry,
      Future<T> Function(PersonalVaultPdfLease) operation,
      {Future<void>? invalidated}) => _read((scope) async {
    if (invalidated != null) {
      unawaited(invalidated.then((_) => scope.invalidate(),
          onError: (Object _) => scope.invalidate()));
    }
    await scope.check();
    final bytes = await _downloadMine(scope, entry);
    final lease = PersonalVaultPdfLease._(scope, bytes);
    try {
      await scope.check();
      return await Future.any<T>([
        operation(lease),
        scope.invalidated.then<T>((_) => throw StateError('本人書類の表示を終了しました。')),
      ]);
    } finally {
      lease.invalidate();
    }
  });

  Future<Uint8List> _downloadMine(_VaultReadSession scope, PersonalVaultEntry entry) async {
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
    final storage = _client.storage.from('personal-pdf-vault');
    final headers = Map<String, String>.fromEntries(storage.headers.entries
        .where((entry) => entry.key.toLowerCase() != 'authorization'))
      ..['Authorization'] = 'Bearer ${scope.token}';
    final bytes = await _download.download(
      uri: Uri.parse('${storage.url}/object/personal-pdf-vault/$path'),
      headers: headers, expectedLength: item['byte_length'] as int,
      expectedHash: item['pdf_hash'] as String, invalidated: scope.invalidated,
      validateSession: scope.check);
    await scope.check();
    if (bytes.length != item['byte_length'] || sha256.convert(bytes).toString() != item['pdf_hash']) {
      throw StateError('保存されたPDFの整合性を確認できません。');
    }
    return bytes;
  }
}

/// Owns only the in-memory snapshot; it never changes the stored PDF/original.
/// Each renderer/layout callback must obtain a fresh checked copy. Retaining a
/// callback after operation completion does not retain access to these bytes.
class PersonalVaultPdfLease {
  PersonalVaultPdfLease._(this._scope, Uint8List bytes) : _bytes = Uint8List.fromList(bytes);
  final _VaultReadSession _scope;
  Uint8List? _bytes;
  bool _closed = false;
  Future<void> get invalidated => _scope.invalidated;
  Future<Uint8List> readBytes() async {
    await _scope.check();
    final bytes = _bytes;
    if (_closed || bytes == null) { throw StateError('本人書類の表示を終了しました。'); }
    final copy = Uint8List.fromList(bytes);
    await _scope.check();
    checkCurrent();
    return copy;
  }
  /// Final synchronous guard before invoking a plugin. This cannot make the
  /// plugin/OS handoff atomic with SDK changes occurring inside that plugin.
  void checkCurrent() {
    _scope.checkCurrent();
    if (_closed || _bytes == null) { throw StateError('本人書類の表示を終了しました。'); }
  }
  void invalidate() { _close(); _scope.invalidate(); }
  void _close() { _closed = true; _bytes = null; }
}

/// Per-read history only. It does not serialize global SDK mutations or detect
/// SDK restores which emit no events and return to the same token (silent ABA).
class _VaultReadSession {
  _VaultReadSession(this.client, this.actor, this.token, Stream<AuthState> events) {
    subscription = events.listen((state) {
      if (state.event == AuthChangeEvent.signedOut ||
          state.session?.user.id != actor || state.session?.accessToken != token) {
        invalidate();
      }
    }, onError: (Object _) { invalidate(); }, onDone: invalidate);
  }
  final SupabaseClient client;
  final String actor, token;
  late final StreamSubscription<AuthState> subscription;
  bool invalid = false;
  final _invalidated = Completer<void>();
  Future<void> get invalidated => _invalidated.future;
  void invalidate() {
    invalid = true;
    if (!_invalidated.isCompleted) { _invalidated.complete(); }
  }
  Future<void> check() async {
    // Drain already queued Auth history before accepting a response, including
    // A -> B -> A where currentSession already looks unchanged.
    await Future<void>.delayed(Duration.zero);
    checkCurrent();
  }
  void checkCurrent() {
    final current = client.auth.currentSession;
    if (invalid || current == null || current.isExpired ||
        current.user.id != actor || current.accessToken != token) {
      invalidate();
      throw StateError('ログイン状態が変更されました。');
    }
  }
  Future<void> close() => subscription.cancel();
}
