import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/template_download_dto.dart';
import 'device_service.dart';
import 'local_storage_service.dart';

class TemplateDownloadService {
  static const MethodChannel _zipChannel =
  MethodChannel('native_zip');

  /// 🔥 FULLY NATIVE: download + unzip + return html path
  Future<String?> downloadAndPrepareTemplate(String templateName) async {
    try {
      final primaryId = await LocalStorageService.getPrimaryId();
      final mac = await DeviceService.getDeviceId();

      if (primaryId == null) {
        debugPrint('❌ PrimaryScreenID missing');
        return null;
      }

      final dto = TemplateDownloadDto(
        screenId: primaryId,
        macProductId: mac,
        templateName: templateName,
      );

      final result =
      await _zipChannel.invokeMethod<Map>('downloadAndUnzip', {
        'apiUrl':
        'https://117.219.19.154:8021/api/Task/DownloadTemplateFile',
        'templateName': templateName,
        'body': jsonEncode(dto.toJson()),
      });

      if (result == null || result['success'] != true) {
        debugPrint('❌ Native download failed');
        return null;
      }

      final htmlPath = result['htmlPath'] as String?;
      debugPrint('✅ Template ready at: $htmlPath');

      return htmlPath;
    } catch (e, stack) {
      debugPrint('❌ downloadAndPrepareTemplate error: $e');
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  /// Used by web server
  Future<String> getTemplateDir() async {
    final result =
    await _zipChannel.invokeMethod<String>('getTemplatesRoot');
    return result!;
  }
}
