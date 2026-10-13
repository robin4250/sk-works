import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/site_chat_lifecycle.dart';

void main() {
  test('site registration creates chat and attendance joins worker', () {
    expect(SiteChatLifecycle.shouldCreateChatOnSiteRegistration(), isTrue);
    expect(
      SiteChatLifecycle.shouldAutoJoinOnAttendance(
        attendanceRecorded: true,
        alreadyMember: false,
      ),
      isTrue,
    );
  });

  test('managers can enter without attendance', () {
    for (final role in <String>['owner', 'admin', 'sub_admin']) {
      expect(SiteChatLifecycle.canManagerEnterWithoutAttendance(role), isTrue);
    }
    expect(SiteChatLifecycle.canManagerEnterWithoutAttendance('member'), isFalse);
  });

  test('closing site archives history and public card excludes financial data', () {
    expect(SiteChatLifecycle.shouldArchiveOnSiteClosure(), isTrue);
    expect(SiteChatLifecycle.publicSiteCardFields, contains('address'));
    expect(SiteChatLifecycle.publicSiteCardFields, isNot(contains('unit_price')));
    expect(SiteChatLifecycle.publicSiteCardFields, isNot(contains('billing_company')));
  });
}
