import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'qr_cache_manager.dart';

enum QrDataType { imageUrl, base64Image, webUrl, text }

class QrParsedData {
  final QrDataType type;
  final String content;
  final String? extension;

  QrParsedData({required this.type, required this.content, this.extension});
}

class QrDashboardScreen extends StatefulWidget {
  const QrDashboardScreen({super.key});

  @override
  State<QrDashboardScreen> createState() => _QrDashboardScreenState();
}

class _QrDashboardScreenState extends State<QrDashboardScreen> {
  QrParsedData? _scannedData;
  bool _isClearing = false;
  WebViewController? _webViewController;

  // Local caching state
  File? _localImageFile;
  bool _isDownloadingImage = false;
  String? _downloadError;

  // Embedded camera scanning state
  final MobileScannerController _cameraController = MobileScannerController();
  bool _isScanning = false;
  String? _lastScannedValue;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  bool _isDirectImageUrl(String url) {
    final cleanUrl = url.toLowerCase().split('?').first;
    return cleanUrl.endsWith('.png') ||
        cleanUrl.endsWith('.jpg') ||
        cleanUrl.endsWith('.jpeg') ||
        cleanUrl.endsWith('.gif') ||
        cleanUrl.endsWith('.webp') ||
        cleanUrl.endsWith('.bmp') ||
        cleanUrl.endsWith('.svg');
  }

