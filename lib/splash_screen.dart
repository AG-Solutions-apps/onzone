import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'factory_login_page.dart';
import 'factory_home_page.dart';
import 'portal_page.dart';
import 'order/order_home_page.dart';
import 'app_theme.dart';
import 'store_management_page.dart';

// ── Brand palette ────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // ── Individual animation handles ─────────────────────────────────────────
  late Animation<double>  _logoFade;
  late Animation<double>  _logoScale;
  late Animation<double>  _badgeFade;
  late Animation<double>  _badgeScale;
  late Animation<double>  _loaderFade;
  late Animation<double>  _agFade;
  late Animation<Offset>  _agSlide;
  late Animation<double>  _chipsFade;
  late Animation<Offset>  _chipsSlide;
  late Animation<double>  _loveFade;
  late Animation<Offset>  _loveSlide;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    );

    // BBC logo – drops in first
    _logoFade = _curve(0.00, 0.45, Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.00, 0.55, curve: Curves.easeOutBack)));

    // Trust badge
    _badgeFade  = _curve(0.45, 0.75, Curves.easeIn);
    _badgeScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.45, 0.75, curve: Curves.easeOutBack)));

    // Loading spinner
    _loaderFade = _curve(0.60, 0.85, Curves.easeIn);

    // AG Solutions logo
    _agFade  = _curve(0.65, 0.90, Curves.easeIn);
    _agSlide = _slide(0.65, 0.90, dy: 0.3);

    // Service chips
    _chipsFade  = _curve(0.75, 1.00, Curves.easeIn);
    _chipsSlide = _slide(0.75, 1.00, dy: 0.5);
    
    // Love text
    _loveFade = _curve(0.85, 1.00, Curves.easeIn);
    _loveSlide = _slide(0.85, 1.00, dy: 0.3);

    _ctrl.forward();

    // Check login status after animations
    _checkLoginStatus();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Animation<double> _curve(double from, double to, Curve curve) =>
      Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _ctrl, curve: Interval(from, to, curve: curve)));

  Animation<Offset> _slide(double from, double to,
          {double dx = 0, double dy = 0}) =>
      Tween<Offset>(begin: Offset(dx, dy), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _ctrl,
              curve: Interval(from, to, curve: Curves.easeOutCubic)));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('token');
    final String? appMode = prefs.getString('app_mode');

    // Wait for animations to complete
    await Future.delayed(const Duration(seconds: 4));

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      if (appMode == 'factory') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const FactoryHomePage()),
        );
      } else if (appMode == 'store') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const StoreManagementPage()),
        );
      } else if (appMode == 'order') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OrderHomePage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PortalPage()),
        );
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PortalPage()),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 120),

                  // ──  LOGO ───────────────────────────────────────────
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                       
                        child: Image.asset(
                          "assets/onzone-logo.png",
                          height: 250,
                          width: 250,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Company Name
                  

                  const SizedBox(height: 30),

                  // ── TRUST BADGE ──────────────────────────────────────────
                  

                  const SizedBox(height: 40),

                  // ── LOADING INDICATOR ──────────────────────────────────
                  FadeTransition(
                    opacity: _loaderFade,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 50,
                          width: 50,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                            backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          "Loading Amazing Experience...",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.primaryColor.withOpacity(0.55),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 150),

                  // ── DIVIDER ─────────────────────────────────────────────
                 Container(
                    margin: const EdgeInsets.symmetric(horizontal: 30),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1,
                            color: const Color.fromARGB(
                              255,
                              33,
                              150,
                              243,
                            ).withOpacity(0.2),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.kBlue.withOpacity(0.4),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: AppTheme.kBlue.withOpacity(0.2),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Crafted with Love Text + AG Solutions SVG Image
                  SlideTransition(
                    position: _loveSlide,
                    child: FadeTransition(
                      opacity: _loveFade,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                " Crafted with",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black.withOpacity(0.5),
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.favorite,
                                size: 17,
                                color: const Color.fromARGB(255, 255, 0, 0),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "by",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black.withOpacity(0.5),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // AG Solutions SVG Image
                          Image.asset(
                            "assets/ag1.png",
                            height: 70,
                            width: 200,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── SERVICE CHIPS ──────────────────────────────────────
                  
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── BLUE CHIP WIDGET ─────────────────────────────────────────────────────
  
}