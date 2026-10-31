part of 'app_auth_storage_owner.dart';

/// Preparation only. Not bound to SupabaseBackend; cannot save or erase sessions.
class NativeAuthSessionStorage extends LocalStorage {
  NativeAuthSessionStorage(this._owner);
  final AppAuthStorageOwner _owner;
  @override
  Future<void> initialize() async {
    final result = await _owner.initialize();
    if (result.phase != AuthStoragePhase.ready && result.phase != AuthStoragePhase.empty) {
      throw StateError('Secure session preparation unavailable.');
    }
  }
  @override
  Future<bool> hasAccessToken() async => await _owner._readForRestore() != null;
  @override
  Future<String?> accessToken() => _owner._readForRestore();
  @override
  Future<void> persistSession(String value) => Future<void>.error(
    StateError('SDK writer ownership is not connected.'));
  @override
  Future<void> removePersistedSession() => Future<void>.error(
    StateError('SDK logout ownership is not connected.'));
}

/// Fixed channel, no configurable Keychain service or exposed credential output.
class NativeAuthSessionVault implements AuthSessionVault {
  NativeAuthSessionVault({required this.project, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.skworks.sko/auth_session_storage_preparation');
  final String project;
  final MethodChannel _channel;
  void _validate() {
    if (!RegExp(r'^[a-z0-9][a-z0-9.-]{0,127}$').hasMatch(project)) {
      throw ArgumentError('Invalid project storage scope.');
    }
  }
  @override
  Future<String?> read() async {
    _validate();
    final response = await _channel.invokeMapMethod<String, dynamic>('read', {'project': project});
    if (response == null || response['status'] is! String) throw StateError('Unknown secure read.');
    if (response.length == 1 && response['status'] == 'absent') return null;
    if (response.length == 2 && response['status'] == 'present' && response['envelope'] is String) {
      return response['envelope'] as String;
    }
    throw StateError('Secure session read unavailable.');
  }
  @override
  Future<void> write(String envelope) async {
    _validate();
    final response = await _channel.invokeMapMethod<String, dynamic>('write', {
      'project': project, 'envelope': envelope,
    });
    if (response == null || response.length != 1 || response['status'] != 'acknowledged') {
      throw StateError('Unknown secure write.');
    }
  }
}
