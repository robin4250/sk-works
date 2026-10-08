import 'dart:typed_data';

enum CaptureFailure { camera, gps, upload }
enum CaptureDecision { confirm, retake }
enum CapturePhotoState { notRegistered, cameraFailed, captured, uploaded, uploadFailed }
enum CaptureGpsState { notRegistered, captured, failed }
enum CaptureAddressSource { liveSample, unavailable }

class CaptureShiftContext {
  const CaptureShiftContext({required this.companyId, required this.workDate,
    required this.requestedMethod, this.sourceClockInId, this.siteId, this.routeId, this.vehicleId});
  final String companyId;
  final String workDate;
  final String requestedMethod;
  final String? sourceClockInId;
  final String? siteId;
  final String? routeId;
  final String? vehicleId;
}

class CapturedPhoto {
  CapturedPhoto({required Uint8List bytes, this.capturedAt, DateTime? observedAt})
    : observedAt = observedAt ?? capturedAt ?? DateTime.now(), bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
  final DateTime? capturedAt;
  final DateTime observedAt;
}

/// Coordinates and address must come from this actual live GPS sample.
class CapturedGpsSample {
  const CapturedGpsSample({required this.latitude, required this.longitude,
    required this.sampledAt, this.address, this.accuracyM});
  final double latitude;
  final double longitude;
  final DateTime sampledAt;
  final String? address;
  final double? accuracyM;
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
  Map<String, Object?> get insertMetadata => {
    'capture_contract_version': 1,
    'gps_capture_status': switch (gpsState) {
      CaptureGpsState.captured => 'acquired',
      CaptureGpsState.failed => 'failed',
      CaptureGpsState.notRegistered => 'missing',
    },
    'photo_capture_status': switch (photoState) {
      CapturePhotoState.uploaded => 'uploaded',
      CapturePhotoState.uploadFailed => 'upload_failed',
      CapturePhotoState.cameraFailed => 'failed',
      _ => 'missing',
    },
    'gps_captured_at': gps?.sampledAt.toUtc().toIso8601String(),
    'photo_captured_at': photo?.capturedAt?.toUtc().toIso8601String(),
    'photo_observed_at': photo?.observedAt.toUtc().toIso8601String(),
    'captured_address': gps?.address,
  };

  // Storage upload never means attendance or daily report was persisted.
  bool get attendancePersisted => false;
}
