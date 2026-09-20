import 'package:flutter/material.dart';

import 'app_v2.dart';
import 'data/supabase_backend.dart';

export 'app_v2.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SupabaseBackend.initializeIfConfigured();
  } catch (_) {
    // Fail closed in the app UI instead of terminating before runApp.
  }
  runApp(const SkWorksApp());
}
