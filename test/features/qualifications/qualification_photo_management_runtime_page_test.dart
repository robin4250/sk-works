import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';
import 'package:sk_works/features/qualifications/qualification_photo_management_runtime_page.dart';

void main() {
  testWidgets('default OFF shows unavailable and help without any SDK request', (tester) async {
    var signedReads = 0;
    final scope = ValueNotifier(const AdminSavedQualificationPhotoSubmissionScope(
      actorId: '00000000-0000-0000-0000-000000000001',
      companyId: '00000000-0000-0000-0000-000000000002',
      targetId: '00000000-0000-0000-0000-000000000003',
      active: true,
    ));
    await tester.pumpWidget(MaterialApp(home: QualificationPhotoManagementRuntimePage(
      scope: scope, qualificationName: '合成資格', holderName: '合成保有者',
      signedUrl: (_) async { signedReads++; throw StateError('OFF reader forbidden'); },
    )));
    expect(find.text('写真の変更申請は準備中です。現在は利用できません。'), findsOneWidget);
    expect(find.text('残す写真を選ぶ'), findsNothing);
    await tester.tap(find.byTooltip('ヘルプ'));
    await tester.pumpAndSettle();
    expect(find.text('操作と保留中の申請について'), findsOneWidget);
    expect(signedReads, 0);
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

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
  for (final status in <String?>[null, 'draft', 'pending', 'unknown']) {
    testWidgets('status=$status cannot acknowledge local pending identity', (tester) async {
      var acknowledgements = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: QualificationPhotoAcknowledgementButton(
          status: status, onPressed: () => acknowledgements++,
        ),
      )));
      expect(find.text('確認済みとして保留を閉じる'), findsNothing);
      expect(acknowledgements, 0);
    });
  }
  for (final status in ['approved', 'rejected']) {
    testWidgets('terminal status=$status permits explicit acknowledgement', (tester) async {
      var acknowledgements = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: QualificationPhotoAcknowledgementButton(
          status: status, onPressed: () => acknowledgements++,
        ),
      )));
      expect(acknowledgements, 0);
      await tester.tap(find.text('確認済みとして保留を閉じる'));
      expect(acknowledgements, 1);
    });
  }

}
