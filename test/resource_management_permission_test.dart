import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/resource_management_permission.dart';

void main() {
  test('all company members can view and use resources', () {
    expect(
      ResourceManagementPermission.canViewOrUse(isCompanyMember: true),
      isTrue,
    );
  });

  test('management roles can manage vehicles and routes', () {
    for (final role in <String>['owner', 'admin', 'sub_admin', 'manager']) {
      expect(
        ResourceManagementPermission.canManage(
          role: role,
          resource: ManagedResource.vehicle,
        ),
        isTrue,
      );
      expect(
        ResourceManagementPermission.canManage(
          role: role,
          resource: ManagedResource.route,
        ),
        isTrue,
      );
    }
  });

  test('ordinary members cannot manage vehicles or routes even if delegated', () {
    expect(
      ResourceManagementPermission.canManage(
        role: 'member',
        resource: ManagedResource.vehicle,
        delegated: const <ManagedResource>{ManagedResource.vehicle},
      ),
      isFalse,
    );
    expect(
      ResourceManagementPermission.canManage(
        role: 'member',
        resource: ManagedResource.route,
        delegated: const <ManagedResource>{ManagedResource.route},
      ),
      isFalse,
    );
    expect(
      ResourceManagementPermission.shouldSoftDisableInsteadOfDelete(),
      isTrue,
    );
  });

  test('other resource delegation remains available where supported', () {
    expect(
      ResourceManagementPermission.canManage(
        role: 'member',
        resource: ManagedResource.site,
        delegated: const <ManagedResource>{ManagedResource.site},
      ),
      isTrue,
    );
  });
}
