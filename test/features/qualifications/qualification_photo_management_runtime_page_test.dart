import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';
import 'package:sk_works/features/qualifications/qualification_photo_management_runtime_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _NoRequests extends http.BaseClient {
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('Product route is OFF');
  }
}

void main() {
  testWidgets('default OFF shows unavailable and help without any SDK request', (tester) async {
    final httpClient = _NoRequests();
    final client = SupabaseClient('https://fixture.invalid', 'synthetic-public-key',
      httpClient: httpClient,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    final scope = ValueNotifier(const AdminSavedQualificationPhotoSubmissionScope(
      actorId: '00000000-0000-0000-0000-000000000001',
      companyId: '00000000-0000-0000-0000-000000000002',
      targetId: '00000000-0000-0000-0000-000000000003',
      active: true,
    ));
    await tester.pumpWidget(MaterialApp(home: QualificationPhotoManagementRuntimePage(
      scope: scope, qualificationName: '合成資格', holderName: '合成保有者', client: client,
    )));
    expect(find.text('写真の変更申請は準備中です。現在は利用できません。'), findsOneWidget);
    expect(find.text('残す写真を選ぶ'), findsNothing);
    await tester.tap(find.byTooltip('ヘルプ'));
    await tester.pumpAndSettle();
    expect(find.text('操作と保留中の申請について'), findsOneWidget);
    expect(httpClient.requests, 0);
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
    await client.dispose();
  });

  testWidgets('enabled without a session stays unavailable and cannot select photos', (tester) async {
    final scope = ValueNotifier(const AdminSavedQualificationPhotoSubmissionScope(
      actorId: null, companyId: null, targetId: null, active: false,
    ));
    await tester.pumpWidget(MaterialApp(home: QualificationPhotoManagementRuntimePage(
      scope: scope, qualificationName: '合成資格', holderName: '合成保有者', enabled: true,
    )));
    expect(find.textContaining('会社・対象・ログイン状態を確認できません'), findsOneWidget);
    expect(find.text('残す写真を選ぶ'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
  });
}
