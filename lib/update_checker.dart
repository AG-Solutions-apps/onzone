import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpgradeCheckOverlay extends StatefulWidget {
  final Widget child;
  const UpgradeCheckOverlay({super.key, required this.child});

  @override
  State<UpgradeCheckOverlay> createState() => _UpgradeCheckOverlayState();
}

class _UpgradeCheckOverlayState extends State<UpgradeCheckOverlay> {
  Timer? _timer;
  bool _showUpdateOverlay = false;
  String _latestVersion = '';
  String _currentVersion = '';
  bool _checking = false;
  DateTime? _lastCheckedTime;

  @override
  void initState() {
    super.initState();
    _startUpdateCheckTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startUpdateCheckTimer() {
    // Check once immediately on load
    _checkUpdate();
    // Run timer check every 1 second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkUpdate();
    });
  }

  Future<void> _checkUpdate() async {
    if (_checking || _showUpdateOverlay) return;

    final now = DateTime.now();
    // Throttle HTTP request to Play Store to every 30 seconds to avoid cellular data waste & rate-limiting
    if (_lastCheckedTime != null && now.difference(_lastCheckedTime!) < const Duration(seconds: 30)) {
      return;
    }

    _checking = true;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      if (mounted) {
        setState(() {
          _currentVersion = currentVersion;
        });
      }

      final playStoreUrl = 'https://play.google.com/store/apps/details?id=com.onzone.agsolutions&hl=en';
      final response = await http.get(Uri.parse(playStoreUrl));
      
      _lastCheckedTime = DateTime.now();

      if (response.statusCode == 200) {
        final html = response.body;
        
        // Scraping regex for Google Play Store HTML details page
        // Pattern 1: Matches the standard Google JSON metadata block nested version string
        final regExp = RegExp(r'\[\[\["([0-9]+\.[0-9]+\.[0-9]+)"\]\]\]');
        final match = regExp.firstMatch(html);
        String? latestVersion;
        
        if (match != null) {
          latestVersion = match.group(1);
        } else {
          // Pattern 2: Fallback selector that matches strings of semver formatting starting with 2.
          final fallbackRegExp = RegExp(r'"([0-9]+\.[0-9]+\.[0-9]+)"');
          final matches = fallbackRegExp.allMatches(html);
          for (var m in matches) {
            final ver = m.group(1);
            if (ver != null && ver != currentVersion && ver.startsWith('2.')) {
              latestVersion = ver;
              break;
            }
          }
        }

        if (latestVersion != null && latestVersion != currentVersion) {
          if (_isVersionNewer(currentVersion, latestVersion)) {
            if (mounted) {
              setState(() {
                _latestVersion = latestVersion!;
                _showUpdateOverlay = true;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking app update: $e');
    } finally {
      _checking = false;
    }
  }

  bool _isVersionNewer(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final cVal = i < currentParts.length ? currentParts[i] : 0;
        final lVal = i < latestParts.length ? latestParts[i] : 0;
        if (lVal > cVal) return true;
        if (cVal > lVal) return false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _launchPlayStore() async {
    final playStoreUri = Uri.parse('https://play.google.com/store/apps/details?id=com.onzone.agsolutions');
    try {
      if (await canLaunchUrl(playStoreUri)) {
        await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch Play Store URI';
      }
    } catch (e) {
      debugPrint('Error launching Play Store: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showUpdateOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: PopScope(
                canPop: false, // Prevent dismissing by back button
                child: Card(
                  elevation: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 32.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.system_update_rounded,
                            size: 36,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Update Available',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'A new version ($_latestVersion) of Onzone is available on the Play Store. Your current version is $_currentVersion. Please update the app to continue.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _showUpdateOverlay = false;
                                  // Snooze network request checking for 15 minutes
                                  _lastCheckedTime = DateTime.now().add(const Duration(minutes: 15));
                                });
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF64748B),
                              ),
                              child: const Text('LATER'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _launchPlayStore,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF202C4D),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              child: const Text('UPDATE'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
