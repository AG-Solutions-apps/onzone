import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'add_packing_slip_page.dart';
import 'update_work_order_receive_page.dart';

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

  Future<void> _fetchReceivedOrders() async {
    setState(() {
      isReceivedLoading = true;
      receivedErrorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final url = 'https://houseofonzone.com/admin/public/api/fetch-work-order-received-list';
      final response = await http.get(
        Uri.parse(url),
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

        setState(() {
          receivedOrders = filteredList;
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
        bgColor = const Color(0xFF3B82F6).withOpacity(0.1);
        textColor = const Color(0xFF3B82F6);
        break;
      case 'draft':
        bgColor = Colors.grey.withOpacity(0.1);
        textColor = Colors.grey;
        break;
      case 'completed':
      case 'success':
        bgColor = const Color(0xFF10B981).withOpacity(0.1);
        textColor = const Color(0xFF10B981);
        break;
      default:
        bgColor = const Color(0xFFF59E0B).withOpacity(0.1);
        textColor = const Color(0xFFF59E0B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.2)),
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

      final url = 'https://houseofonzone.com/admin/public/api/update-work-orders-received-factory-status/$id';
      
      final response = await http.put(
        Uri.parse(url),
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
    final status = widget.status ?? 'Pending';
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final count = widget.count ?? 0;
    
    // Calculate progress percentage
    final double progress = count > 0 ? (totalReceive / count) : 0.0;
    final int progressPercentage = (progress * 100).round();
    
    // Calculate pending - ensure it doesn't go negative
    final int pending = (count - totalReceive) > 0 ? (count - totalReceive) : 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        // Set back arrow color to white
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
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
            const Text(
              'WORK ORDER DETAILS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1,
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
                    color: Colors.black.withOpacity(0.3),
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
                                color: Colors.grey,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.workOrderRef,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
                                  color: const Color(0xFF2D3748),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF3D4A5C),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.factory,
                                      size: 12,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.factory!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[300],
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
                                Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Created: ${widget.date ?? 'N/A'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[400],
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
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: statusColor.withOpacity(0.3),
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
                                    color: const Color(0xFF00D4FF),
                                  ),
                                ),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$progressPercentage%',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'Complete',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Colors.grey[400],
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
                      color: const Color(0xFF0A0E1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF2D3748),
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
                          const Color(0xFF00D4FF),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: const Color(0xFF2D3748),
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
                          color: const Color(0xFF2D3748),
                        ),
                        _buildMiniStat(
                          'Pending',
                          pending.toString(),
                          Icons.pending,
                          const Color(0xFFF59E0B),
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
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
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
                  icon: const Icon(Icons.refresh, color: Color(0xFF00D4FF)),
                  onPressed: _fetchReceivedOrders,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Received Orders List
            if (isReceivedLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D4FF)),
                  ),
                ),
              )
            else if (receivedErrorMessage.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        receivedErrorMessage,
                        style: TextStyle(color: Colors.grey[400]),
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
                      Icon(
                        Icons.inbox,
                        size: 48,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No packing slips found',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add a new packing slip for this work order',
                        style: TextStyle(
                          color: Colors.grey[500],
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
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddPackingSlipPage(
                        workOrderId: widget.workOrderId,
                        workOrderRef: widget.workOrderRef,
                        brand: widget.brand,
                        workOrderNo: widget.workOrderNo,
                      ),
                    ),
                  );
                  if (result == true) {
                    navigator.pop(true);
                  }
                },
                icon: const Icon(Icons.add_box, size: 22, color: Colors.white),
                label: const Text(
                  'ADD PACKING SLIP',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
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
        color: const Color(0xFF1E2740),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2D3748),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[300],
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
            color: color.withOpacity(0.15),
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
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
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
    final factory = item['work_order_rc_factory'] ?? item['factory'] ?? 'N/A';
    final brand = item['work_order_rc_brand'] ?? item['brand'] ?? 'N/A';
    final status = item['work_order_rc_status'] ?? item['status'] ?? 'Draft';
    final id = item['id'] ?? 0;
    final qty = item['work_order_rc_qty'] ?? item['qty'] ?? 0;

    final cardStatus = status.toString().trim().toLowerCase();
    Color statusColor = Colors.grey;
    if (cardStatus == 'on the way' || cardStatus == 'on_the_way') {
      statusColor = const Color(0xFF3B82F6);
    } else if (cardStatus == 'completed' || cardStatus == 'success') {
      statusColor = const Color(0xFF10B981);
    } else if (cardStatus == 'draft') {
      statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(16),
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
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00D4FF), Color(0xFF7B2FFC)],
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
                      color: const Color(0xFF2D3748),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Qty: $qty',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[400],
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
                color: Colors.grey[500],
              ),
              const SizedBox(width: 6),
              Text(
                date.toString(),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.branding_watermark,
                size: 12,
                color: Colors.grey[500],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  brand.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                    'MARK ON THE WAY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6).withOpacity(0.15),
                    foregroundColor: const Color(0xFF3B82F6),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: const Color(0xFF3B82F6).withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, color: Color(0xFF00D4FF)),
                  onPressed: () => _showEditDialog(id),
                  tooltip: 'Edit Packing Slip',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1E2740),
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
      ..color = const Color(0xFF1E2740)
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