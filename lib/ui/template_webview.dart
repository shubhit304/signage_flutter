import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../app/app_state.dart';

class TemplateWebView extends StatefulWidget {
  final AppState state;
  final String? initialTemplate;

  const TemplateWebView({super.key, required this.state, this.initialTemplate});

  @override
  State<TemplateWebView> createState() => _TemplateWebViewState();
}

class _TemplateWebViewState extends State<TemplateWebView> {
  WebViewController? _controller;
  String? _currentTemplate;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView(widget.initialTemplate);

    // Listen for template changes
    widget.state.addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() {
    final newTemplate = widget.state.currentTemplate;

    // Check if template has actually changed
    if (newTemplate != null && newTemplate != _currentTemplate) {
      _reloadWithNewTemplate(newTemplate);
    }
  }

  Future<void> _initializeWebView(String? template) async {
    if (template == null) return;

    _currentTemplate = template;
    await _createWebViewController();
    await _loadTemplate();
  }

  Future<void> _createWebViewController() async {
    // Clean up existing controller if any
    await _cleanupWebView();

    final params = const PlatformWebViewControllerCreationParams();

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel(
        'Flutter',
        onMessageReceived: (message) {
          debugPrint("JS says: ${message.message}");
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            widget.state.updateLoading("Loading template…", p / 100);
          },
          onPageStarted: (_) {
            widget.state.startTemplateLoading("Preparing content…");
          },
          onPageFinished: (_) {
            // ✅ SAFE STATE UPDATE
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.state.stopTemplateLoading();
              widget.state.showTemplateView();
            });
          },
          onWebResourceError: (error) {
            debugPrint(
              "WebView Error: ${error.errorCode} - ${error.description}",
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.state.stopTemplateLoading();
            });
          },
        ),
      );

    // 🔥 ANDROID TV AUTOPLAY FIX (CORRECT)
    if (_controller!.platform is AndroidWebViewController) {
      final androidController =
          _controller!.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    _isInitialized = true;
  }

  Future<void> _cleanupWebView() async {
    if (_controller != null) {
      try {
        // Clear any loaded content
        await _controller!.clearCache();
        await _controller!.loadHtmlString('');

        // For Android, we can dispose the platform controller
        if (_controller!.platform is AndroidWebViewController) {
          // AndroidWebViewController doesn't have a dispose method in current API
          // So we'll just nullify and let garbage collection handle it
        }
      } catch (e) {
        debugPrint("Error cleaning up WebView: $e");
      }

      _controller = null;
    }
    _isInitialized = false;
  }

  Future<void> _loadTemplate() async {
    if (_controller == null || _currentTemplate == null) return;

    debugPrint("📄 Loading template in WebView: $_currentTemplate");

    try {
      if (_currentTemplate!.startsWith('http://') ||
          _currentTemplate!.startsWith('https://')) {
        // 🌐 Local server / URL
        await _controller!.loadRequest(Uri.parse(_currentTemplate!));
      } else {
        // 📁 Local file
        await _controller!.loadFile(_currentTemplate!);
      }
    } catch (e) {
      debugPrint("Error loading template: $e");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.state.stopTemplateLoading();
      });
    }
  }

  Future<void> _reloadWithNewTemplate(String newTemplate) async {
    debugPrint("🔄 Reloading WebView with new template: $newTemplate");

    setState(() {
      _currentTemplate = newTemplate;
    });

    // Option 1: Reload with existing controller (faster, keeps state)
    if (_controller != null && _isInitialized) {
      try {
        await _loadTemplate();
        return;
      } catch (e) {
        debugPrint("Failed to reload, reinitializing: $e");
      }
    }

    // Option 2: Full reinitialization (cleanest)
    await _initializeWebView(newTemplate);

    // Force rebuild
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onAppStateChanged);
    _cleanupWebView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Positioned.fill(child: WebViewWidget(controller: _controller!));
  }
}
