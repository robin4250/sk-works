import 'package:flutter_test/flutter_test.dart';
import '../lib/features/operations/vehicle_notification_settings_repository.dart';

void main() {
  VehicleNotificationSettings settings({bool enabled = false}) =>
      VehicleNotificationSettings.fromJson({
        'vehicle_id': 'car',
        'can_manage': true,
        'enabled': enabled,
        'configured': true,
        'user_ids': ['stopped'],
        'candidates': [
          {'user_id': 'admin', 'role': 'admin'},
          {'user_id': 'viewer', 'role': 'viewer'},
          {'user_id': 'manager', 'role': 'manager'},
          {'user_id': 'member', 'role': 'member'},
        ],
      });

  test('unknown availability remains OFF and stored unresolved IDs remain', () {
    expect(settings().enabled, isFalse);
    expect(settings().canSave(['admin']), isFalse);
    expect(settings().userIds, ['stopped']);
    expect(settings().validSelection(['stopped']), isFalse);
    expect(VehicleNotificationSettings.fromJson({}).enabled, isFalse);
  });

  test('selection requires one to three distinct actual candidates', () {
    final model = settings(enabled: true);
    expect(model.validSelection([]), isFalse);
    expect(model.validSelection(['admin']), isTrue);
    expect(model.canSave(['admin']), isTrue);
    expect(model.validSelection(['admin', 'viewer', 'manager']), isTrue);
    expect(model.validSelection(['admin', 'admin']), isFalse);
    expect(model.validSelection(['admin', 'viewer', 'manager', 'member']), isFalse);
  });
}
