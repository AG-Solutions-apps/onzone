import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'factory_home_page.dart';
import 'api.dart';
import 'package:http/http.dart' as http;
import 'store_management_page.dart';

class FactoryLoginPage extends StatefulWidget {
  final String? redirectPath;
  const FactoryLoginPage({super.key, this.redirectPath});

  @override
  State<FactoryLoginPage> createState() => _FactoryLoginPageState();
}

class _FactoryLoginPageState extends State<FactoryLoginPage> with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  
  late AnimationController _animationController;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _attemptLogin();
  }

  Future<void> _attemptLogin() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': _usernameController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        await _handleSuccess(response.body);
      } else {
        await _tryAlternativeLogin();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error. Please check your connection.';
      });
    }
  }

  Future<void> _tryAlternativeLogin() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': _usernameController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        await _handleSuccess(response.body);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid credentials. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _handleSuccess(String responseBody) async {
    try {
      final data = jsonDecode(responseBody);
      
      if (data['UserInfo'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['UserInfo']['token']);
        await prefs.setString('app_mode', 'factory');
        await prefs.setString('user_data', jsonEncode(data['UserInfo']['user']));

        if (mounted) {
          if (widget.redirectPath == 'store_management') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const StoreManagementPage()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const FactoryHomePage()),
            );
          }
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid server response';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error processing login';
      });
    }
  }

  List<Widget> _buildFormChildren(BuildContext context, Color primaryColor, bool isDark, bool isDesktop) {
    return [
      if (!isDesktop) ...[
        // Logo Section
        FadeTransition(
          opacity: _logoFade,
          child: ScaleTransition(
            scale: _logoScale,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Image.asset(
                "assets/onzone-logo.png",
                height: 160,
                width: 160,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],

      // Welcome Text
      Text(
        'Welcome Back',
        style: TextStyle(
          fontSize: isDesktop ? 30 : 28,
          fontWeight: FontWeight.bold,
          color: primaryColor,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
      
      const SizedBox(height: 8),
      
      Text(
        'Sign in to continue to your account',
        style: TextStyle(
          fontSize: 15,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
      
      const SizedBox(height: 32),
      
      // Username/Email Field
      TextField(
        controller: _usernameController,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          labelText: 'Email or Username',
          labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700]),
          hintText: 'Enter your email or username',
          hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400]),
          prefixIcon: Icon(
            Icons.person_outline,
            color: primaryColor,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: primaryColor,
              width: 2,
            ),
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
      
      const SizedBox(height: 20),
      
      // Password Field
      TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          labelText: 'Password',
          labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700]),
          hintText: 'Enter your password',
          hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400]),
          prefixIcon: Icon(
            Icons.lock_outline,
            color: primaryColor,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: primaryColor,
              width: 2,
            ),
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
      
      const SizedBox(height: 24),
      
      // Error Message
      if (_errorMessage != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red.shade700,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
      
      // Login Button
      ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          minimumSize: const Size(double.infinity, 50),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = AppTheme.primaryColor;
    const isDark = false;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            // Desktop Split Screen Layout
            return Row(
              children: [
                // Left Panel: Beautiful gradient side panel with branding
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.secondaryColor,
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Decorative abstract shapes
                        Positioned(
                          top: -120,
                          left: -120,
                          child: Container(
                            width: 320,
                            height: 320,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -160,
                          right: -80,
                          child: Container(
                            width: 440,
                            height: 440,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 200,
                          right: -50,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.03),
                            ),
                          ),
                        ),
                        // Content in the middle of left panel
                        Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(48.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // White card for logo
                                Container(
                                  padding: const EdgeInsets.all(28),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 24,
                                        offset: const Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    "assets/onzone-logo.png",
                                    height: 140,
                                    width: 140,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(height: 40),
                                const Text(
                                  'ONZONE',
                                  style: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'TIMELESS ALLIANCE',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 3.0,
                                  ),
                                ),
                                const SizedBox(height: 30),
                                Container(
                                  width: 60,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                                const SizedBox(height: 30),
                                Text(
                                  'Manage your work orders, packing slips, and receipts with our unified operations dashboard.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.8),
                                    fontWeight: FontWeight.w400,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right Panel: Clean form card with subtle ambient circles
                Expanded(
                  flex: 6,
                  child: Stack(
                    children: [
                      Container(
                        color: AppTheme.scaffoldBackgroundColor,
                      ),
                      Positioned(
                        top: -100,
                        right: -100,
                        child: Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0D9488).withValues(alpha: 0.06),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                blurRadius: 100,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -80,
                        left: -80,
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF2563EB).withValues(alpha: 0.06),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                                blurRadius: 80,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32.0),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Card(
                              elevation: 4,
                              shadowColor: Colors.black.withValues(alpha: 0.05),
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: BorderSide(
                                  color: Colors.grey.shade100,
                                  width: 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40.0,
                                  vertical: 48.0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: _buildFormChildren(context, primaryColor, isDark, true),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          } else {
            // Mobile & Tablet Layout
            return Stack(
              children: [
                // Background gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF1F5F9), // Light slate gray
                        Color(0xFFFFFFFF), // Pure white
                        Color(0xFFE2E8F0), // Soft gray
                      ],
                    ),
                  ),
                ),
                // Soft ambient glowing circles in the background for depth
                Positioned(
                  top: -100,
                  right: -100,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0D9488).withValues(alpha: 0.06), // Very soft teal glow
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                          blurRadius: 100,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80,
                  left: -80,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2563EB).withValues(alpha: 0.06), // Very soft blue glow
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                          blurRadius: 80,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Card(
                          elevation: 0,
                          color: Colors.transparent,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _buildFormChildren(context, primaryColor, isDark, false),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }
}