import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Credential-free logout marker operations; failures never open the fence.
abstract interface class AppLogoutMarkerStore {
  Future<void> initialize();
  Future<String?> read();
  Future<bool> writePending();
  Future<bool> clear();
}

class SharedPreferencesLogoutMarkerStore implements AppLogoutMarkerStore {
  SharedPreferencesLogoutMarkerStore(this.key);
  final String key;
  late SharedPreferences _preferences;
  @override
  Future<void> initialize() async { _preferences = await SharedPreferences.getInstance(); }
  @override
  Future<String?> read() async {
    await _preferences.reload();
    return _preferences.getString(key);
  }
  @override
  Future<bool> writePending() => _preferences.setString(key, 'pending-v1');
  @override
  Future<bool> clear() => _preferences.remove(key);
}

/// Unlike the SDK default adapter, observes platform write/remove booleans
/// and reloads before accepting session absence; a cache eviction is not proof.
class SharedPreferencesLogoutSessionStorage extends LocalStorage {
  SharedPreferencesLogoutSessionStorage(this.key);
  final String key;
  late SharedPreferences _preferences;
  @override
  Future<void> initialize() async { _preferences = await SharedPreferences.getInstance(); }
  @override
  Future<bool> hasAccessToken() async { await _preferences.reload(); return _preferences.containsKey(key); }
  @override
  Future<String?> accessToken() async { await _preferences.reload(); return _preferences.getString(key); }
  @override
  Future<void> persistSession(String value) async {
    if (!await _preferences.setString(key, value)) throw StateError('Session storage write was not acknowledged.');
    await _preferences.reload();
    if (_preferences.getString(key) != value) throw StateError('Session storage write could not be confirmed.');
  }
  @override
  Future<void> removePersistedSession() async {
    if (!await _preferences.remove(key)) throw StateError('Session storage removal was not acknowledged.');
    await _preferences.reload();
    if (_preferences.containsKey(key)) throw StateError('Session storage removal could not be confirmed.');
  }
}

/// The gateway receives only this port, never stored sessions or credentials.
abstract interface class AppLogoutPersistenceFence {
  bool get blocked;
  Future<void> persistIntent();
  Future<void> confirmLocalRemoval();
  Future<void> releaseFence(bool Function() localLogoutStillConfirmed);
}

/// Existing SDK storage key and serialization are retained. No token is logged,
/// copied to a new key, or returned through the gateway's persistence port.
class AppAuthLogoutPersistence extends LocalStorage implements AppLogoutPersistenceFence {
  AppAuthLogoutPersistence({required LocalStorage delegate, required AppLogoutMarkerStore markers})
      : _delegate = delegate, _markers = markers;
  factory AppAuthLogoutPersistence.forProject(String url) {
    final key = sdkSessionKey(url);
    return AppAuthLogoutPersistence(
      delegate: SharedPreferencesLogoutSessionStorage(key),
      markers: SharedPreferencesLogoutMarkerStore('$key.sko-logout-fence-v1'));
  }
  // Exact default key in pinned SupabaseFlutter 2.17.2; no session migration.
  static String sdkSessionKey(String url) => 'sb-${Uri.parse(url).host.split('.').first}-auth-token';
  final LocalStorage _delegate;
  final AppLogoutMarkerStore _markers;
  Future<void> _tail = Future<void>.value();
  bool _blocked = true;
  int _epoch = 0;
  @override
  bool get blocked => _blocked;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError:(Object _, StackTrace __) {});
    return next;
  }
  @override
  Future<void> initialize() => _serial(() async {
    try { await _markers.initialize(); _blocked = await _markers.read() != null; }
    catch (_) { _blocked = true; }
    await _delegate.initialize();
  });
  @override
  Future<bool> hasAccessToken() => _serial(() async => !_blocked && await _delegate.hasAccessToken());
  @override
  Future<String?> accessToken() => _serial(() async => _blocked ? null : await _delegate.accessToken());
  @override
  Future<void> persistSession(String value) {
    if (_blocked) return Future<void>.value();
    final epoch = _epoch;
    return _serial(() async {
      if (!_blocked && epoch == _epoch) await _delegate.persistSession(value);
    });
  }
  @override
  Future<void> removePersistedSession() => _serial(_delegate.removePersistedSession);

  Future<void> _removeAndVerify() async {
    await _delegate.removePersistedSession();
    if (await _delegate.hasAccessToken() || await _delegate.accessToken() != null) {
      throw StateError('Local logout storage removal could not be confirmed.');
    }
  }
  @override
  Future<void> persistIntent() {
    _blocked = true;
    final epoch = ++_epoch;
    return _serial(() async {
      try {
        await _markers.initialize();
        if (!await _markers.writePending() || await _markers.read() != 'pending-v1' || epoch != _epoch) {
          throw StateError('Logout marker could not be confirmed.');
        }
      } catch (_) {
        // No token deletion before platform marker acknowledgment/readback. The in-memory
        // fence stays closed; an unacknowledged write cannot prove restart safety.
        throw StateError('Logout marker could not be confirmed.');
      }
    });
  }
  @override
  Future<void> confirmLocalRemoval() {
    final epoch = _epoch;
    return _serial(() async {
      if (!_blocked || epoch != _epoch) throw StateError('Logout fence changed.');
      await _removeAndVerify();
      if (epoch != _epoch) throw StateError('Logout fence changed.');
    });
  }
  @override
  Future<void> releaseFence(bool Function() localLogoutStillConfirmed) {
    final epoch = _epoch;
    return _serial(() async {
    if (!_blocked || epoch != _epoch || !localLogoutStillConfirmed()) throw StateError('Logout confirmation changed.');
    try {
      await _removeAndVerify();
      if (!await _markers.clear() || await _markers.read() != null || epoch != _epoch || !localLogoutStillConfirmed()) {
        throw StateError('Logout marker release could not be confirmed.');
      }
      // Marker readback reloads preferences too: recheck session absence after it.
      if (await _delegate.hasAccessToken() || await _delegate.accessToken() != null ||
          epoch != _epoch || !localLogoutStillConfirmed()) {
        throw StateError('Session storage changed during marker release.');
      }
      _blocked = false;
    } catch (_) {
      try { await _markers.writePending(); } catch (_) { /* Remain blocked. */ }
      throw StateError('Logout marker release could not be confirmed.');
    }
    });
  }
}
