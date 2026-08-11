import 'package:flutter/material.dart';
import 'factory_login_page.dart';
import 'order/order_login_page.dart';
import 'store_management_page.dart';
import 'store_login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PortalPage extends StatefulWidget {
  const PortalPage({super.key});

  @override
  State<PortalPage> createState() => _PortalPageState();
}

class _PortalPageState extends State<PortalPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Modern off-white background
      body: Stack(
        children: [
          // Premium subtle background gradient
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
                color: const Color(0xFF0D9488).withOpacity(0.06), // Very soft teal glow
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0D9488).withOpacity(0.12),
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
                color: const Color(0xFF2563EB).withOpacity(0.06), // Very soft blue glow
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.12),
                    blurRadius: 80,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(),
                      
                      // Brand Logo & Title (Light Theme Styled)
                      Hero(
  tag: 'app_logo',
  child: Container(
    padding: const EdgeInsets.all(18),
    child: Image.asset(
      'assets/onzone-logo.png',
      height: 180,
      width: 180,
      fit: BoxFit.contain,
    ),
  ),
),
                      const SizedBox(height: 10),
                      const Text(
                        'Select your portal to continue',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A), // Deep Slate/Black
                          letterSpacing: 2.0,
                        ),
                      ),
                   
                     
                      const SizedBox(height: 40),

                      // Portal Choice 1: Factory (White Theme Card)
                      _buildPortalCard(
                        context: context,
                        title: 'Factory Login ',
                        description: 'Pending Work Orders ,Create and edit Packaging Slips',
                        icon: Icons.precision_manufacturing,
                        iconColor: const Color(0xFF0F766E), // Teal Accent
                        bgColor: const Color(0xFFF0FDF4),   // Soft greenish-teal background for icon container
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const FactoryLoginPage()),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // Portal Choice 2: Orders (White Theme Card)
                      _buildPortalCard(
                        context: context,
                        title: 'Order Form login',
                        description: 'Create and download order forms',
                        icon: Icons.shopping_bag,
                        iconColor: const Color(0xFF1D4ED8), // Blue Accent
                        bgColor: const Color(0xFFEFF6FF),   // Soft blue background for icon container
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const OrderLoginPage()),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // Portal Choice 3: Store Management (White Theme Card)
                      _buildPortalCard(
                        context: context,
                        title: 'Store Management Login',
                        description: 'Scan box barcodes to manage and verify received box items.',
                        icon: Icons.store,
                        iconColor: const Color(0xFFEA580C), // Orange Accent
                        bgColor: const Color(0xFFFFF7ED),   // Soft orange background for icon container
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final token = prefs.getString('token') ?? '';

                          if (mounted) {
                            if (token.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const StoreManagementPage()),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const StoreLoginPage()),
                              );
                            }
                          }
                        },
                      ),
                      
                      const Spacer(flex: 2),

                      // Footer Credits
                      // const Text(
                      //   'Powered by AG Solutions',
                      //   style: TextStyle(
                      //     fontSize: 12,
                      //     color: Color(0xFF94A3B8), // Muted text color
                      //     letterSpacing: 1.0,
                      //     fontWeight: FontWeight.w500,
                      //   ),
                      // ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortalCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: iconColor.withOpacity(0.15),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                size: 30,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A), // Slate Black
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569), // Slate Gray
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}
