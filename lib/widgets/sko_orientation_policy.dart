import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Preserve the normal iPhone portrait policy; signatures temporarily rotate.
/// iPad and other platforms retain their existing platform orientation policy.
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
    if (!_phonePortrait) return;
    _signaturePages++;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static Future<void> leaveSignature() async {
    if (!_phonePortrait || _signaturePages == 0) return;
    _signaturePages--;
    if (_signaturePages == 0) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }
}
