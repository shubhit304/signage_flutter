import 'dart:convert';
import 'dart:io';

import 'package:signage/models/template_manager.dart';

import '../models/sse_message.dart';
import '../scheduling/template_schedule.dart';
import '../scheduling/template_schedule_parser.dart';
import '../server/local_web_server.dart';
import '../services/device_service.dart';
import '../services/local_storage_service.dart';
import '../services/template_download_service.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import 'app_state.dart';

class CommandDispatcher {
  final ApiService apiService;
  final AppState appState;
  bool _templateUpdateInProgress = false; // 🔒 LOCK
  final TemplateDownloadService _templateService = TemplateDownloadService();

  TemplateSchedule? activeSchedule;

  CommandDispatcher({required this.apiService, required this.appState});

  // ---------------------------------------------------------------------------
  // ENTRY POINT (called from SSE / Health)
  // ---------------------------------------------------------------------------

  Future<void> handle(SseMessage message) async {
    switch (message.commandType) {
      case SseCommandType.templateUpdate:
        await handleTemplateUpdate(message);
        break;

      case SseCommandType.scheduledUpdate:
        _handleScheduledUpdate(message);
        break;

      case SseCommandType.deleteInstantTemplate:
      case SseCommandType.deleteScheduledTemplate:
        _handleDeleteTemplate(message);
        break;

      case SseCommandType.volumeUpdate:
        _handleVolume(message);
        break;

      case SseCommandType.brightnessUpdate:
        _handleBrightness(message);
        break;

      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 🔁 LOAD DEFAULT TEMPLATE ON APP START (LeftScreen)
  // ---------------------------------------------------------------------------

  Future<void> loadDefaultTemplateIfExists() async {
    try {
      final baseDir = await _templateService.getTemplateDir();
      final defaultHtml = '$baseDir/LeftScreen/LeftScreen.html';

      final file = File(defaultHtml);

      if (!file.existsSync()) {
        print('ℹ️ Default template LeftScreen not found');
        return;
      }

      print('⭐ Loading default template: LeftScreen');

      // Stop anything running
      appState.hideTemplate();
      appState.clearTemplate();

      appState.startTemplateLoading('LOADING DEFAULT TEMPLATE', progress: 0.2);

      await _loadTemplate(defaultHtml);

      appState.showTemplateView();
      appState.stopTemplateLoading();
    } catch (e) {
      print('❌ Failed to load default template: $e');
      appState.stopTemplateLoading();
    }
  }

  // ---------------------------------------------------------------------------
  // TEMPLATE UPDATE (WinForms: TemplateUpdate case)
  // ---------------------------------------------------------------------------

  Future<void> handleTemplateUpdate(SseMessage msg) async {
    if (_templateUpdateInProgress) {
      print('⏳ Template update already running');
      return;
    }

    _templateUpdateInProgress = true;

    try {
      final templateName = msg.templateName;
      if (templateName == null || templateName.isEmpty) return;

      // 🔴 HARD STOP CURRENT TEMPLATE
      appState.hideTemplate();
      appState.clearTemplate();

      // 🧹 DELETE OLD FILES (🔥 THIS IS THE FIX)
      //await _clearAllTemplates();

      // 🟡 DOWNLOADING
      appState.startTemplateLoading('DOWNLOADING TEMPLATE', progress: 0.15);
      AppToast.show('Downloading template');
      final templatePath = await _downloadAndPrepareTemplate(templateName);
      if (templatePath == null) return;

      AppToast.show('Temp receive: $templatePath');
      await TemplateManager.setActiveTemplate(templatePath);
      //await TemplateManager.restartWithTemplate(templatePath);

      // 🟠 LOADING
      appState.updateLoading('LOADING CONTENT', 0.75);
      AppToast.show('Template loaded');
      await _loadTemplate(templatePath);
      AppToast.show('Template displayed');

      // 🟢 FINALIZING
      appState.updateLoading('FINALIZING', 0.95);

      await Future.delayed(const Duration(milliseconds: 500));
      appState.showTemplateView();

      await _updateTemplateStatus(
        templateName: templateName,
        status: 'Template updated',
      );
    } finally {
      appState.stopTemplateLoading();
      _templateUpdateInProgress = false;
    }
  }

  // Future<void> _clearAllTemplates() async {
  //   final baseDir = await _templateService.getTemplateDir();
  //   final dir = Directory(baseDir);
  //
  //   if (!dir.existsSync()) return;
  //
  //   print('🧹 Clearing old templates...');
  //
  //   for (final entity in dir.listSync(recursive: false)) {
  //     try {
  //       if (entity is Directory) {
  //         entity.deleteSync(recursive: true);
  //         print('🗑 Deleted folder: ${entity.path}');
  //       } else if (entity is File && entity.path.endsWith('.zip')) {
  //         entity.deleteSync();
  //         print('🗑 Deleted zip: ${entity.path}');
  //       }
  //     } catch (e) {
  //       print('❌ Failed to delete ${entity.path}: $e');
  //     }
  //   }
  // }
  Future<String?> _downloadAndPrepareTemplate(String templateName) async {
    try {
      AppToast.show('Downloading template');

      // 🔥 ONE native call does everything:
      // - download zip
      // - unzip
      // - resolve HTML path
      final htmlPath = await _templateService.downloadAndPrepareTemplate(
        templateName,
      );

      if (htmlPath == null || htmlPath.isEmpty) {
        print('❌ Native download/unzip failed');
        return null;
      }

      AppToast.show('Download template success');

      print('✅ Using existing HTML: $htmlPath');
      return htmlPath;
    } catch (e) {
      print('❌ _downloadAndPrepareTemplate failed: $e');
      return null;
    }
  }

  // Future<String?> _downloadAndPrepareTemplate(String templateName) async {
  //   final cleanName = templateName.contains('\\')
  //       ? templateName.split('\\').last
  //       : templateName;
  //
  //   // 1️⃣ Download ZIP
  //   final zipOk = await _templateService.downloadZip(templateName);
  //   if (!zipOk) return null;
  //
  //   // 2️⃣ Extract ZIP
  //   final extractOk = await _templateService.extractTemplate(cleanName);
  //   if (!extractOk) return null;
  //
  //   // 3️⃣ Resolve template directory
  //   final baseDir = await _templateService.getTemplateDir();
  //   final templateDir = Directory('$baseDir/$cleanName');
  //
  //   if (!templateDir.existsSync()) {
  //     print('❌ Template directory not found');
  //     return null;
  //   }
  //
  //   // 4️⃣ USE EXISTING HTML (IMPORTANT)
  //   final htmlFile = File('${templateDir.path}/$cleanName.html');
  //   AppToast.show('Download template success');
  //   if (!htmlFile.existsSync()) {
  //     print('❌ HTML file missing: ${htmlFile.path}');
  //     return null;
  //   }
  //
  //   print('✅ Using existing HTML: ${htmlFile.path}');
  //   return htmlFile.path;
  // }

  Future<String?> getLocalIpAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback) {
          return addr.address; // e.g. 192.168.1.25
        }
      }
    }
    return null;
  }

  // Future<void> _loadTemplate(String htmlPath) async {
  //   final templatesRoot = await _templateService.getTemplateDir();
  //   await LocalWebServer.start(templatesRoot, port: 8080);
  //
  //   final relativePath = htmlPath.replaceFirst('$templatesRoot/', '');
  //   final url = 'http://localhost:8080/$relativePath';
  //
  //   print('🧠 Native WebView loading: $url');
  //   AppToast.show('Loading template on screen...');
  //   // 🔥 Native WebView lifecycle
  //   await NativeWebViewBridge.hide();
  //   await NativeWebViewBridge.clear();
  //
  //   await NativeWebViewBridge.loadTemplate(url);
  //   await NativeWebViewBridge.show();
  //
  //   // Keep state for backend health reporting
  //   appState.setTemplate(url);
  // }

  // Future<void> _loadTemplate(String htmlPath) async {
  //   final templatesRoot = await _templateService.getTemplateDir();
  //
  //   // 🔥 Start server on all interfaces
  //   await LocalWebServer.start(templatesRoot, port: 8080);
  //
  //   final url = await _buildTemplateUrl(htmlPath);
  //
  //   print('🧠 WebView loading: $url');
  //   AppToast.show('Loading template on screen...');
  //
  //   appState.setTemplate(url);
  // }

  Future<void> _loadTemplate(String htmlPath) async {
    print('🧠 WebView loading FILE directly: $htmlPath');
    AppToast.show('Loading template on screen...');

    // ✅ STORE FILE PATH, NOT URL
    appState.setTemplate(htmlPath);
  }

  // Future<String> _buildTemplateUrl(String htmlPath) async {
  //   final templatesRoot = await _templateService.getTemplateDir();
  //
  //   // Convert absolute file path → relative web path
  //   final relativePath = htmlPath.startsWith(templatesRoot)
  //       ? htmlPath.replaceFirst('$templatesRoot/', '')
  //       : htmlPath;
  //
  //   final ip = await getLocalIpAddress();
  //   final host = ip ?? 'localhost';
  //
  //   return 'http://$host:8080/$relativePath';
  // }

  // ---------------------------------------------------------------------------
  // SCHEDULED UPDATE
  // ---------------------------------------------------------------------------

  Future<void> _handleScheduledUpdate(SseMessage msg) async {
    final templateName = msg.templateName;
    if (templateName == null || templateName.isEmpty) return;
    AppToast.show('Scheduled content started');
    // 🧹 CLEAR OLD FIRST
    //await _clearAllTemplates();
    print('📥 Scheduled template received → downloading');

    // 🔽 DOWNLOAD + EXTRACT (same as WinForms)
    final templatePath = await _downloadAndPrepareTemplate(templateName);
    if (templatePath == null) {
      print('❌ Scheduled template download failed');
      return;
    }

    // 🔒 Store template path (but DO NOT load)
    appState.setTemplate(templatePath, scheduled: true);

    // 🗓 Parse & store schedule
    if (msg.templateSchedule != null) {
      final schedule = TemplateScheduleParser.parse(msg.templateSchedule!);
      activeSchedule = schedule;
      appState.setSchedule(schedule);
    }

    // 🔁 Update backend status (same as C#)
    await _updateTemplateStatus(
      templateName: templateName,
      status: 'Template received',
    );

    print('✅ Scheduled template ready (waiting for time window)');
  }
  //
  // Future<void> loadLocalTemplate(
  //   String htmlPath, {
  //   bool scheduled = false,
  // }) async {
  //   print('🧠 Loading local scheduled template: $htmlPath');
  //
  //   appState.hideTemplate();
  //   // await NativeWebViewBridge.hide();
  //   // await NativeWebViewBridge.clear();
  //
  //   final templatesRoot = await _templateService.getTemplateDir();
  //   await LocalWebServer.start(templatesRoot, port: 8080);
  //
  //   final url = await _buildTemplateUrl(htmlPath);
  //
  //   print('🧠 WebView loading (scheduled): $url');
  //   AppToast.show('🧠 WebView loading (scheduled)');
  //   appState.setTemplate(url, scheduled: scheduled);
  //   appState.showTemplateView();
  // }

  Future<void> loadLocalTemplate(
    String htmlPath, {
    bool scheduled = false,
  }) async {
    print('🧠 Loading local scheduled template: $htmlPath');
    AppToast.show('Loading scheduled template');

    appState.hideTemplate();

    // ✅ DIRECT FILE PATH
    appState.setTemplate(htmlPath, scheduled: scheduled);
    appState.showTemplateView();
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------

  void _handleDeleteTemplate(SseMessage msg) {
    appState.clearTemplate();
  }

  // ---------------------------------------------------------------------------
  // VOLUME / BRIGHTNESS
  // ---------------------------------------------------------------------------

  void _handleVolume(SseMessage msg) {
    print('🔊 Volume update: ${msg.volumeLevel}');
  }

  void _handleBrightness(SseMessage msg) {
    print('🔆 Brightness update: ${msg.brightnessLevel}');
  }

  String _getSafeTemplateName(String name) {
    return name.contains('\\') ? name.split('\\').last : name;
  }

  Future<String> _getTemplateHtmlPath(String templateName) async {
    final safeName = _getSafeTemplateName(templateName);
    final dir = await _templateService.getTemplateDir();
    return '$dir/$safeName/$safeName.html';
  }

  // ---------------------------------------------------------------------------
  // UPDATE STATUS (WinForms UpdateStatus)
  // ---------------------------------------------------------------------------

  Future<void> _updateTemplateStatus({
    required String templateName,
    required String status,
  }) async {
    final primaryId = await LocalStorageService.getPrimaryId();
    final mac = await DeviceService.getDeviceId();

    if (primaryId == null) return;

    await apiService.send(
      endpoint: 'Screen/UpdateStatus',
      method: 'POST',
      body: {
        'ScreenID': primaryId,
        'Mac_Product_ID': mac,
        'UpdateType': 'TemplateUpdateStatus',
        'Status': status,
        'TemplateName': templateName,
      },
    );
  }
}
