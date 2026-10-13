class VehicleDriverMeterInput {
  const VehicleDriverMeterInput({required this.currentKm, this.manualDistanceKm});
  final double currentKm;
  final double? manualDistanceKm;

  static double? parseKilometres(String text) {
    final value = text.trim();
    if (!RegExp(r'^\d+(?:\.\d)?$').hasMatch(value)) {
      return null;
    }
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed > 99999999999.9) {
      return null;
    }
    return parsed;
  }

  static VehicleDriverMeterInput? parse({
    required double previousKm,
    required String currentText,
    required String manualDistanceText,
  }) {
    if (!previousKm.isFinite || previousKm < 0) {
      return null;
    }
    final current = parseKilometres(currentText);
    if (current == null) {
      return null;
    }
    if (current < previousKm) {
      final manual = parseKilometres(manualDistanceText);
      if (manual == null) {
        return null;
      }
      return VehicleDriverMeterInput(currentKm: current, manualDistanceKm: manual);
    }
    return VehicleDriverMeterInput(currentKm: current);
  }
}
