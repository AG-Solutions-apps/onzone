import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'app_theme.dart';
import 'api.dart';
import 'order/barcode_scanner_page.dart';
import 'store_login_page.dart';
import 'app_utils.dart';

class StoreManagementPage extends StatefulWidget {
  const StoreManagementPage({super.key});

  @override
  State<StoreManagementPage> createState() => _StoreManagementPageState();
}

class _StoreManagementPageState extends State<StoreManagementPage> {
  List<dynamic> _inventory = [];
  bool _isLoadingInventory = true;
  bool _isProcessingScan = false;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      if (token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access denied. Please login with Admin credentials.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const StoreLoginPage()),
          );
        }
        return;
      }

      final inventoryStr = prefs.getString('store_inventory');
      if (inventoryStr != null && inventoryStr.isNotEmpty) {
        setState(() {
          _inventory = jsonDecode(inventoryStr);
        });
      }
    } catch (e) {
      debugPrint('Error loading store inventory: $e');
    } finally {
      setState(() {
        _isLoadingInventory = false;
      });
    }
  }

  Future<void> _saveInventory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('store_inventory', jsonEncode(_inventory));
    } catch (e) {
      debugPrint('Error saving store inventory: $e');
    }
  }

  void _clearInventory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Inventory'),
        content: const Text('Are you sure you want to delete all stored boxes? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _inventory.clear();
              });
              _saveInventory();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Inventory cleared successfully.')),
              );
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteBox(int index) {
    setState(() {
      _inventory.removeAt(index);
    });
    _saveInventory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Box removed from inventory.')),
    );
  }

  Future<void> _startBarcodeScan() async {
    FocusScope.of(context).unfocus();
    final List<String>? barcodes = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerPage(singleScan: false)),
    );

    if (barcodes != null && barcodes.isNotEmpty) {
      _processScannedBarcodes(barcodes);
    }
  }

  Future<void> _processScannedBarcodes(List<String> barcodes) async {
    setState(() {
      _isProcessingScan = true;
    });

    int addedCount = 0;
    int duplicateCount = 0;
    int errorCount = 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      for (final barcode in barcodes) {
        final cleanBarcode = barcode.trim();
        if (cleanBarcode.isEmpty) continue;

        final parts = cleanBarcode.split('/');
        String boxKey = '';
        String ref = '';
        String? receivedId;

        if (parts.length >= 3 && parts[0].toLowerCase() == 'rc') {
          receivedId = parts[1].trim();
          boxKey = parts[2].trim();
          ref = 'REC/ID/$receivedId';
        } else {
          if (parts.length < 2) {
            errorCount++;
            continue;
          }
          boxKey = parts.last.trim();
          ref = parts.sublist(0, parts.length - 1).join('/').trim();
        }

        try {
          Map<String, dynamic> detailsData;

          if (receivedId != null) {
            final detailsUrl = '$baseUrl/fetch-work-order-received-view-by-id/$receivedId';
            final detailsResponse = await http.get(Uri.parse(detailsUrl), headers: headers);
            if (detailsResponse.statusCode != 200) throw 'Fetch failed';
            detailsData = jsonDecode(detailsResponse.body);
          } else {
            // Fetch received list fallback
            final listUrl = '$baseUrl/fetch-work-order-received-list';
            final listResponse = await http.get(Uri.parse(listUrl), headers: headers);
            if (listResponse.statusCode != 200) throw 'List fetch failed';

            final listData = jsonDecode(listResponse.body);
            List<dynamic> rawList = [];
            if (listData is List) {
              rawList = listData;
            } else if (listData is Map) {
              rawList = listData['workorderrc'] ?? 
                        listData['work_order_received'] ?? 
                        listData['received'] ?? 
                        listData['workorder'] ??
                        listData['data'] ?? 
                        listData['list'] ?? [];
            }

            String constructReceiptRef(Map<String, dynamic> item) {
              final directRef = item['work_order_rc_ref']?.toString() ?? '';
              if (directRef.isNotEmpty) return directRef;

              final brand = item['work_order_rc_brand']?.toString() ?? 'OZ';
              final rcNo = item['work_order_rc_no']?.toString() ?? '';
              final wRef = item['work_order_rc_w_ref']?.toString() ?? '';

              String year = '';
              final wRefParts = wRef.split('/');
              if (wRefParts.length >= 3) {
                year = wRefParts.last;
              }

              String constructed = 'REC/$brand/$rcNo';
              if (year.isNotEmpty) {
                constructed += '/$year';
              }
              return constructed;
            }

            final matchedReceipt = rawList.firstWhere(
              (item) {
                final itemRef = constructReceiptRef(item);
                final normalizedItemRef = formatWorkOrderRef(itemRef);
                final normalizedTargetRef = formatWorkOrderRef(ref);
                return normalizedItemRef.trim().toLowerCase() == normalizedTargetRef.trim().toLowerCase();
              },
              orElse: () => null,
            );

            if (matchedReceipt == null) throw 'Not found';

            final id = matchedReceipt['id'];
            final detailsUrl = '$baseUrl/fetch-work-order-received-view-by-id/$id';
            final detailsResponse = await http.get(Uri.parse(detailsUrl), headers: headers);
            if (detailsResponse.statusCode != 200) throw 'Details fetch failed';

            detailsData = jsonDecode(detailsResponse.body);
          }

          // Resolve reference name
          String? actualRef;
          if (detailsData['workorderrc'] != null) {
            final parentRc = detailsData['workorderrc'];
            if (parentRc is Map) {
              actualRef = parentRc['work_order_rc_ref']?.toString();
            } else if (parentRc is List && parentRc.isNotEmpty) {
              actualRef = parentRc.first['work_order_rc_ref']?.toString();
            }
          }
          if (actualRef != null && actualRef.isNotEmpty) {
            ref = actualRef;
          }

          // Duplicate Check
          final alreadyExists = _inventory.any(
            (element) => element['ref'].toString().toLowerCase() == ref.toLowerCase() &&
                         element['boxNo'].toString() == boxKey,
          );

          if (alreadyExists) {
            duplicateCount++;
            continue;
          }

          final List<dynamic> subList = detailsData['workorderrcsub'] ?? [];
          final boxItems = subList.where((item) {
            final itemBox = item['work_order_rc_sub_box']?.toString() ??
                            item['work_order_rc_sub_box_no']?.toString() ??
                            item['box_no']?.toString() ??
                            '';
            return itemBox.trim() == boxKey;
          }).toList();

          if (boxItems.isEmpty) {
            errorCount++;
            continue;
          }

          // Group items
          final Map<String, Map<String, dynamic>> grouped = {};
          for (var item in boxItems) {
            final itemBarcode = item['work_order_rc_sub_barcode']?.toString() ?? '';
            final size = item['finished_stock_size']?.toString() ?? 'N/A';
            final amount = double.tryParse(item['finished_stock_amount']?.toString() ?? '') ?? 0.0;

            final key = '$itemBarcode|$size|$amount';
            if (!grouped.containsKey(key)) {
              grouped[key] = {
                'barcode': itemBarcode,
                'size': size,
                'amount': amount,
                'quantity': 1,
              };
            } else {
              grouped[key]!['quantity'] = (grouped[key]!['quantity'] as int) + 1;
            }
          }

          final list = grouped.values.toList();
          list.sort((a, b) => (a['barcode'] as String).compareTo(b['barcode'] as String));

          int boxPcs = 0;
          double boxAmount = 0.0;
          for (var x in list) {
            final q = x['quantity'] as int;
            final a = x['amount'] as double;
            boxPcs += q;
            boxAmount += q * a;
          }

          _inventory.insert(0, {
            'ref': ref,
            'boxNo': boxKey,
            'pcs': boxPcs,
            'amount': boxAmount,
            'items': list,
            'addedAt': DateTime.now().toIso8601String(),
          });
          addedCount++;

        } catch (e) {
          errorCount++;
        }
      }

      _saveInventory();

    } catch (e) {
      _showErrorDialog('Error Occurred', 'An error occurred while fetching details: $e');
    } finally {
      setState(() {
        _isProcessingScan = false;
      });

      if (mounted) {
        String msg = 'Added $addedCount boxes.';
        if (duplicateCount > 0) msg += ' ($duplicateCount duplicates skipped)';
        if (errorCount > 0) msg += ' ($errorCount errors)';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: errorCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _submitInventoryDialog() async {
    if (_inventory.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Count total boxes
    final boxCount = _inventory.length;
    
    // Count total pieces
    int totalPcs = 0;
    for (var box in _inventory) {
      totalPcs += int.tryParse(box['pcs']?.toString() ?? '0') ?? 0;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.cloud_upload_outlined, color: AppTheme.TColor),
              const SizedBox(width: 10),
              const Text('Confirm Submission', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are about to upload scanned data to the server:',
                style: TextStyle(color: isDark ? Colors.grey[300] : const Color(0xFF475569), fontSize: 14),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Boxes:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('$boxCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Pieces:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('$totalPcs Pcs', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This will update the work order status. Are you sure you want to proceed?',
                style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF475569))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _sendInventoryToBackend();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.TColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Confirm & Send', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendInventoryToBackend() async {
    setState(() {
      _isProcessingScan = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      List<Map<String, dynamic>> boxdata = [];
      for (var box in _inventory) {
        final String ref = box['ref'].toString();
        final String boxNo = box['boxNo'].toString();
        final List<dynamic> items = box['items'] as List<dynamic>;
        
        for (var item in items) {
          boxdata.add({
            'work_order_rc_sub_ref': ref,
            'box': boxNo,
            'finished_stock_barcode': item['barcode']?.toString() ?? '',
            'finished_stock_amount': item['amount']?.toString() ?? '0',
            'total_qnty': item['quantity']?.toString() ?? '0',
          });
        }
      }

      final response = await http.put(
        Uri.parse('$baseUrl/updateworkordersreceivedstatusbox'),
        headers: headers,
        body: jsonEncode({
          'boxdata': boxdata,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _inventory.clear();
        });
        _saveInventory();

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Text('Success'),
                ],
              ),
              content: const Text('Store inventory details successfully submitted to the server.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        final errorMsg = jsonDecode(response.body)['message'] ?? 'Status code: ${response.statusCode}';
        throw 'Server error: $errorMsg';
      }
    } catch (e) {
      _showErrorDialog('Submission Failed', 'Failed to submit scans: $e');
    } finally {
      setState(() {
        _isProcessingScan = false;
      });
    }
  }



  Widget _buildTableCell(String text, bool isDark, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? FontWeight.w800 : FontWeight.w600,
          color: isHeader
              ? (isDark ? Colors.grey[350] : const Color(0xFF0F172A))
              : (isDark ? Colors.grey[400] : const Color(0xFF334155)),
        ),
      ),
    );
  }

  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTheme.gradientColors2,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'STORE MANAGEMENT',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
        actions: [
          if (_inventory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              tooltip: 'Clear All',
              onPressed: _clearInventory,
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              await prefs.remove('app_mode');
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          _isLoadingInventory
              ? const Center(child: CircularProgressIndicator())
              : _inventory.isEmpty
                  ? _buildEmptyState(isDark)
                  : _buildInventoryList(isDark),
          if (_isProcessingScan)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Fetching box details...',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startBarcodeScan,
        label: const Text('Scan Barcode', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
        backgroundColor: AppTheme.TColor,
      ),
      bottomNavigationBar: _inventory.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _submitInventoryDialog,
                        icon: const Icon(Icons.cloud_upload, color: Colors.white),
                        label: Text(
                          'Send To Stack (${_inventory.length} Boxes)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF1E293B) : Colors.orange.shade50,
              ),
              child: Icon(
                Icons.store,
                size: 72,
                color: isDark ? Colors.orange.shade300 : Colors.orange.shade500,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Stored Inventory',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the scan button to scan and preview a box barcode (e.g. REC/OZ/21/1) to add it to your inventory.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBoxDetailsDialog(Map<String, dynamic> box) {
    final ref = box['ref']?.toString() ?? 'N/A';
    final boxNo = box['boxNo']?.toString() ?? '0';
    final totalPcs = int.tryParse(box['pcs']?.toString() ?? '0') ?? 0;
    final totalAmount = double.tryParse(box['amount']?.toString() ?? '0') ?? 0.0;
    final List<dynamic> items = box['items'] ?? [];
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppTheme.gradientColors2,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Box $boxNo Details',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ref: $ref',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Summary Info bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Pcs: $totalPcs',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? Colors.grey[300] : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Amount: ₹${totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? Colors.grey[300] : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                // Table details scrollable list
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12.0),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.0),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.4),
                        3: FlexColumnWidth(1.0),
                      },
                      border: TableBorder.symmetric(
                        inside: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                      children: [
                        TableRow(
                          children: [
                            _buildTableCell('Barcode', isDark, isHeader: true),
                            _buildTableCell('Size', isDark, isHeader: true),
                            _buildTableCell('Amount (₹)', isDark, isHeader: true),
                            _buildTableCell('Quantity', isDark, isHeader: true),
                          ],
                        ),
                        ...items.map((row) {
                          final barcode = row['barcode'] as String;
                          final size = row['size'] as String;
                          final amount = row['amount'] as double;
                          final quantity = row['quantity'] as int;

                          return TableRow(
                            children: [
                              _buildTableCell(barcode, isDark),
                              _buildTableCell(size, isDark),
                              _buildTableCell(amount.toStringAsFixed(2), isDark),
                              _buildTableCell(quantity.toString(), isDark),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInventoryList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: _inventory.length,
      itemBuilder: (context, index) {
        final box = _inventory[index];
        final ref = box['ref']?.toString() ?? 'N/A';
        final boxNo = box['boxNo']?.toString() ?? '0';
        final pcs = box['pcs']?.toString() ?? '0';
        final amount = double.tryParse(box['amount']?.toString() ?? '') ?? 0.0;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showBoxDetailsDialog(box),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.inventory_2,
                          color: isDark ? Colors.orange.shade400 : Colors.orange.shade700,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Box $boxNo',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ref: $ref',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$pcs Pcs',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.grey[450] : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showBoxDetailsDialog(box),
                        icon: Icon(Icons.visibility, size: 16, color: isDark ? Colors.orange.shade300 : AppTheme.TColor),
                        label: Text(
                          'View',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.orange.shade300 : AppTheme.TColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        onPressed: () => _deleteBox(index),
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        label: const Text(
                          'Remove',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
