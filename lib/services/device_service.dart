import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static const _storage = FlutterSecureStorage();
  static const _deviceKey = 'app_device_id';

  /// Acts as MAC address replacement on Android
  /* static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;

      // ANDROID_ID is the only stable, Play-Store-safe identifier
      return android.id;
    }

    return 'unknown-device';
  } */

  static Future<String> getDeviceId() async {
    String? id = await _storage.read(key: _deviceKey);

    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _deviceKey, value: id);
    }

    return id;
  }

  static Future<Map<String, String>> getScreenResolution() async {
    final size = await _getScreenSize();
    return {'width': size.$1.toString(), 'height': size.$2.toString()};
  }

  static Future<(int, int)> _getScreenSize() async {
    final window = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = window.physicalSize;
    return (size.width.toInt(), size.height.toInt());
  }
}
