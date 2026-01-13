import 'dart:convert';
import 'package:flutter/services.dart';

class NativeZipBridge {
  static const MethodChannel _channel = MethodChannel('native_zip');

  static Future<bool> downloadAndUnzip({
    required String templateName,
    required Map<String, dynamic> body,
  }) async {
    final result = await _channel.invokeMethod<bool>('downloadAndUnzip', {
      'apiUrl': 'https://117.219.19.154:8021/api/Task/DownloadTemplateFile',
      'templateName': templateName,
      'body': jsonEncode(body),
    });

    return result ?? false;
  }
}
