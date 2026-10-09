import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../lib/features/payroll/resident_tax_capability.dart';

void main() {
  test('only confirmed legacy includes fixed amount in general save', () {
    expect(residentTaxUsesGeneralSave(ResidentTaxCapability.legacy), isTrue);
    expect(residentTaxUsesGeneralSave(ResidentTaxCapability.timeline), isFalse);
    expect(residentTaxUsesGeneralSave(ResidentTaxCapability.unknown), isFalse);
  });
  test('only supported integer version adopts timeline', () async {
    expect(await readResidentTaxCapability(() async => 1), ResidentTaxCapability.timeline);
    for (final value in [null, '1', 1.0, 2]) {
      expect(await readResidentTaxCapability(() async => value), ResidentTaxCapability.unknown);
    }
  });
  test('confirmed missing RPC preserves legacy editing; other failures do not', () async {
    for (final code in ['PGRST202', '42883']) {
      expect(await readResidentTaxCapability(() async => throw PostgrestException(message: 'missing', code: code)), ResidentTaxCapability.legacy);
    }
    expect(await readResidentTaxCapability(() async => throw const PostgrestException(message: 'denied', code: '42501')), ResidentTaxCapability.unknown);
    expect(await readResidentTaxCapability(() async => throw Exception('network')), ResidentTaxCapability.unknown);
  });
}
