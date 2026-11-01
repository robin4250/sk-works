import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/profile/avatar_upload_format.dart';
import 'package:sk_works/features/profile/profile_repository.dart';

Uint8List box(String major, List<String> compatible) {
  final size = 16 + compatible.length * 4;
  final bytes = Uint8List(size);
  ByteData.sublistView(bytes).setUint32(0, size);
  bytes.setRange(4, 8, 'ftyp'.codeUnits);
  bytes.setRange(8, 12, major.codeUnits);
  for (var i = 0; i < compatible.length; i++) {
    bytes.setRange(16 + i * 4, 20 + i * 4, compatible[i].codeUnits);
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('supported raster signatures determine MIME and extension', () {
    for (final entry in <(List<int>, String, String)>[
      ([255, 216, 255], 'image/jpeg', '.jpg'),
      ([137, 80, 78, 71, 13, 10, 26, 10], 'image/png', '.png'),
      ('GIF89a'.codeUnits, 'image/gif', '.gif'),
      (
        [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits],
        'image/webp',
        '.webp',
      ),
    ]) {
      final format = AvatarUploadFormat.inspect(Uint8List.fromList(entry.$1));
      expect(format.mime, entry.$2);
      expect(format.extension, entry.$3);
    }
  });
  test('HEIC and HEIF brand checks preserve phone photo formats', () {
    expect(
      AvatarUploadFormat.inspect(box('mif1', ['heic'])).mime,
      'image/heic',
    );
    expect(AvatarUploadFormat.inspect(box('mif1', [])).mime, 'image/heif');
  });
  test('AVIF, unrelated BMFF and malformed ftyp do not masquerade as HEIF', () {
    final truncated = box('heic', [])..[3] = 24;
    for (final bytes in [
      box('avif', ['mif1']),
      box('mif1', ['avis']),
      box('mp42', []),
      truncated,
    ]) {
      expect(() => AvatarUploadFormat.inspect(bytes), throwsStateError);
    }
  });
  test('HTML, SVG, executable and empty content refuse as photos', () {
    for (final value in [
      '',
      '<html>fake.jpg</html>',
      '<svg></svg>',
      'MZ executable',
      '%PDF-1.7',
    ]) {
      expect(
        () =>
            AvatarUploadFormat.inspect(Uint8List.fromList(utf8.encode(value))),
        throwsStateError,
      );
    }
  });
  test('oversized recognizable photo refuses', () {
    final bytes = Uint8List(AvatarUploadFormat.maxBytes + 1)
      ..setRange(0, 3, [255, 216, 255]);
    expect(() => AvatarUploadFormat.inspect(bytes), throwsStateError);
  });
  test(
    'real SDK uses inspected bytes despite a misleading filename; invalid bytes never reach network',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://avatar.invalid',
        'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.startsWith('/storage/v1/object/')) {
            return http.Response(
              '{"Key":"profile-photos/synthetic"}',
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            request.method == 'GET' ? '[]' : '{}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final user = {
        'id': '11111111-1111-4111-8111-111111111111',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'synthetic@fixture.invalid',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-01-01T00:00:00Z',
      };
      final payload = base64Url.encode(
        utf8.encode(jsonEncode({'exp': 4102444800, 'sub': user['id']})),
      );
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'e30.$payload.synthetic',
          'refresh_token': 'synthetic',
          'expires_in': 3600,
          'token_type': 'bearer',
          'user': user,
        }),
      );
      final repository = ProfileRepository.forClient(client);
      await expectLater(
        repository.uploadAvatar(
          bytes: Uint8List.fromList('<svg/>'.codeUnits),
          filename: 'fake.jpg',
        ),
        throwsStateError,
      );
      expect(requests, isEmpty);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6GqkAAAAASUVORK5CYII=',
      );
      await repository.uploadAvatar(bytes: png, filename: 'misleading.html');
      final upload = requests.singleWhere(
        (r) => r.url.path.startsWith('/storage/v1/object/'),
      );
      expect(
        latin1.decode(upload.bodyBytes),
        matches(RegExp(r'content-type: image/png', caseSensitive: false)),
      );
      expect(upload.url.path, endsWith('.png'));
      expect(upload.headers['x-upsert'], 'false');
    },
  );
}
