import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:signage/models/template_manager.dart';
import '../services/local_storage_service.dart';
import '../services/location_service.dart';
import '../services/screen_status_service.dart';
import '../models/screen_register_dto.dart';
import '../models/screen_health_details_dto.dart';
import '../models/sse_message.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../services/screen_health_service.dart';
import '../services/screen_registration_service.dart';
import '../services/connectivity_service.dart';
import '../scheduling/template_schedule_evaluator.dart';
import '../services/sse_client.dart';
import '../utils/app_toast.dart';
import '../utils/crc32.dart';
import 'command_dispatcher.dart';
import 'app_state.dart';

class AppController {
  final ApiService apiService;
  final AppState appState = AppState();
  Timer? _scheduleTimer;

  late final SseClient sseClient;

  late final CommandDispatcher dispatcher;
  late final ScreenHealthService healthService;

  Timer? _healthTimer;

  AppController({required this.apiService}) {
    print('🟢 AppController CONSTRUCTOR called');
    print('🌐 Base URL => ${apiService.baseUrl}');
    sseClient = SseClient(
      '${apiService.baseUrl}sse/updates', // ✅ correct
    );

    dispatcher = CommandDispatcher(apiService: apiService, appState: appState);
    healthService = ScreenHealthService(apiService);
  }

