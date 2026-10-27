import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/master_feature_availability.dart';

void main() {
  test('old server does not enable lifecycle features', () {
    final flags = MasterFeatureAvailability.fromJson({
      'vehicle_management': true, 'route_assignment': true,
    });
    expect(flags.vehicleManagement, isTrue);
    for (final key in MasterFeatureAvailability.lifecycleFeatures.keys) {
      expect(flags.lifecycleEnabled(key), isFalse);
      expect(flags.lifecycleSupported(key), isFalse);
    }
  });
  test('only real booleans advertise support', () {
    for (final bad in [null, 1, 'true', [], {}]) {
      final flags = MasterFeatureAvailability.fromJson({'affiliation_switch': bad});
      expect(flags.lifecycleSupported('affiliation_switch'), isFalse);
      expect(flags.lifecycleEnabled('affiliation_switch'), isFalse);
    }
    final flags = MasterFeatureAvailability.fromJson({
      'affiliation_switch': true, 'personal_pdf_vault': false,
    });
    expect(flags.lifecycleEnabled('affiliation_switch'), isTrue);
    expect(flags.lifecycleSupported('personal_pdf_vault'), isTrue);
    expect(flags.lifecycleEnabled('personal_pdf_vault'), isFalse);
  });
}
