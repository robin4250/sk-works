import 'package:flutter/material.dart';

import 'app_v2.dart';
import 'data/supabase_backend.dart';

export 'app_v2.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseBackend.initializeIfConfigured();
  runApp(const SkWorksApp());
}