  /// Entry point (EXACT role of WinForms ConnectionThread)
  void start() {
    print('🚀 AppController.start() CALLED');
    AppToast.show('Connecting to server');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startConnectionFlow();
    });
  }

  Future<void> _startConnectionFlow() async {
    print('🔵 _startConnectionFlow STARTED');

    final connectivityService = ConnectivityService(apiService);
    final screenStatusService = ScreenStatusService(apiService);
    final registrationService = ScreenRegistrationService(apiService);
    // 1️⃣ CHECK CONNECTIVITY
    print('1️⃣ Checking backend connectivity...');

    /// ANDROID_ID = MAC + DeviceId (Android limitation)
    final deviceId = await DeviceService.getDeviceId();
    final resolution = await DeviceService.getScreenResolution();
    // 2️⃣ REGISTER SCREEN
    print('2️⃣ Registering screen...');
    print('🆔 Device ID => $deviceId');
    print('🧾 Resolution => $resolution');

    /// 🔐 CRC32 Connection Code (EXACT WinForms logic)
    final connectionCode = _generateConnectionCode(
      playerType: 'ANDROID',
      macAddress: deviceId,
    );

    appState.setConnectionCode(connectionCode);

    // 1️⃣ CHECK CONNECTIVITY
    while (true) {
      if (await connectivityService.checkConnectivity()) {
        AppToast.show('Backend connected');

        print('✅ Backend connectivity OK');
        break;
      }
      AppToast.show('Waiting for backend...');

      print('⏳ Waiting for backend...');
      await Future.delayed(const Duration(seconds: 10));
    }

    Map<String, dynamic> locationData = {};

    try {
      locationData = await LocationService.getCurrentLocation();
      print('📍 Location fetched: $locationData');
    } catch (e) {
      print('⚠️ Location unavailable: $e');
    }

    final dto = ScreenRegisterDTO(
      macProductId: deviceId,
      deviceId: deviceId,
      tagName: 'Android Player',
      location: locationData['location'] ?? 'Unknown',
      city: locationData['city'] ?? 'Unknown',
      uniqueCode: connectionCode,
      latitude: locationData['latitude'] ?? 0.0,
      longitude: locationData['longitude'] ?? 0.0,
      geoCode: locationData['geoCode'] ?? '',
      playerType: 'ANDROID',
      screenWidth: resolution['width']!,
      screenHeight: resolution['height']!,
    );
    AppToast.show('Registering screen');

    final screenId = await registrationService.registerScreen(dto);

    // ❌ Hard failure
    if (screenId == -1) {
      AppToast.show('Screen registration failed', bgColor: Colors.red);

      print('❌ Screen registration API error');
      return;
    }

    if (screenId != null) {
      appState.setRegistered(screenId);

      await LocalStorageService.savePrimaryId(screenId);

      AppToast.show('Screen approved');
      print('✅ Screen approved instantly');
    } else {
      AppToast.show('Waiting for approval');
      print('🟡 Screen registered (pending approval)');
    }

    while (!appState.isClientRegistered) {
      final screenId = await screenStatusService.isScreenRegistered(
        macProductId: deviceId,
      );

      if (screenId != null) {
        appState.setRegistered(screenId);

        await LocalStorageService.savePrimaryId(screenId); // ✅ FIXED

        AppToast.show('Screen approved');
        print('✅ Screen approved with ID $screenId');
        break;
      }

      print('⏳ Screen pending approval...');
      await Future.delayed(const Duration(seconds: 15));
    }

    // 4️⃣ START HEALTH + SSE (EXACT WinForms order)
    _startHealthTimer(deviceId);
    _startSse();

    // ⭐ START SCHEDULE LOOP
    _startScheduleTimer();

    // ⭐ Load default template if present (LeftScreen)
    //await dispatcher.loadDefaultTemplateIfExists();

    final lastTemplate = await TemplateManager.getActiveTemplate();
    if (lastTemplate != null) {
      AppToast.show('Temp load after restart: $lastTemplate');

      // Stop anything running
      appState.hideTemplate();
      appState.clearTemplate();

      appState.startTemplateLoading('LOADING DEFAULT TEMPLATE', progress: 0.2);

      appState.setTemplate(lastTemplate ?? 'default');

      appState.showTemplateView();
      appState.stopTemplateLoading();
    }
  }

  void _startScheduleTimer() {
    _scheduleTimer?.cancel();

    _scheduleTimer = Timer.periodic(
      const Duration(minutes: 1), // same idea as WinForms polling
      (_) => _evaluateSchedule(),
    );

    print('⏱ Schedule evaluation timer started');
  }

  Future<void> _evaluateSchedule() async {
    final schedule = appState.activeSchedule;

    // No schedule → nothing to do
    if (schedule == null) return;

    final shouldShow = TemplateScheduleEvaluator.shouldShowScheduledTemplate(
      schedule,
    );

    final isExpired = TemplateScheduleEvaluator.isScheduleExpired(schedule);

    // 🟢 CASE 1: Schedule should start
    if (shouldShow && !appState.isShowingScheduledTemplate) {
      print('📅 Scheduled template ACTIVE → switching');

      appState.markScheduledPlaying(true);

      final localHtmlPath = appState.scheduledTemplateFile;

      if (localHtmlPath == null) {
        print('❌ No scheduled template HTML found');
        return;
      }

      await dispatcher.loadLocalTemplate(localHtmlPath, scheduled: true);

      return;
    }

    // 🔴 CASE 2: Schedule expired → restore to normal
    if (isExpired && appState.isShowingScheduledTemplate) {
      print('⏰ Schedule expired → stopping scheduled template');

      appState.markScheduledPlaying(false);
      appState.clearSchedule();

      // 🔴 HARD STOP TEMPLATE
      appState.hideTemplate();
      appState.clearTemplate();

      print('🟡 Player idle → waiting for next command');
    }
  }

  // --------------------------------------------------------------------------
  // 🔁 HEALTH TIMER (EXACT SendHealthDetails equivalent)
  // --------------------------------------------------------------------------

  void _startHealthTimer(String macAddress) {
    _healthTimer?.cancel();
    print('💓 Starting HEALTH TIMER');
    AppToast.show('Health service started');

    _healthTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
      if (!appState.isClientRegistered) return;
      AppToast.show('Health ping sent');
      final dto = ScreenHealthDetailsDTO(
        screenId: appState.screenId!,
        macProductId: macAddress,
        templateName: appState.activeTemplateFile ?? '',
        totalSpace: 0, // TODO: Android storage calc
        filledSpace: 0, // TODO: Android storage calc
      );

      final cmd = await healthService.sendHealth(dto);

      /// WinForms: CommandParsing(msg)
      if (cmd != null && cmd.commandType != SseCommandType.templateUpdate) {
        dispatcher.handle(cmd);
      }
    });

    print('💓 Health timer started');
  }

  // --------------------------------------------------------------------------
  // 📡 SSE
  // --------------------------------------------------------------------------

  void _startSse() async {
    print('📡 _startSse() called');
    AppToast.show('Starting live updates');

    final primaryId = await LocalStorageService.getPrimaryId();

    if (primaryId == null) {
      AppToast.show(
        'Live updates disabled (Screen not registered)',
        bgColor: Colors.orange,
      );
      print('❌ PrimaryId not found, SSE ignored');
      return;
    }

    print('📡 SSE URL => ${apiService.baseUrl}sse/updates');
    print('🆔 PrimaryScreenID => $primaryId');

    sseClient.onMessageReceived = (SseMessage message) async {
      print(
        '📨 RAW SSE MESSAGE => ${jsonEncode({"ScreenId": message.screenId, "CommandType": message.commandType.name, "TemplateName": message.templateName})}',
      );

      AppToast.show(
        'Command received: ${message.commandType.name}',
        gravity: ToastGravity.TOP,
      );

      // 🔥 EXACT C# CONDITION
      if (message.screenId == primaryId) {
        print('✅ ScreenId matched → CommandParsing');
        _commandParsing(message);
      } else {
        print('⛔ Ignored SSE for ScreenId ${message.screenId}');
      }
    };

    sseClient.start();
    print('📡 SSE listener started');
  }

  Future<void> _commandParsing(SseMessage msg) async {
    try {
      print('⚙️ Command received => ${msg.commandType}');

      switch (msg.commandType) {
        case SseCommandType.templateUpdate:
        case SseCommandType.scheduledUpdate:
          await dispatcher.handle(msg);

          break;

        default:
          print('⚠️ Unsupported command');
          break;
      }
    } catch (e) {
      print('❌ CommandParsing exception: $e');
    }
  }

  void _handleSseMessage(SseMessage message) {
    dispatcher.handle(message);
  }

  // --------------------------------------------------------------------------
  // 🔐 CRC32 (EXACT C# MATCH)
  // --------------------------------------------------------------------------

  String _generateConnectionCode({
    required String playerType,
    required String macAddress,
  }) {
    final now = DateTime.now();

    final timestamp =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final buffer = '$playerType#$macAddress#$timestamp';
    final bytes = Uint8List.fromList(utf8.encode(buffer));
    final crc = Crc32.compute(bytes);

    return crc.toRadixString(16).toUpperCase().padLeft(8, '0');
  }

  // --------------------------------------------------------------------------

  bool shouldShowTemplate() {
    return TemplateScheduleEvaluator.shouldShowScheduledTemplate(
      appState.activeSchedule,
    );
  }
}
