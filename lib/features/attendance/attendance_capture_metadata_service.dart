import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional evidence enrichment. Never substitutes site data or the current time.
class AttendanceCaptureMetadataService {
  const AttendanceCaptureMetadataService({
    MethodChannel channel = const MethodChannel('sko.capture_metadata'),
    TargetPlatform? platform,
  }) : _channel = channel,
       _platform = platform;

  final MethodChannel _channel;
  final TargetPlatform? _platform;

  bool get _available => !kIsWeb && (_platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  Future<DateTime?> readPhotoCapturedAt(String localPhotoPath) async {
    if (!_available || !localPhotoPath.startsWith('/') || localPhotoPath.contains('\u0000')) {
      return null;
    }
    final raw = await _read('photoCapturedAt', {'path': localPhotoPath});
    if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$').hasMatch(raw)) {
      return null;
    }
    final value = DateTime.tryParse(raw);
    // DateTime accepts overflowing calendar fields; require an exact round trip.
    if (value == null || value.toUtc().toIso8601String().substring(0, 19) != raw.substring(0, 19)) {
      return null;
    }
    return value.toUtc();
  }

  Future<String?> reverseGeocodeCapturedLocation({
    required double latitude,
    required double longitude,
  }) async {
    if (!_available || !latitude.isFinite || !longitude.isFinite ||
        latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return null;
    }
    final raw = await _read('reverseGeocode', {'latitude': latitude, 'longitude': longitude});
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return raw.trim();
  }

  Future<Object?> _read(String method, Map<String, Object> arguments) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments).timeout(const Duration(seconds: 6));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
