import 'package:flutter/material.dart';
import 'package:signage/ui/template_webview.dart';
import '../app/app_controller.dart';
import '../app/app_state.dart';

class HomeScreen extends StatelessWidget {
  final AppController controller;
  const HomeScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: controller.appState,
        builder: (_, __) {
          final state = controller.appState;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ✅ Always present base layer
              const ColoredBox(color: Colors.black),

              // ✅ WEBVIEW
              if (state.showTemplate && state.currentTemplate != null)
                TemplateWebView(state: state),

              // ✅ IDLE
              if (!state.showTemplate && !state.isTemplateLoading)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'WAITING FOR CONTENT',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 18,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (state.connectionCode != null) ...[
                        const Text(
                          'UNIQUE CODE',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.connectionCode!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            letterSpacing: 4,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // ✅ LOADING
              if (state.isTemplateLoading) _loadingOverlay(state),
            ],
          );
        },
      ),
    );
  }

  Widget _loadingOverlay(AppState state) {
    return Container(
      color: const Color(0xFF0B0B0B),
      alignment: Alignment.center,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.loadingMessage,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: state.loadingProgress,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF3D7EFF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
