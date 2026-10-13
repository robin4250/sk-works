import 'gps_photo_capture_result.dart';

/// Isolated capture draft coordinator. Ports do not create attendance or reports.
class GpsPhotoCaptureController {
  GpsPhotoCaptureController({required this.camera, required this.sampleGps,
    required this.upload, required this.prompt, required this.now,
    this.maximumGpsAge = const Duration(seconds: 30)});
  final Future<CapturedPhoto?> Function() camera;
  final Future<CapturedGpsSample> Function() sampleGps;
  final Future<String> Function(CapturedPhoto, CaptureShiftContext) upload;
  final Future<CaptureDecision> Function(CaptureFailure) prompt;
  final DateTime Function() now;
  final Duration maximumGpsAge;

  Future<GpsPhotoCaptureResult> capture(CaptureShiftContext context) async {
    while (true) {
      final attemptedAt = now();
      CapturedPhoto? photo;
      CapturedGpsSample? gps;
      var gpsState = CaptureGpsState.notRegistered;
      var photoState = CapturePhotoState.notRegistered;
      String? path;
      try {
        photo = await camera();
      } catch (_) {
        photoState = CapturePhotoState.cameraFailed;
        if (await prompt(CaptureFailure.camera) == CaptureDecision.retake) { continue; }
      }
      if (photo == null) {
        if (photoState != CapturePhotoState.cameraFailed &&
            await prompt(CaptureFailure.camera) == CaptureDecision.retake) { continue; }
        return GpsPhotoCaptureResult(context: context, attemptedAt: attemptedAt,
          photoState: photoState, gpsState: gpsState);
      }
      photoState = CapturePhotoState.captured;
      try {
        final sample = await sampleGps();
        final delta = sample.sampledAt.difference(photo.capturedAt ?? photo.observedAt).abs();
        if (!sample.isValid || delta > maximumGpsAge) { throw StateError('invalid_capture_sample'); }
        gps = sample;
        gpsState = CaptureGpsState.captured;
      } catch (_) {
        gpsState = CaptureGpsState.failed;
        if (await prompt(CaptureFailure.gps) == CaptureDecision.retake) { continue; }
      }
      try {
        final uploaded = await upload(photo, context);
        if (uploaded.trim().isEmpty) { throw StateError('upload_unconfirmed'); }
        path = uploaded;
        photoState = CapturePhotoState.uploaded;
      } catch (_) {
        photoState = CapturePhotoState.uploadFailed;
        if (await prompt(CaptureFailure.upload) == CaptureDecision.retake) { continue; }
      }
      return GpsPhotoCaptureResult(context: context, attemptedAt: attemptedAt,
        photoState: photoState, gpsState: gpsState, photo: photo, gps: gps, storagePath: path);
    }
  }
}
