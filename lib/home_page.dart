import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_theme.dart';
import 'work_order_detail_page.dart';
import 'add_packing_slip_page.dart';
import 'api.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String userName = 'User';
  String userEmail = '';
  String userMobile = '';
  List<dynamic> workOrders = [];
  List<dynamic> displayedOrders = [];
  bool isLoading = true;
  String errorMessage = '';
  String selectedTab = 'Pending';
  List<dynamic> receivedOrdersList = [];
  
  int totalPendingCount = 0;
  int totalClosedCount = 0;
  int currentPage = 1;
  int itemsPerPage = 1000;
  int totalPages = 1;



  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchWorkOrders();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString != null && userDataString.isNotEmpty) {
        final userData = jsonDecode(userDataString);
        setState(() {
          userName = userData['full_name'] ?? userData['name'] ?? 'User';
          userEmail = userData['email'] ?? '';
          userMobile = userData['mobile'] ?? '';
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _fetchWorkOrders() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // Fetch pending orders
      final pendingResponse = await http.get(
        Uri.parse('$baseUrl/fetch-work-order-app-list'),
        headers: headers,
      );

      // Fetch closed orders
      final closedResponse = await http.get(
        Uri.parse('$baseUrl/fetch-work-order-close-app-list'),
        headers: headers,
      );

      List<dynamic> rawReceivedList = [];
      try {
        final receivedResponse = await http.get(
          Uri.parse('$baseUrl/fetch-work-order-received-list'),
          headers: headers,
        );
        if (receivedResponse.statusCode == 200) {
          final receivedData = jsonDecode(receivedResponse.body);
          if (receivedData is List) {
            rawReceivedList = receivedData;
          } else if (receivedData is Map) {
            rawReceivedList = receivedData['workorderrc'] ?? 
                              receivedData['work_order_received'] ?? 
                              receivedData['received'] ?? 
                              receivedData['workorder'] ??
                              receivedData['data'] ?? 
                              receivedData['list'] ?? [];
          }
        }
      } catch (e) {
        print('Error fetching received list: $e');
      }

      if (pendingResponse.statusCode == 200 && closedResponse.statusCode == 200) {
        final pendingData = jsonDecode(pendingResponse.body);
        final closedData = jsonDecode(closedResponse.body);

        final List<dynamic> pendingList = pendingData['workorder'] is List ? pendingData['workorder'] : [];
        final List<dynamic> closedList = closedData['workorder'] is List ? closedData['workorder'] : [];

        setState(() {
          totalPendingCount = pendingList.length;
          totalClosedCount = closedList.length;
          workOrders = selectedTab == 'Closed' ? closedList : pendingList;
          receivedOrdersList = rawReceivedList;
          totalPages = 1;
          _updateDisplayedOrders();
          isLoading = false;
          errorMessage = '';
        });
        print('Loaded $totalPendingCount pending and $totalClosedCount closed orders');
      } else {
        await _fetchWorkOrdersWithoutToken();
      }
    } catch (e) {
      print('Error fetching work orders: $e');
      await _fetchWorkOrdersWithoutToken();
    }
  }

  Future<void> _fetchWorkOrdersWithoutToken() async {
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final pendingResponse = await http.get(
        Uri.parse('$baseUrl/fetch-work-order-app-list'),
        headers: headers,
      );

      final closedResponse = await http.get(
        Uri.parse('$baseUrl/fetch-work-order-close-app-list'),
        headers: headers,
      );

      List<dynamic> rawReceivedList = [];
      try {
        final receivedResponse = await http.get(
          Uri.parse('$baseUrl/fetch-work-order-received-list'),
          headers: headers,
        );
        if (receivedResponse.statusCode == 200) {
          final receivedData = jsonDecode(receivedResponse.body);
          if (receivedData is List) {
            rawReceivedList = receivedData;
          } else if (receivedData is Map) {
            rawReceivedList = receivedData['workorderrc'] ?? 
                              receivedData['work_order_received'] ?? 
                              receivedData['received'] ?? 
                              receivedData['workorder'] ??
                              receivedData['data'] ?? 
                              receivedData['list'] ?? [];
          }
        }
      } catch (e) {
        print('Error fetching received list: $e');
      }

      if (pendingResponse.statusCode == 200 && closedResponse.statusCode == 200) {
        final pendingData = jsonDecode(pendingResponse.body);
        final closedData = jsonDecode(closedResponse.body);

        final List<dynamic> pendingList = pendingData['workorder'] is List ? pendingData['workorder'] : [];
        final List<dynamic> closedList = closedData['workorder'] is List ? closedData['workorder'] : [];

        setState(() {
          totalPendingCount = pendingList.length;
          totalClosedCount = closedList.length;
          workOrders = selectedTab == 'Closed' ? closedList : pendingList;
          receivedOrdersList = rawReceivedList;
          totalPages = 1;
          _updateDisplayedOrders();
          isLoading = false;
          errorMessage = '';
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load work orders';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load work orders. Check network connection.';
        isLoading = false;
      });
    }
  }

  void _updateDisplayedOrders() {
    final startIndex = (currentPage - 1) * itemsPerPage;
    final endIndex = startIndex + itemsPerPage;
    
    if (startIndex < workOrders.length) {
      displayedOrders = workOrders.sublist(
        startIndex,
        endIndex > workOrders.length ? workOrders.length : endIndex
      );
    } else {
      displayedOrders = [];
    }
  }

  void _goToPage(int page) {
    if (page < 1 || page > totalPages) return;
    
    setState(() {
      currentPage = page;
      _updateDisplayedOrders();
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_data');
    
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // Function to handle Add Packing Slip from card
  void _onAddPackingSlip(Map<String, dynamic> order) {
    print(jsonEncode(order));
    final workOrderId = _parseInt(order['work_order_no']);
    final workOrderRef = order['work_order_ref']?.toString() ?? '';
    final brand = order['work_order_brand']?.toString() ?? '';
    final workOrderNo = _parseInt(order['work_order_no']);
    
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddPackingSlipPage(
          workOrderId: workOrderId,
          workOrderRef: workOrderRef,
          brand: brand,
          workOrderNo: workOrderNo,
        ),
      ),
    ).then((value) {
      if (value == true) {
        _fetchWorkOrders();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = AppTheme.primaryColor;
    const gradientColors = AppTheme.gradientColors;
    const isDark = false;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.person, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              userName.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.8,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _fetchWorkOrders,
              tooltip: 'Refresh',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _logout,
              tooltip: 'Logout',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // KPI Cards Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                _buildKPICard(
                  'Pending Orders',
                  totalPendingCount.toString(),
                  Icons.assignment_outlined,
                  'Active work orders',
                ),
                _buildKPICard(
                  'Recently Closed',
                  totalClosedCount.toString(),
                  Icons.history_toggle_off,
                  'Closed work orders',
                ),
              ],
            ),
          ),

          // Tabs: Pending & Recently Closed
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (selectedTab != 'Pending') {
                          setState(() {
                            selectedTab = 'Pending';
                            currentPage = 1;
                          });
                          _fetchWorkOrders();
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: selectedTab == 'Pending' ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: selectedTab == 'Pending'
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            'Pending',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: selectedTab == 'Pending' ? primaryColor : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (selectedTab != 'Closed') {
                          setState(() {
                            selectedTab = 'Closed';
                            currentPage = 1;
                          });
                          _fetchWorkOrders();
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: selectedTab == 'Closed' ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: selectedTab == 'Closed'
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            'Recently Closed',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: selectedTab == 'Closed' ? primaryColor : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Work Orders List with Pagination
          Expanded(
            child: isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 50,
                          height: 50,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'LOADING WORK ORDERS...',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  )
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                errorMessage,
                                style: TextStyle(
                                  color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _fetchWorkOrders,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'RETRY',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : displayedOrders.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 64,
                                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'NO WORK ORDERS FOUND',
                                  style: TextStyle(
                                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: displayedOrders.length,
                                  itemBuilder: (context, index) {
                                    final order = displayedOrders[index];
                                    final totalReceive = _parseInt(order['total_receive']);
                                    final ref = order['work_order_ref']?.toString() ?? '';
                                    final hasWorkingDetails = totalReceive > 0 || receivedOrdersList.any((item) {
                                      final itemRef = item['work_order_rc_w_ref']?.toString() ?? '';
                                      return itemRef.trim().toLowerCase() == ref.trim().toLowerCase();
                                    });

                                    return WorkOrderCard(
                                      order: order,
                                      isClosed: selectedTab == 'Closed',
                                      hasWorkingDetails: hasWorkingDetails,
                                      onTap: () {
                                        Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => WorkOrderDetailPage(
                                              workOrderRef: order['work_order_ref']?.toString() ?? '',
                                              workOrderId: _parseInt(order['id']),
                                              workOrderNo: _parseInt(order['work_order_no']),
                                              brand: order['work_order_brand']?.toString() ?? '',
                                              factory: order['work_order_factory']?.toString() ?? '',
                                              status: order['work_order_status']?.toString() ?? '',
                                              date: order['work_order_date']?.toString() ?? '',
                                              count: _parseInt(order['work_order_count']),
                                              totalReceive: _parseInt(order['total_receive']), 
                                            ),
                                          ),
                                        ).then((value) {
                                          if (value == true) {
                                            _fetchWorkOrders();
                                          }
                                        });
                                      },
                                      onAddPackingSlip: () => _onAddPackingSlip(order),
                                    );
                                  },
                                ),
                              ),
                              // Pagination Controls
                            ],
                          ),
              ),
        ],
      ),
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, String subtitle) {
    const gradientColors = AppTheme.gradientColors;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Work Order Card Widget with Add Packing Slip Button
class WorkOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  final VoidCallback onAddPackingSlip;
  final bool isClosed;
  final bool hasWorkingDetails;

  const WorkOrderCard({
    super.key, 
    required this.order,
    required this.onTap,
    required this.onAddPackingSlip,
    required this.isClosed,
    required this.hasWorkingDetails,
  });

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = AppTheme.primaryColor;
    const gradientColors = AppTheme.gradientColors;

    final workOrderNo = order['work_order_no']?.toString() ?? 'N/A';
    final workOrderRef = order['work_order_ref']?.toString() ?? 'N/A';
    final workOrderDate = order['work_order_date']?.toString() ?? 'N/A';
    final brand = order['work_order_brand']?.toString() ?? 'N/A';
    final count = _parseInt(order['work_order_count']);
    final totalReceive = _parseInt(order['total_receive']);

    // Progress math
    final double progress = count > 0 ? (totalReceive / count) : 0.0;
    final int progressPercentage = (progress * 100).round().clamp(0, 100);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Accent color line on the left side of the card
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: isClosed ? AppTheme.red : null,
                  gradient: isClosed 
                      ? null 
                      : const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: AppTheme.gradientColors,
                        ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row: Work order no and brand badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'WO #$workOrderNo',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                                letterSpacing: 0.2,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                brand.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: primaryColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Work order reference description
                        Text(
                          workOrderRef,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF334155),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 14),
                        // Progress segment
                        // Row(
                        //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        //   children: [
                        //     Text(
                        //       '$totalReceive / $count Pcs Sent',
                        //       style: const TextStyle(
                        //         fontSize: 11,
                        //         fontWeight: FontWeight.w700,
                        //         color: Color(0xFF64748B),
                        //       ),
                        //     ),
                        //     Text(
                        //       '$progressPercentage%',
                        //       style: const TextStyle(
                        //         fontSize: 11,
                        //         fontWeight: FontWeight.w800,
                        //         color: primaryColor,
                        //       ),
                        //     ),
                        //   ],
                        // ),
                        // const SizedBox(height: 6),
                        // Custom thin progress bar
                        // ClipRRect(
                        //   borderRadius: BorderRadius.circular(4),
                        //   child: Container(
                        //     height: 6,
                        //     width: double.infinity,
                        //     color: const Color(0xFFF1F5F9),
                        //     child: Align(
                        //       alignment: Alignment.centerLeft,
                        //       child: FractionallySizedBox(
                        //         widthFactor: progress.clamp(0.0, 1.0),
                        //         child: Container(
                        //           decoration: const BoxDecoration(
                        //             gradient: LinearGradient(
                        //               colors: gradientColors,
                        //             ),
                        //           ),
                        //         ),
                        //       ),
                        //     ),
                        //   ),
                        // ),
                        // const SizedBox(height: 16),
                        // Bottom row: Date & Add Slip button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 13,
                                  color: Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  workOrderDate,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            if (!isClosed)
                              hasWorkingDetails
                                  ? ElevatedButton.icon(
                                      onPressed: onTap,
                                      icon: const Icon(Icons.visibility, size: 14, color: Colors.white),
                                      label: const Text(
                                        'VIEW',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          letterSpacing: 0.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    )
                                  : ElevatedButton.icon(
                                      onPressed: onAddPackingSlip,
                                      icon: const Icon(Icons.qr_code_scanner, size: 14, color: Colors.white),
                                      label: const Text(
                                        'ADD SLIP',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          letterSpacing: 0.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}