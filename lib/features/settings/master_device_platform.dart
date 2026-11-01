import 'dart:io';
import 'package:flutter/services.dart';

/// A display classification, never proof that a device or Apple identity is trusted.
class MasterDevicePlatform {
  const MasterDevicePlatform(this.type, this.name);
  final String type;
  final String name;
  static const channel = MethodChannel('sko.device_platform');

  static Future<MasterDevicePlatform> detect({String? operatingSystem}) async {
    final os = operatingSystem ?? Platform.operatingSystem;
    if (os == 'macos') return const MasterDevicePlatform('mac', 'SKO Master MacBook / Mac');
    if (os == 'ios') {
      final type = await channel.invokeMethod<String>('deviceType')
          .timeout(const Duration(seconds: 5));
      if (type == 'ipad') return const MasterDevicePlatform('ipad', 'SKO Master iPad');
      if (type == 'iphone') return const MasterDevicePlatform('iphone', 'SKO Master iPhone');
      throw StateError('端末の種類を確認できません。アプリを更新して再確認してください。');
    }
    return const MasterDevicePlatform('other', 'SKO Master Device');
  }
}
