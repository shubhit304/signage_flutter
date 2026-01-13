import 'package:flutter/material.dart';
import '../services/signage_config_service.dart';
import 'app_loader.dart';

class ApiSetupScreen extends StatefulWidget {
  ApiSetupScreen({super.key});

  @override
  State<ApiSetupScreen> createState() => _ApiSetupScreenState();
}

class _ApiSetupScreenState extends State<ApiSetupScreen> {
  final String _hardcodedUrl =
      'https://117.219.19.154:8021/api/'; // ?? Your hardcoded URL

  @override
  void initState() {
    super.initState();
    _saveAndContinue(); // ?? Automatically trigger save
  }

  Future<void> _saveAndContinue() async {
    await SignageConfigService.saveBaseUrl(_hardcodedUrl);

    // Navigate directly to AppLoader
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AppLoader()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Optional: show a loading indicator while saving
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
