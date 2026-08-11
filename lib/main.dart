import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'splash_screen.dart';
import 'portal_page.dart';
import 'factory_login_page.dart';
import 'factory_home_page.dart';
import 'order/order_login_page.dart';
import 'order/order_home_page.dart';
import 'order/api.dart';
import 'store_login_page.dart';
import 'store_management_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final String? token = prefs.getString('token');
  final String? appMode = prefs.getString('app_mode');
  
  if (token != null && appMode == 'order') {
    // Fetch order stock in the background so startup remains instant
    fetchAndCacheStock();
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'House of Onzone',
      theme: AppTheme.themeData,
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const PortalPage(),
        '/factory_login': (context) => const FactoryLoginPage(),
        '/factory_home': (context) => const FactoryHomePage(),
        '/order_login': (context) => const OrderLoginPage(),
        '/order_home': (context) => const OrderHomePage(),
        '/store_login': (context) => const StoreLoginPage(),
        '/store_management': (context) => const StoreManagementPage(),
      },
    );
  }
}