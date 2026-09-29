import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/resource_management_permission.dart';

void main() {
  test('all company members can view and use resources', () {
    expect(ResourceManagementPermission.canViewOrUse(isCompanyMember: true), isTrue);
  });

  test('admin sub-admin and delegated members can manage', () {
    for (final role in <String>['owner', 'admin', 'sub_admin']) {
      expect(
        ResourceManagementPermission.canManage(
          role: role,
          resource: ManagedResource.vehicle,
        ),
        isTrue,
      );
    }
    expect(
      ResourceManagementPermission.canManage(
        role: 'member',
        resource: ManagedResource.route,
        delegated: const <ManagedResource>{ManagedResource.route},
      ),
      isTrue,
    );
  });

  test('ordinary members cannot manage without delegated permission', () {
    expect(
      ResourceManagementPermission.canManage(
        role: 'member',
        resource: ManagedResource.vehicle,
      ),
      isFalse,
    );
    expect(ResourceManagementPermission.shouldSoftDisableInsteadOfDelete(), isTrue);
  });
}