  bool _isMeQrUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.contains('me-qr.com');
  }

  QrParsedData _parseQrContent(String value) {
    final trimmed = value.trim();

    // 1. Check if it's a URL
    if (trimmed.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      if (_isDirectImageUrl(trimmed) || _isMeQrUrl(trimmed)) {
        return QrParsedData(type: QrDataType.imageUrl, content: trimmed);
      } else {
        return QrParsedData(type: QrDataType.webUrl, content: trimmed);
      }
    }

    // 2. Check if it's base64 image (Data URL format)
    final base64Pattern = RegExp(
      r'^data:image/(jpeg|png|gif|webp|bmp|jpg);base64,',
      caseSensitive: false,
    );
    final match = base64Pattern.firstMatch(trimmed);
    if (match != null) {
      final mimeType = match.group(1);
      final base64Content = trimmed.substring(match.group(0)!.length);
      return QrParsedData(
        type: QrDataType.base64Image,
        content: base64Content,
        extension: mimeType,
      );
    }

    // 3. Check if it's a raw base64 string
    try {
      if (trimmed.length > 30 && !trimmed.contains(' ') && !trimmed.contains('\n')) {
        final decoded = base64Decode(trimmed);
        if (decoded.isNotEmpty) {
          return QrParsedData(type: QrDataType.base64Image, content: trimmed);
        }
      }
    } catch (_) {}

    return QrParsedData(type: QrDataType.text, content: trimmed);
  }

  void _initializeWebViewController(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(url));
  }

  void _toggleScanning() {
    setState(() {
      _isScanning = !_isScanning;
      if (!_isScanning) {
        _lastScannedValue = null;
        _lastScanTime = null;
      }
    });
  }

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? rawValue = barcodes.first.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        final now = DateTime.now();
        if (rawValue == _lastScannedValue && 
            _lastScanTime != null && 
            now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
          return;
        }

        _lastScannedValue = rawValue;
        _lastScanTime = now;

        HapticFeedback.lightImpact();
        _processScannedValue(rawValue);
      }
    }
  }

  void _processScannedValue(String value) {
    final parsed = _parseQrContent(value);
    setState(() {
      _scannedData = parsed;
      _localImageFile = null;
      _isDownloadingImage = false;
      _downloadError = null;
      if (parsed.type == QrDataType.webUrl) {
        _initializeWebViewController(parsed.content);
      } else {
        _webViewController = null;
      }
    });

    if (parsed.type == QrDataType.imageUrl) {
      _handleImageCaching(parsed.content);
    }
  }

  Future<void> _handleImageCaching(String url) async {
    try {
      final cachedFile = await QrCacheManager.instance.getCachedImage(url);
      if (cachedFile != null) {
        if (mounted) {
          setState(() {
            _localImageFile = cachedFile;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isDownloadingImage = true;
          _downloadError = null;
        });
      }

      final downloadedFile = await QrCacheManager.instance.downloadAndCacheImage(url);

      if (mounted) {
        setState(() {
          _localImageFile = downloadedFile;
          _isDownloadingImage = false;
        });
      }
    } catch (e) {
      if (_isMeQrUrl(url)) {
        if (mounted) {
          setState(() {
            _isDownloadingImage = false;
            _downloadError = null;
            _scannedData = QrParsedData(type: QrDataType.webUrl, content: url);
            _initializeWebViewController(url);
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isDownloadingImage = false;
            _downloadError = e.toString();
          });
        }
      }
    }
  }

  void _clearResult() {
    setState(() {
      _isClearing = true;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _scannedData = null;
          _webViewController = null;
          _localImageFile = null;
          _isDownloadingImage = false;
          _downloadError = null;
          _isClearing = false;
        });
      }
    });
  }

  Future<void> _clearCacheAction() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Clear Image Cache?', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        content: const Text('This will delete all locally cached images.', style: TextStyle(color: Color(0xFF334155))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await QrCacheManager.instance.clearCache();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Local image cache cleared'),
            backgroundColor: Color(0xFF0F172A),
          ),
        );
        if (_scannedData?.type == QrDataType.imageUrl) {
          _clearResult();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 12),
              Expanded(
                child: AnimatedOpacity(
                  opacity: _isClearing ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 250),
                  child: _scannedData == null
                      ? _buildPlaceholder()
                      : _buildResultPreview(),
                ),
              ),
              const SizedBox(height: 12),
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A)),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back to Dashboard',
          ),
          const SizedBox(width: 6),
          // Small Square Camera Preview (top-left)
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isScanning ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _isScanning
                ? MobileScanner(
                    controller: _cameraController,
                    onDetect: _onDetect,
                  )
                : const Center(
                    child: Icon(
                      Icons.camera_alt_outlined,
                      color: Color(0xFF94A3B8),
                      size: 26,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          // App Title Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MODEL SCANNER',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isScanning ? 'Camera active. Point at QR code.' : 'Camera stopped.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isScanning) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMiniRoundButton(
                  icon: Icons.flip_camera_ios_rounded,
                  onPressed: () => _cameraController.switchCamera(),
                  tooltip: 'Flip Camera',
                ),
                const SizedBox(width: 16),
                Expanded(child: _buildScanningToggleButton()),
                const SizedBox(width: 16),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _cameraController,
                  builder: (context, state, child) {
                    final isTorchOn = state.torchState == TorchState.on;
                    return _buildMiniRoundButton(
                      icon: isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      iconColor: isTorchOn ? const Color(0xFFF59E0B) : const Color(0xFF64748B),
                      onPressed: () => _cameraController.toggleTorch(),
                      tooltip: 'Toggle Flash',
                    );
                  },
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                _buildMiniRoundButton(
                  icon: Icons.cleaning_services_rounded,
                  onPressed: _clearCacheAction,
                  tooltip: 'Clear Cache',
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildScanningToggleButton()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanningToggleButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: _isScanning
              ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
              : [const Color(0xFF4F46E5), const Color(0xFF3730A3)],
        ),
        boxShadow: [
          BoxShadow(
            color: (_isScanning ? const Color(0xFFEF4444) : const Color(0xFF4F46E5)).withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _toggleScanning,
        icon: Icon(
          _isScanning ? Icons.stop_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 18,
        ),
        label: Text(
          _isScanning ? 'STOP CAMERA' : 'START CAMERA',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniRoundButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color iconColor = const Color(0xFF64748B),
    String? tooltip,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor, size: 20),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 16,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2F6),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
              ),
              child: const Center(
                child: Icon(
                  Icons.checkroom_rounded,
                  size: 60,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Model Preview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                'Point the scanner at a box QR code to preview the dress model image.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultPreview() {
    final data = _scannedData!;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Icon(
                  data.type == QrDataType.text ? Icons.text_snippet_outlined : Icons.image_outlined,
                  color: const Color(0xFF4F46E5),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  data.type == QrDataType.imageUrl 
                      ? 'Image Preview' 
                      : data.type == QrDataType.webUrl
                          ? 'Web Landing Page'
                          : data.type == QrDataType.base64Image 
                              ? 'Base64 Image' 
                              : 'Scanned Text',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                if (data.type == QrDataType.imageUrl) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _localImageFile != null
                          ? const Color(0xFFD1FAE5)
                          : const Color(0xFFFFEDD5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _localImageFile != null ? 'CACHED' : 'ONLINE',
                      style: TextStyle(
                        color: _localImageFile != null ? const Color(0xFF065F46) : const Color(0xFF9A3412),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    data.type.name.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF4F46E5),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFFF8FAFC),
              padding: EdgeInsets.zero,
              alignment: Alignment.center,
              child: _buildPreviewBody(data),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _getShortenedContent(data.content),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _clearResult,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                  label: const Text('Clear', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: const Color(0xFFFEE2E2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBody(QrParsedData data) {
    if (data.type == QrDataType.imageUrl) {
      if (_isDownloadingImage) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF4F46E5),
            ),
            const SizedBox(height: 12),
            const Text(
              'Resolving and caching image...',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
          ],
        );
      }

      if (_downloadError != null) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildErrorWidget('Failed to download image.\n$_downloadError'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _handleImageCaching(data.content),
              icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
              label: const Text('Retry Download', style: TextStyle(color: Colors.white, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        );
      }

      if (_localImageFile != null) {
        return ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Image.file(
            _localImageFile!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return _buildErrorWidget('Failed to load locally cached image.');
            },
          ),
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Image.network(
          data.content,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
                color: const Color(0xFF4F46E5),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget('Failed to load image from URL.\nMake sure the link is correct and you have internet access.');
          },
        ),
      );
    } else if (data.type == QrDataType.webUrl) {
      if (_webViewController != null) {
        return ClipRRect(
          borderRadius: BorderRadius.zero,
          child: WebViewWidget(controller: _webViewController!),
        );
      } else {
        return const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF4F46E5),
          ),
        );
      }
    } else if (data.type == QrDataType.base64Image) {
      try {
        final decodedBytes = base64Decode(data.content);
        return ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Image.memory(
            decodedBytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return _buildErrorWidget('Failed to decode Base64 data into an image.');
            },
          ),
        );
      } catch (e) {
        return _buildErrorWidget('Invalid base64 image data.');
      }
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber.shade600,
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'No Image Found',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'The scanned QR code contains text rather than an image.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 120),
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SingleChildScrollView(
              child: Text(
                data.content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Color(0xFF4F46E5)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: data.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied content to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEEF2F6),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildErrorWidget(String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
        const SizedBox(height: 12),
        const Text(
          'Preview Error',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }

  String _getShortenedContent(String value) {
    if (value.length > 100) {
      return '${value.substring(0, 50)}...${value.substring(value.length - 50)}';
    }
    return value;
  }
}
