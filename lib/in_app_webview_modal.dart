import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:webview_flutter/webview_flutter.dart';

class InAppWebViewModal extends StatefulWidget {
  final String url;
  final String title;
  final Color primaryColor;

  const InAppWebViewModal({
    super.key,
    required this.url,
    required this.title,
    this.primaryColor = const Color(0xFF4F46E5), // Indigo default
  });

  @override
  State<InAppWebViewModal> createState() => _InAppWebViewModalState();

  static void show(BuildContext context, String url, String title, {Color? primaryColor}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => InAppWebViewModal(
          url: url,
          title: title,
          primaryColor: primaryColor ?? Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}

class _InAppWebViewModalState extends State<InAppWebViewModal> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100.0;
            });
          },
          onWebResourceError: (WebResourceError error) {
            // Only consider it an error if it's a connection / resolving issue, or host lookup failure.
            if (error.description.contains('net::ERR') || 
                error.description.contains('dns') ||
                error.errorCode < 0) {
              setState(() {
                _hasError = true;
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final headerColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final textThemeColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: headerColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: isDark ? Colors.grey[400] : Colors.grey[700]),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Close',
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textThemeColor,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: isDark ? Colors.grey[400] : Colors.grey[700]),
            onPressed: () {
              _controller.reload();
            },
            tooltip: 'Reload',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _isLoading
              ? LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: widget.primaryColor.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(widget.primaryColor),
                  minHeight: 3,
                )
              : const SizedBox(height: 3),
        ),
      ),
      body: SafeArea(
        child: _hasError
            ? _buildErrorWidget(isDark)
            : WebViewWidget(
                controller: _controller,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              ),
      ),
    );
  }

  Widget _buildErrorWidget(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              color: Colors.redAccent,
              size: 54,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Unable to load page',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Please check your internet connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _hasError = false;
                _isLoading = true;
              });
              _controller.reload();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.replay_rounded),
            label: const Text(
              'Try Again',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
