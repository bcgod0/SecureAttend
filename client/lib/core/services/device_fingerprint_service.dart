import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Generates and caches a stable device fingerprint hash.
///
/// Android: android_id + model + brand + hardware
/// iOS:     identifierForVendor + model + systemName
/// Web:     Stored UUID (localStorage via flutter_secure_storage)
/// Windows: machine guid + model
class DeviceFingerprintService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const _storage = FlutterSecureStorage();
  static const _fpKey = 'device_fingerprint';

  /// Returns a stable hex fingerprint for the current device.
  static Future<String> getFingerprint() async {
    // Check cache first
    final cached = await _storage.read(key: _fpKey);
    if (cached != null && cached.isNotEmpty) return cached;

    final fp = await _compute();
    await _storage.write(key: _fpKey, value: fp);
    return fp;
  }

  /// Returns metadata about the device for the registration payload.
  static Future<Map<String, String>> getDeviceInfo() async {
    try {
      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        return {
          'platform': 'web',
          'browser': info.browserName.name,
          'userAgent': info.userAgent ?? 'unknown',
        };
      }
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return {
          'platform': 'android',
          'model': info.model,
          'brand': info.brand,
          'version': info.version.release,
          'sdk': info.version.sdkInt.toString(),
        };
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return {
          'platform': 'ios',
          'model': info.model,
          'systemVersion': info.systemVersion,
          'name': info.name,
        };
      }
      if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return {
          'platform': 'windows',
          'computerName': info.computerName,
          'userName': info.userName,
        };
      }
    } catch (_) {}
    return {'platform': 'unknown'};
  }

  static Future<String> _compute() async {
    String raw;
    try {
      if (kIsWeb) {
        // Web: generate a persistent UUID stored in secure storage
        const keyId = 'web_device_id';
        var id = await _storage.read(key: keyId);
        if (id == null) {
          id = const Uuid().v4();
          await _storage.write(key: keyId, value: id);
        }
        raw = 'web:$id';
      } else if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        raw = [
          info.id, // android_id equivalent
          info.model,
          info.brand,
          info.hardware,
          info.fingerprint,
        ].join(':');
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        raw = [
          info.identifierForVendor ?? '',
          info.model,
          info.systemName,
        ].join(':');
      } else if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        raw = [
          info.deviceId,
          info.computerName,
        ].join(':');
      } else {
        raw = const Uuid().v4();
      }
    } catch (_) {
      raw = const Uuid().v4();
    }

    final bytes = utf8.encode(raw);
    return sha256.convert(bytes).toString();
  }
}

/// Riverpod provider for the device fingerprint
final deviceFingerprintProvider = FutureProvider<String>((ref) async {
  return DeviceFingerprintService.getFingerprint();
});
