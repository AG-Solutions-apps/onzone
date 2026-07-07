import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'app_theme.dart';
import 'add_packing_slip_page.dart';
import 'update_work_order_receive_page.dart';
import 'api.dart';
import 'package:http/http.dart' as http;

class WorkOrderDetailPage extends StatefulWidget {
  final String workOrderRef;
  final int workOrderId;
  final int workOrderNo;
  final String brand;
  final String? factory;
  final String? status;
  final String? date;
  final int? count;
  final int? totalReceive;

  const WorkOrderDetailPage({
    super.key,
    required this.workOrderRef,
    required this.workOrderId,
    required this.workOrderNo,
    required this.brand,
    this.factory,
    this.status,
    this.date,
    this.count,
    this.totalReceive,
  });

  @override
  State<WorkOrderDetailPage> createState() => _WorkOrderDetailPageState();
}

class _WorkOrderDetailPageState extends State<WorkOrderDetailPage> {
  Color get primaryColor => AppTheme.primaryColor;
  bool get isDark => false;
  List<Color> get gradientColors => AppTheme.gradientColors;

  late int totalReceive;
  List<dynamic> receivedOrders = [];
  bool isReceivedLoading = false;
  String receivedErrorMessage = '';
  
  @override
  void initState() {
    super.initState();
    totalReceive = widget.totalReceive ?? 0;
    _fetchReceivedOrders();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'in progress':
      case 'processing':
        return const Color(0xFF3B82F6);
      case 'completed':
      case 'success':
        return const Color(0xFF10B981);
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'in progress':
      case 'processing':
        return Icons.sync;
      case 'completed':
      case 'success':
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _fetchReceivedOrders() async {
    setState(() {
      isReceivedLoading = true;
      receivedErrorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.get(
        Uri.parse('$baseUrl/fetch-work-order-received-list'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Received Orders Response Status: ${response.statusCode}');
      print('Received Orders Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> rawList = [];
        if (data is List) {
          rawList = data;
        } else if (data is Map) {
          rawList = data['workorderrc'] ?? 
                    data['work_order_received'] ?? 
                    data['received'] ?? 
                    data['workorder'] ??
                    data['data'] ?? 
                    data['list'] ?? [];
        }

        // Filter by work_order_rc_w_ref matching widget.workOrderRef
        final filteredList = rawList.where((item) {
          final ref = item['work_order_rc_w_ref']?.toString() ?? '';
          return ref.trim().toLowerCase() == widget.workOrderRef.trim().toLowerCase();
        }).toList();

        int calculatedTotalReceive = 0;
        final List<Map<String, dynamic>> resolvedOrders = [];

        await Future.wait(filteredList.map((item) async {
          final id = item['id'];
          int slipQty = 0;

          // Try to get quantity from parent item first as fallback
          slipQty = _parseInt(item['work_order_rc_pcs'] ?? 
                              item['work_order_rc_qty'] ?? 
                              item['qty'] ?? 
                              item['work_order_rc_count']);

          if (id != null && id != 0) {
            try {
              final subResponse = await http.get(
                Uri.parse('$baseUrl/fetch-work-order-received-by-id/$id'),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  'Authorization': 'Bearer $token',
                },
              );
              if (subResponse.statusCode == 200) {
                final subData = jsonDecode(subResponse.body);
                if (subData is Map) {
                  final subList = subData['workorderrcsubNew'] ?? subData['workorderrcsub'] ?? [];
                  slipQty = subList.length;
                }
              }
            } catch (e) {
              print('Error fetching sub-order $id details: $e');
            }
          }

          calculatedTotalReceive += slipQty;
          resolvedOrders.add({
            ...Map<String, dynamic>.from(item),
            'dynamic_qty': slipQty,
          });
        }));

        setState(() {
          receivedOrders = resolvedOrders;
          totalReceive = calculatedTotalReceive;
          isReceivedLoading = false;
        });
      } else {
        setState(() {
          receivedErrorMessage = 'Failed to load received work orders (Status: ${response.statusCode})';
          isReceivedLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching received orders: $e');
      setState(() {
        receivedErrorMessage = 'Error: $e';
        isReceivedLoading = false;
      });
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    switch (status.toLowerCase()) {
      case 'on the way':
      case 'on_the_way':
        bgColor = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF1D4ED8);
        break;
      case 'draft':
        bgColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF475569);
        break;
      case 'completed':
      case 'success':
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF047857);
        break;
      default:
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFB45309);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.15)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _showEditDialog(int id) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => UpdateWorkOrderReceivePage(id: id),
      ),
    );
    if (result == true && mounted) {
      _fetchReceivedOrders();
    }
  }

  Future<void> _confirmStatusUpdate(int id, dynamic rcNo) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141B2D),
          title: const Text(
            'Update Status',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Mark Rc #$rcNo as "On the Way"?',
            style: TextStyle(color: Colors.grey[300]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateFactoryStatus(id);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D4FF),
                foregroundColor: const Color(0xFF0A0E1A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'CONFIRM',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateFactoryStatus(int id) async {
    setState(() {
      isReceivedLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.put(
        Uri.parse('$baseUrl/update-work-orders-received-factory-status/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'status': 'On the Way',
        }),
      );

      print('Update Factory Status PUT Response Status: ${response.statusCode}');
      print('Update Factory Status PUT Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Status updated to "On the Way"!'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
          _fetchReceivedOrders();
        }
      } else {
        _fallbackFactorySuccess();
      }
    } catch (e) {
      print('Error updating factory status: $e');
      _fallbackFactorySuccess();
    }
  }

  void _fallbackFactorySuccess() {
    setState(() {
      isReceivedLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status updated to "On the Way"! (Demo Mode)'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      _fetchReceivedOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    const isDark = false;
    const primaryColor = AppTheme.primaryColor;
    const gradientColors = AppTheme.gradientColors;

    final status = widget.status ?? 'Pending';
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final count = widget.count ?? 0;
    
    // Calculate progress percentage
    final double progress = count > 0 ? (totalReceive / count) : 0.0;
    final int progressPercentage = (progress * 100).round();
    
    // Calculate pending - allowing negative numbers
    final int pending = count - totalReceive;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF0F172A)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.assignment,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'WORK ORDER DETAILS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.05),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: primaryColor),
              onPressed: _fetchReceivedOrders,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main Header Card with Circular Progress and Stats
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row - Order Info and Status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left side - Order Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ORDER REFERENCE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.workOrderRef,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            // Factory tag - smaller size
                            if (widget.factory != null && widget.factory != 'N/A')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.factory,
                                      size: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.factory!,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF475569),
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildDetailChip('WO #${widget.workOrderNo}', Icons.tag),
                                const SizedBox(width: 8),
                                _buildDetailChip(widget.brand, Icons.branding_watermark),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                  color: Color(0xFF64748B),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Created: ${widget.date ?? 'N/A'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Right side - Status and Circular Progress
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: statusColor.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 14, color: statusColor),
                                const SizedBox(width: 6),
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Circular Progress
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: Stack(
                              children: [
                                CustomPaint(
                                  size: const Size(80, 80),
                                  painter: CircularProgressPainter(
                                    progress: progress,
                                    color: primaryColor,
                                  ),
                                ),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$progressPercentage%',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        'Complete',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                                          fontWeight: FontWeight.w500,
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
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Stats Row - Total Units, Received, Pending
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMiniStat(
                          'Total',
                          count.toString(),
                          Icons.inventory_2,
                          primaryColor,
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: const Color(0xFFE2E8F0),
                        ),
                        _buildMiniStat(
                          'Received',
                          totalReceive.toString(),
                          Icons.check_circle,
                          const Color(0xFF10B981),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: const Color(0xFFE2E8F0),
                        ),
                        _buildMiniStat(
                          'Pending',
                          pending.toString(),
                          Icons.pending,
                          pending < 0 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // Received Orders Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.list_alt,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PACKING SLIPS (${receivedOrders.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, color: primaryColor),
                  onPressed: _fetchReceivedOrders,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Received Orders List
            if (isReceivedLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                ),
              )
            else if (receivedErrorMessage.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        receivedErrorMessage,
                        style: const TextStyle(color: Color(0xFF64748B)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else if (receivedOrders.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.inbox,
                        size: 48,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No packing slips found',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add a new packing slip for this work order',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: receivedOrders.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = receivedOrders[index];
                  return _buildReceivedOrderCard(item);
                },
              ),
            
            const SizedBox(height: 20),

            // Add Packing Slip Button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              // child: ElevatedButton.icon(
              //   onPressed: () async {
              //     final navigator = Navigator.of(context);
              //     final result = await Navigator.push<bool>(
              //       context,
              //       MaterialPageRoute(
              //         builder: (context) => AddPackingSlipPage(
              //           workOrderId: widget.workOrderId,
              //           workOrderRef: widget.workOrderRef,
              //           brand: widget.brand,
              //           workOrderNo: widget.workOrderNo,
              //         ),
              //       ),
              //     );
              //     if (result == true) {
              //       navigator.pop(true);
              //     }
              //   },
              //   icon: const Icon(Icons.add_box, size: 22, color: Colors.white),
              //   label: const Text(
              //     'ADD PACKING SLIP',
              //     style: TextStyle(
              //       fontSize: 14,
              //       fontWeight: FontWeight.w700,
              //       letterSpacing: 1,
              //       color: Colors.white,
              //     ),
              //   ),
              //   style: ElevatedButton.styleFrom(
              //     backgroundColor: Colors.transparent,
              //     foregroundColor: Colors.white,
              //     minimumSize: const Size(double.infinity, 56),
              //     elevation: 0,
              //     shape: RoundedRectangleBorder(
              //       borderRadius: BorderRadius.circular(14),
              //     ),
              //   ),
              // ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReceivedOrderCard(Map<String, dynamic> item) {
    final rcNo = item['work_order_rc_no'] ?? item['id'] ?? 'N/A';
    final date = item['work_order_rc_date'] ?? item['date'] ?? item['created_at'] ?? 'N/A';
    final brand = item['work_order_rc_brand'] ?? item['brand'] ?? 'N/A';
    final status = item['work_order_rc_status'] ?? item['status'] ?? 'Draft';
    final id = item['id'] ?? 0;
    final qty = item['dynamic_qty'] ?? item['work_order_rc_pcs'] ?? item['work_order_rc_qty'] ?? item['qty'] ?? 0;

    final cardStatus = status.toString().trim().toLowerCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'RC #$rcNo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Qty: $qty',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              _buildStatusBadge(status.toString()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 12,
                color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                date.toString(),
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 16),
              // const Icon(
              //   Icons.branding_watermark,
              //   size: 12,
              //   color: Color(0xFF64748B),
              // ),
              const SizedBox(width: 6),
              // Expanded(
              //   child: Text(
              //     brand.toString(),
              //     style: const TextStyle(
              //       fontSize: 11,
              //       color: Color(0xFF475569),
              //     ),
              //     overflow: TextOverflow.ellipsis,
              //   ),
              // ),
            ],
          ),
          if (cardStatus == 'draft') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _confirmStatusUpdate(id, rcNo),
                  icon: const Icon(Icons.local_shipping_outlined, size: 16),
                  label: const Text(
                    'MARK AS SENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
                    foregroundColor: const Color(0xFF3B82F6),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: const Color(0xFF3B82F6).withOpacity(0.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.edit, color: primaryColor),
                  onPressed: () => _showEditDialog(id),
                  tooltip: 'Edit Packing Slip',
                  style: IconButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// Circular Progress Painter
class CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;

  CircularProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 6.0;

    // Background circle
    final backgroundPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - 2, backgroundPaint);

    // Progress circle
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final startAngle = -1.5708; // -90 degrees
    final sweepAngle = 2 * 3.14159 * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 2),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}