import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

Future<Uint8List> downloadAuthenticatedStorageObject(
  SupabaseClient client, {
  required String bucket,
  required String path,
}) async {
  final session = client.auth.currentSession;
  if (session == null || session.isExpired) {
    throw StateError('ログイン状態を確認してください。');
  }

  final random = Random.secure();
  final nonce = List.generate(16, (_) => random.nextInt(256))
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  final bytes = await client.storage
      .from(bucket)
      .setHeader('Authorization', 'Bearer ${session.accessToken}')
      .setHeader('Cache-Control', 'no-cache, no-store')
      .download(path, cacheNonce: nonce);
  if (client.auth.currentSession?.accessToken != session.accessToken) {
    throw StateError('ログイン状態が変わりました。添付を開き直してください。');
  }
  return bytes;
}
