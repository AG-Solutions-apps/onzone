import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'work_order_detail_page.dart';
import 'add_packing_slip_page.dart';

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
  
  // Pagination variables
  int currentPage = 1;
  int itemsPerPage = 10;
  int totalPages = 1;

  final String workOrderUrl = 'https://houseofonzone.com/admin/public/api/fetch-work-order-list';

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

      final response = await http.get(
        Uri.parse(workOrderUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['workorder'] != null && data['workorder'] is List) {
          setState(() {
            workOrders = data['workorder'];
            totalPages = (workOrders.length / itemsPerPage).ceil();
            _updateDisplayedOrders();
            isLoading = false;
            errorMessage = '';
          });
          print('Loaded ${workOrders.length} work orders');
        } else {
          setState(() {
            errorMessage = 'No work orders found';
            isLoading = false;
          });
        }
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
      final response = await http.get(
        Uri.parse(workOrderUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['workorder'] != null && data['workorder'] is List) {
          setState(() {
            workOrders = data['workorder'];
            totalPages = (workOrders.length / itemsPerPage).ceil();
            _updateDisplayedOrders();
            isLoading = false;
            errorMessage = '';
          });
          print('Loaded ${workOrders.length} work orders without token');
        } else {
          setState(() {
            errorMessage = 'No work orders found';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Failed to load work orders. Status: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
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
    final workOrderId = _parseInt(order['id']);
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.dashboard,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'WORK ORDER DASHBOARD',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF141B2D),
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.3),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2740),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00D4FF)),
              onPressed: _fetchWorkOrders,
              tooltip: 'Refresh',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2740),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.logout, color: Color(0xFFFF6B6B)),
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
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF141B2D),
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF1E2740),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                _buildKPICard(
                  'Total Orders',
                  workOrders.length.toString(),
                  Icons.assignment,
                  const Color(0xFF00D4FF),
                  'Total Work Orders',
                ),
                _buildKPICard(
                  'Active',
                  workOrders.where((order) {
                    final status = order['work_order_status']?.toString().toLowerCase() ?? '';
                    return status.contains('progress') || status.contains('process');
                  }).length.toString(),
                  Icons.pending_actions,
                  const Color(0xFFF59E0B),
                  'In Progress',
                ),
                _buildKPICard(
                  'Completed',
                  workOrders.where((order) {
                    final status = order['work_order_status']?.toString().toLowerCase() ?? '';
                    return status.contains('complete') || status.contains('done');
                  }).length.toString(),
                  Icons.check_circle,
                  const Color(0xFF10B981),
                  'Completed Orders',
                ),
              ],
            ),
          ),

          // User Profile Summary
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E2740), Color(0xFF141B2D)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF2D3748),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (userEmail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.email_outlined,
                              size: 14,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              userEmail,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                                letterSpacing: 0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Work Orders List with Pagination
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 50,
                          height: 50,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D4FF)),
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          'LOADING WORK ORDERS...',
                          style: TextStyle(
                            color: Color(0xFF00D4FF),
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
                                  color: const Color(0xFF1E2740),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                errorMessage,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _fetchWorkOrders,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00D4FF),
                                  foregroundColor: const Color(0xFF0A0E1A),
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
                                  color: Colors.grey[700],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'NO WORK ORDERS FOUND',
                                  style: TextStyle(
                                    color: Colors.grey[500],
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
                                    return WorkOrderCard(
                                      order: order,
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
                              if (totalPages > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141B2D),
                                    border: Border(
                                      top: BorderSide(
                                        color: const Color(0xFF1E2740),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      TextButton(
                                        onPressed: currentPage > 1 
                                            ? () => _goToPage(currentPage - 1)
                                            : null,
                                        style: TextButton.styleFrom(
                                          foregroundColor: currentPage > 1 
                                              ? const Color(0xFF00D4FF) 
                                              : Colors.grey[700],
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.chevron_left, size: 18),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'PREV',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF00D4FF).withOpacity(0.2),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          '${currentPage.toString().padLeft(2, '0')} / ${totalPages.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            fontSize: 13,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: currentPage < totalPages
                                            ? () => _goToPage(currentPage + 1)
                                            : null,
                                        style: TextButton.styleFrom(
                                          foregroundColor: currentPage < totalPages 
                                              ? const Color(0xFF00D4FF) 
                                              : Colors.grey[700],
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        child: Row(
                                          children: [
                                            const Text(
                                              'NEXT',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.chevron_right, size: 18),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color, String subtitle) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2740),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                Icon(
                  icon,
                  color: color,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 9,
                fontWeight: FontWeight.w400,
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

  const WorkOrderCard({
    super.key, 
    required this.order,
    required this.onTap,
    required this.onAddPackingSlip,
  });

  @override
  Widget build(BuildContext context) {
    final status = order['work_order_status'] ?? '';
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    
    final workOrderRef = order['work_order_ref']?.toString() ?? 'N/A';
    final workOrderDate = order['work_order_date']?.toString() ?? 'N/A';
    final factory = order['work_order_factory']?.toString() ?? 'N/A';
    final brand = order['work_order_brand']?.toString() ?? 'N/A';
    final count = int.tryParse(order['work_order_count']?.toString() ?? '') ?? 0;
    final totalReceive = int.tryParse(order['total_receive']?.toString() ?? '') ?? 0;
    final workOrderNo = order['work_order_no']?.toString() ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2740), Color(0xFF141B2D)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF2D3748),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                workOrderNo,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                workOrderRef,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              statusIcon,
                              size: 12,
                              color: statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(Icons.factory, factory),
                            const SizedBox(height: 8),
                            _buildInfoRow(Icons.branding_watermark, brand),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.inventory_2,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$count PCS',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: totalReceive > 0 
                                  ? const Color(0xFF10B981).withOpacity(0.15) 
                                  : Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: totalReceive > 0 
                                    ? const Color(0xFF10B981).withOpacity(0.3) 
                                    : Colors.grey[700]!,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 12,
                                  color: totalReceive > 0 ? const Color(0xFF10B981) : Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$totalReceive RECEIVED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: totalReceive > 0 ? const Color(0xFF10B981) : Colors.grey[500],
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, const Color(0xFF2D3748), Colors.transparent],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            workOrderDate,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D3748),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'WO #$workOrderNo',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Add Packing Slip Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E1A),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(
                top: BorderSide(
                  color: const Color(0xFF2D3748),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.add_box_outlined,
                      size: 18,
                      color: const Color(0xFF00D4FF).withOpacity(0.7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ADD PACKING SLIP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF00D4FF).withOpacity(0.7),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: onAddPackingSlip,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'ADD NEW',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B2FFC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: Colors.grey[500],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[300],
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('factory') || lowerStatus.contains('production')) {
      return const Color(0xFF3B82F6);
    } else if (lowerStatus.contains('complete') || lowerStatus.contains('done')) {
      return const Color(0xFF10B981);
    } else if (lowerStatus.contains('progress') || lowerStatus.contains('process')) {
      return const Color(0xFFF59E0B);
    } else if (lowerStatus.contains('pending') || lowerStatus.contains('wait')) {
      return const Color(0xFFEF4444);
    } else if (lowerStatus.contains('shipped') || lowerStatus.contains('deliver')) {
      return const Color(0xFF8B5CF6);
    } else {
      return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('factory') || lowerStatus.contains('production')) {
      return Icons.factory;
    } else if (lowerStatus.contains('complete') || lowerStatus.contains('done')) {
      return Icons.check_circle;
    } else if (lowerStatus.contains('progress') || lowerStatus.contains('process')) {
      return Icons.hourglass_top;
    } else if (lowerStatus.contains('pending') || lowerStatus.contains('wait')) {
      return Icons.pending;
    } else if (lowerStatus.contains('shipped') || lowerStatus.contains('deliver')) {
      return Icons.local_shipping;
    } else {
      return Icons.help_outline;
    }
  }
}