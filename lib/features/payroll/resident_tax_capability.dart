import 'package:supabase_flutter/supabase_flutter.dart';

enum ResidentTaxCapability { legacy, timeline, unknown }

bool residentTaxUsesGeneralSave(ResidentTaxCapability capability) =>
    capability == ResidentTaxCapability.legacy;

Future<ResidentTaxCapability> readResidentTaxCapability(
    Future<dynamic> Function() readVersion) async {
  try {
    final version = await readVersion();
    return version is int && version == 1
        ? ResidentTaxCapability.timeline
        : ResidentTaxCapability.unknown;
  } on PostgrestException catch (error) {
    return error.code == 'PGRST202' || error.code == '42883'
        ? ResidentTaxCapability.legacy
        : ResidentTaxCapability.unknown;
  } catch (_) {
    return ResidentTaxCapability.unknown;
  }
}
