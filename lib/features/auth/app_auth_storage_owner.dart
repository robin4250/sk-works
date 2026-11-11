import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'native_auth_session_storage.dart';

/// Unconnected migration contract. Never reads the live SDK or removes legacy data.
abstract interface class AuthSessionVault {
  Future<String?> read();
  Future<void> write(String envelope);
}

enum AuthStoragePhase { unopened, empty, prepared, pending, unknown, blocked }

class AuthStorageOutcome {
  const AuthStorageOutcome(this.phase);
  final AuthStoragePhase phase;
}

/// Copies opaque bytes only; prepared is NOT permission to restore a session.
/// No durable logout tombstone/native CAS exists here. SDK adoption and restore
/// require a separate owner and must remain disconnected.
class AppAuthStorageOwner {
  AppAuthStorageOwner({required this.vault, required this.project,
    required this.readLegacy, required this.logoutPending});
  final AuthSessionVault vault;
  final String project;
  final Future<String?> Function() readLegacy;
  final Future<bool> Function() logoutPending;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  AuthStoragePhase _phase = AuthStoragePhase.unopened;
  AuthStoragePhase get phase => _phase;

  /// Must run synchronously with logout admission, before any asynchronous work.
  void retire() { _generation++; _phase = AuthStoragePhase.blocked; }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> _current(int generation) async {
    final pending = await logoutPending();
    return generation == _generation && !pending;
  }

  Map<String, Object?> _record(String value, String state) => {
    'schema': 1, 'project': project, 'state': state, 'session': value,
  };

  Map<String, dynamic> _decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value.length != 4 ||
        value['schema'] != 1 || value['project'] != project ||
        !{'pending', 'committed'}.contains(value['state']) ||
        value['session'] is! String || (value['session'] as String).isEmpty) {
      throw const FormatException('Invalid secure session envelope.');
    }
    return value;
  }

  Future<AuthStorageOutcome> initialize() => _serial(() async {
    if (_phase != AuthStoragePhase.unopened) return AuthStorageOutcome(_phase);
    final generation = _generation;
    try {
      if (project.isEmpty || !await _current(generation)) return _blocked();
      final secure = await vault.read();
      if (!await _current(generation)) return _blocked();
      if (secure != null) {
        final record = _decode(secure);
        if (record['state'] != 'committed') {
          _phase = AuthStoragePhase.pending;
          return AuthStorageOutcome(_phase);
        }
        _phase = AuthStoragePhase.prepared;
        return AuthStorageOutcome(_phase);
      }
      final legacy = await readLegacy();
      if (!await _current(generation)) return _blocked();
      if (legacy == null) {
        _phase = AuthStoragePhase.empty;
        return AuthStorageOutcome(_phase);
      }
      if (legacy.isEmpty) throw const FormatException('Empty legacy session.');
      // Copy exactly; no setSession, refresh, token rewrite or legacy cleanup.
      final pending = jsonEncode(_record(legacy, 'pending'));
      await vault.write(pending);
      if (!await _current(generation)) return _blocked();
      if (await vault.read() != pending) throw StateError('Unconfirmed secure stage.');
      if (!await _current(generation)) return _blocked();
      final committed = jsonEncode(_record(legacy, 'committed'));
      await vault.write(committed);
      if (!await _current(generation)) return _blocked();
      if (await vault.read() != committed) throw StateError('Unconfirmed secure commit.');
      if (!await _current(generation)) return _blocked();
      _phase = AuthStoragePhase.prepared;
      return AuthStorageOutcome(_phase);
    } catch (_) {
      if (_phase != AuthStoragePhase.blocked) _phase = AuthStoragePhase.unknown;
      return AuthStorageOutcome(_phase);
    }
  });

  AuthStorageOutcome _blocked() {
    _phase = AuthStoragePhase.blocked;
    return AuthStorageOutcome(_phase);
  }

}
