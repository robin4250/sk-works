import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/app_auth_logout_persistence.dart';
import '../features/auth/app_auth_mutation_gateway.dart';

class SupabaseBackendConfig {
  const SupabaseBackendConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

class SupabaseBackend {
  const SupabaseBackend._();

  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initializeIfConfigured() async {
    if (_initialized || !SupabaseBackendConfig.isConfigured) {
      return;
    }

    final persistence = AppAuthLogoutPersistence.forProject(SupabaseBackendConfig.url);
    await Supabase.initialize(
      url: SupabaseBackendConfig.url,
      publishableKey: SupabaseBackendConfig.publishableKey,
      authOptions: FlutterAuthClientOptions(localStorage: persistence),
    );
    AppAuthMutationGateway.bindPersistence(client, persistence);
    _initialized = true;
  }
}
