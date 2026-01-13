import 'package:shared_preferences/shared_preferences.dart';
import 'package:restart_app/restart_app.dart';

class TemplateManager {
  static const String _templateKey = 'selected_template';
  static const String _pendingTemplateKey = 'pending_template';

  // Save the template name to use on next restart
  static Future<void> saveTemplateForRestart(String templateName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingTemplateKey, templateName);
  }

  // Check if there's a pending template to load after restart
  static Future<String?> getPendingTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final template = prefs.getString(_pendingTemplateKey);

    // Clear it after reading
    if (template != null) {
      await prefs.remove(_pendingTemplateKey);
    }

    return template;
  }

  // Save the currently active template
  static Future<void> setActiveTemplate(String templateName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_templateKey, templateName);
  }

  // Get the currently active template
  static Future<String?> getActiveTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_templateKey);
  }

  // Restart the app with the new template
  static Future<void> restartWithTemplate(String templateName) async {
    await saveTemplateForRestart(templateName);
    await setActiveTemplate(templateName);

    // Restart the app
    Restart.restartApp();
  }
}
