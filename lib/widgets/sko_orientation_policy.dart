import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Normal iPhone pages are portrait. Signature routes request only landscape.
/// Other devices return to the app's normal, platform-controlled policy ([]).
class SkoOrientationPolicy {
  static bool _phonePortrait = false;
  static int _signaturePages = 0;

  static Future<void> initialize(ui.FlutterView? view) async {
    _phonePortrait = false;
    _signaturePages = 0;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || view == null) return;
    final display = view.display;
    _phonePortrait = display.size.shortestSide / display.devicePixelRatio < 600;
    if (_phonePortrait) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  static Future<void> enterSignature() async {
    _signaturePages++;
    if (_signaturePages != 1) return;
    // iPad multitasking / OS restrictions can ignore this request. The capture
    // page withholds its entire form until a landscape viewport is available.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static Future<void> leaveSignature() async {
    if (_signaturePages == 0) return;
    _signaturePages--;
    if (_signaturePages == 0) {
      await SystemChrome.setPreferredOrientations(_phonePortrait
        ? [DeviceOrientation.portraitUp] : <DeviceOrientation>[]);
    }
  }
}
