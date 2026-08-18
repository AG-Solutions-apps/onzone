import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QrCacheManager {
  QrCacheManager._internal();
  static final QrCacheManager instance = QrCacheManager._internal();

  SharedPreferences? _prefs;
  Directory? _cacheDir;
  bool _isInitialized = false;

  static const String _prefPrefix = 'qr_cache_';

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    final docDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${docDir.path}/qr_image_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    _isInitialized = true;
  }

  String _getPrefKey(String url) {
    final bytes = utf8.encode(url);
    return '$_prefPrefix${sha256.convert(bytes)}';
  }

  String _generateFileName(String url) {
    final bytes = utf8.encode(url);
    final hash = sha256.convert(bytes).toString();
    String extension = '.bin';
    final cleanUrl = url.toLowerCase().split('?').first;
    if (cleanUrl.endsWith('.png')) {
      extension = '.png';
    } else if (cleanUrl.endsWith('.jpg') || cleanUrl.endsWith('.jpeg')) {
      extension = '.jpg';
    } else if (cleanUrl.endsWith('.gif')) {
      extension = '.gif';
    } else if (cleanUrl.endsWith('.webp')) {
      extension = '.webp';
    } else if (cleanUrl.endsWith('.svg')) {
      extension = '.svg';
    }
    return '$hash$extension';
  }

  bool _isMeQrUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.contains('me-qr.com');
  }

  String? _getMeQrId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (pathSegments.isEmpty) return null;
    return pathSegments.last;
  }

  Future<String?> _resolveMeQrImageUrl(String url) async {
    final id = _getMeQrId(url);
    if (id == null) return null;

    // 1. Try to fetch the data image-pack page directly
    final dataPageUrl = 'https://qr1.me-qr.com/data/image-pack/$id';
    try {
      final response = await http.get(Uri.parse(dataPageUrl));
      if (response.statusCode == 200) {
        final html = response.body;
        final regExp = RegExp(r'''https://storage\d*\.me-qr\.com/image/[^\s"']+\.(?:jpg|jpeg|png|gif|webp)''', caseSensitive: false);
        final match = regExp.firstMatch(html);
        if (match != null) {
          return match.group(0);
        }
      }
    } catch (_) {}

    // 2. Fallback: Fetch original landing page to get redirects or directly search
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final html = response.body;

        // Look for window.location redirects
        final redirectRegExp = RegExp(r'''(?:window\.location|location\.href|location\.replace)\s*=\s*["']([^"']+)["']''', caseSensitive: false);
        final redirectMatch = redirectRegExp.firstMatch(html);
        if (redirectMatch != null) {
          final redirectUrl = redirectMatch.group(1)!;
          final subResponse = await http.get(Uri.parse(redirectUrl));
          if (subResponse.statusCode == 200) {
            final subHtml = subResponse.body;
            final storageRegExp = RegExp(r'''https://storage\d*\.me-qr\.com/image/[^\s"']+\.(?:jpg|jpeg|png|gif|webp)''', caseSensitive: false);
            final storageMatch = storageRegExp.firstMatch(subHtml);
            if (storageMatch != null) {
              return storageMatch.group(0);
            }
          }
        }

        // Direct check on original html
        final regExp = RegExp(r'''https://storage\d*\.me-qr\.com/image/[^\s"']+\.(?:jpg|jpeg|png|gif|webp)''', caseSensitive: false);
        final match = regExp.firstMatch(html);
        if (match != null) {
          return match.group(0);
        }
      }
    } catch (_) {}

    return null;
  }

  /// Returns the cached image [File] if it exists, otherwise null.
  Future<File?> getCachedImage(String url) async {
    await init();
    final key = _getPrefKey(url);
    final filePath = _prefs!.getString(key);
    if (filePath != null) {
      final file = File(filePath);
      if (await file.exists()) {
        return file;
      } else {
        // Clean up stale reference if file was deleted
        await _prefs!.remove(key);
      }
    }
    return null;
  }

  /// Downloads the image from the given [url], caches it locally, and returns the [File].
  Future<File> downloadAndCacheImage(String url) async {
    await init();
    
    // Check if it's already cached first
    final existingFile = await getCachedImage(url);
    if (existingFile != null) {
      return existingFile;
    }

    String downloadUrl = url;
    if (_isMeQrUrl(url)) {
      final resolvedUrl = await _resolveMeQrImageUrl(url);
      if (resolvedUrl == null) {
        throw Exception('Not a valid me-qr image or failed to resolve image page.');
      }
      downloadUrl = resolvedUrl;
    }

    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download image: Status ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    final fileName = _generateFileName(url);
    final filePath = '${_cacheDir!.path}/$fileName';
    final file = File(filePath);

    await file.writeAsBytes(bytes);

    final key = _getPrefKey(url);
    await _prefs!.setString(key, filePath);

    return file;
  }

  /// Clears all files in the cache directory and preference entries.
  Future<void> clearCache() async {
    await init();
    if (await _cacheDir!.exists()) {
      try {
        await _cacheDir!.delete(recursive: true);
      } catch (_) {}
      await _cacheDir!.create(recursive: true);
    }
    
    // Remove all keys with the prefix
    final keys = _prefs!.getKeys();
    for (final key in keys) {
      if (key.startsWith(_prefPrefix)) {
        await _prefs!.remove(key);
      }
    }
  }
}
