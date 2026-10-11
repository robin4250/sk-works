typedef RecordedLocationAddressLookup = Future<String?> Function({
  required double latitude,
  required double longitude,
});

/// Display enrichment of recorded coordinates; never reads the current location.
class DailyReportEvidenceAddressResolver {
  DailyReportEvidenceAddressResolver({required this.reverseGeocode});

  final RecordedLocationAddressLookup reverseGeocode;
  final Map<String, Future<String?>> _lookups = {};

  Future<String?> resolve({
    String? savedAddress,
    double? latitude,
    double? longitude,
    String? gpsStatus,
    bool timeOnly = false,
  }) async {
    if (timeOnly) return null;
    final saved = normalizeRecordedAddress(savedAddress);
    if (saved != null) return saved;
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        (gpsStatus != null && gpsStatus != 'acquired')) {
      return null;
    }
    return _lookups.putIfAbsent('$latitude,$longitude', () async {
      try {
        return normalizeRecordedAddress(
          await reverseGeocode(latitude: latitude, longitude: longitude),
        );
      } catch (_) {
        // Optional address failure must not hide recorded coordinates or photos.
        return null;
      }
    });
  }
}

String? normalizeRecordedAddress(String? value) {
  var address = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (address == null || address.isEmpty) return null;
  // Core Location returns prefecture/city/town/street-number components with
  // spaces. Keep numbers separate while rendering Japanese block addresses.
  if (RegExp(r'^(北海道|.{2,3}[都府県])').hasMatch(address)) {
    address = address.replaceAllMapped(
      RegExp(r'(\d)\s+(?=\d)'),
      (m) => '${m[1]}-',
    );
    address = address.replaceAll(RegExp(r'\s+'), '');
    address = address.replaceAllMapped(
      RegExp(r'(\d+)丁目(?=\d)'),
      (m) => '${m[1]}-',
    );
    address = address.replaceAllMapped(
      RegExp(r'(\d+)番(?:地)?(?=\d)'),
      (m) => '${m[1]}-',
    );
    address = address.replaceAll(RegExp(r'(?<=\d)(番地|番|号)$'), '');
  }
  return address;
}
