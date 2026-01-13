import 'package:flutter/foundation.dart';
import '../scheduling/template_schedule.dart';

import 'package:flutter/foundation.dart';
import '../scheduling/template_schedule.dart';
import '../services/local_storage_service.dart';

enum ClientStatus { disconnected, connected }

class AppState extends ChangeNotifier {
  String? activeTemplateFile;
  TemplateSchedule? activeSchedule;

  // 👇 ADD THIS
  String? scheduledTemplateFile;

  // ⭐ SCHEDULE STATE
  bool isShowingScheduledTemplate = false;
  String? lastInstantTemplate;

  ClientStatus clientStatus = ClientStatus.disconnected;
  bool isClientRegistered = false;
  int? screenId;

  bool isTemplateLoading = false;
  String loadingMessage = '';
  double loadingProgress = 0.0;

  bool showTemplate = false;

  String? connectionCode;

  // ---------------- TEMPLATE ----------------

  void startTemplateLoading(String message, {double progress = 0.0}) {
    isTemplateLoading = true;
    loadingMessage = message;
    loadingProgress = progress;
    notifyListeners();
  }

  void updateLoading(String message, double progress) {
    loadingMessage = message;
    loadingProgress = progress;
    notifyListeners();
  }

  void stopTemplateLoading() {
    isTemplateLoading = false;
    loadingMessage = '';
    loadingProgress = 0.0;
    notifyListeners();
  }

  void hideTemplate() {
    showTemplate = false;
    notifyListeners();
  }

  void showTemplateView() {
    showTemplate = true;
    notifyListeners();
  }

  void setTemplate(String filePath, {bool scheduled = false}) {
    if (scheduled) {
      scheduledTemplateFile = filePath;
    } else {
      activeTemplateFile = filePath;
      lastInstantTemplate = filePath;
      // ✅ Persist last running template (WinForms INI equivalent)
      LocalStorageService.saveLastRunningTemplate(filePath);
    }
    notifyListeners();
  }

  // ✅ ADD THIS GETTER HERE
  String? get currentTemplate {
    if (isShowingScheduledTemplate && scheduledTemplateFile != null) {
      return scheduledTemplateFile;
    }
    return activeTemplateFile;
  }

  void clearTemplate() {
    activeTemplateFile = null;
    showTemplate = false;
    notifyListeners();
  }

  void setConnectionCode(String code) {
    connectionCode = code;
    notifyListeners();
  }
  // ---------------- SCHEDULE ----------------

  void setSchedule(TemplateSchedule schedule) {
    activeSchedule = schedule;
    notifyListeners();
  }

  void clearSchedule() {
    activeSchedule = null;
    notifyListeners();
  }

  void markScheduledPlaying(bool value) {
    isShowingScheduledTemplate = value;
    notifyListeners();
  }

  // ---------------- REGISTRATION ----------------

  void setRegistered(int id) {
    isClientRegistered = true;
    screenId = id;
    notifyListeners();
  }
}
