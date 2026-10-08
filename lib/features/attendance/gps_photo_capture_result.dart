import 'dart:typed_data';

enum CaptureFailure { camera, gps, upload }
enum CaptureDecision { confirm, retake }
enum CapturePhotoState { notRegistered, cameraFailed, captured, uploaded, uploadFailed }
enum CaptureGpsState { notRegistered, captured, failed }
enum CaptureAddressSource { liveSample, unavailable }

class CaptureShiftContext {
  const CaptureShiftContext({required this.companyId, required this.workDate,
    required this.requestedMethod, this.sourceClockInId, this.siteId, this.routeId});
  final String companyId;
  final String workDate;
  final String requestedMethod;
  final String? sourceClockInId;
  final String? siteId;
  final String? routeId;
}

class CapturedPhoto {
  CapturedPhoto({required Uint8List bytes, required this.capturedAt})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
  final DateTime capturedAt;
}

/// Coordinates and address must come from this actual live GPS sample.
class CapturedGpsSample {
  const CapturedGpsSample({required this.latitude, required this.longitude,
    required this.sampledAt, this.address});
  final double latitude;
  final double longitude;
  final DateTime sampledAt;
  final String? address;
  bool get isValid => latitude.isFinite && longitude.isFinite &&
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}

class GpsPhotoCaptureResult {
  const GpsPhotoCaptureResult({required this.context, required this.attemptedAt,
    required this.photoState, required this.gpsState, this.photo, this.gps,
    this.storagePath});
  final CaptureShiftContext context;
  final DateTime attemptedAt;
  final CapturePhotoState photoState;
  final CaptureGpsState gpsState;
  final CapturedPhoto? photo;
  final CapturedGpsSample? gps;
  final String? storagePath;
  CaptureAddressSource get addressSource => gps?.address?.trim().isNotEmpty == true
    ? CaptureAddressSource.liveSample : CaptureAddressSource.unavailable;
  // Storage upload never means attendance or daily report was persisted.
  bool get attendancePersisted => false;
}
