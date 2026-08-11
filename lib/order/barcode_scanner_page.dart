import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../api.dart';
import '../app_theme.dart';
import '../app_utils.dart';

class BarcodeScannerPage extends StatefulWidget {
  final bool singleScan;
  const BarcodeScannerPage({super.key, this.singleScan = false});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController controller = MobileScannerController();
  final List<String> _scannedBarcodes = [];
  final Map<String, DateTime> _lastScannedTimes = {};
  // Maps raw barcode -> human-friendly display label (ref + box)
  final Map<String, String> _barcodeDisplayLabels = {};
  String? _latestDetectedBarcode;
  bool _hasPopped = false;

  // Flashlight and camera state
  bool _isTorchOn = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _captureBarcode() {
    if (_latestDetectedBarcode != null) {
      _onBarcodeDetected(_latestDetectedBarcode!);
      setState(() {
        _latestDetectedBarcode = null; // Clear focus after scanning
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please align a barcode in the viewfinder first.'),
          duration: Duration(milliseconds: 1000),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onBarcodeDetected(String barcode) {
    final cleaned = barcode.trim();
    if (cleaned.isEmpty) return;

    if (widget.singleScan) {
      HapticFeedback.lightImpact();
      Navigator.pop(context, [cleaned]);
      return;
    }

    // DUPLICATE PREVENT
    if (_scannedBarcodes.contains(cleaned)) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barcode "$cleaned" already exists in the list!'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final lastTime = _lastScannedTimes[cleaned];

    // Throttle duplicate scans of the exact same barcode for 1.5 seconds
    if (lastTime != null && now.difference(lastTime).inMilliseconds < 1500) {
      return;
    }

    _lastScannedTimes[cleaned] = now;

    // Trigger haptic feedback
    HapticFeedback.lightImpact();

    setState(() {
      _scannedBarcodes.add(cleaned);
    });

    // Resolve a friendly display label in background (for RC/id/box format)
    _resolveBarcodeLabel(cleaned);

    // Show a temporary Toast/SnackBar overlay
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scanned: $cleaned'),
        duration: const Duration(milliseconds: 600),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Fetches the human-friendly reference label for RC/id/box barcodes
  /// and updates [_barcodeDisplayLabels] silently in the background.
  Future<void> _resolveBarcodeLabel(String barcode) async {
    final parts = barcode.trim().split('/');
    // Only handle RC/id/box format
    if (parts.length < 3 || parts[0].toLowerCase() != 'rc') return;

    final receivedId = parts[1].trim();
    final boxKey = parts[2].trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('$baseUrl/fetch-work-order-received-view-by-id/$receivedId'),
        headers: headers,
      );

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      String? ref;
      if (data['workorderrc'] != null) {
        final parentRc = data['workorderrc'];
        if (parentRc is Map) {
          ref = parentRc['work_order_rc_ref']?.toString();
        } else if (parentRc is List && parentRc.isNotEmpty) {
          ref = parentRc.first['work_order_rc_ref']?.toString();
        }
      }

      if (ref != null && ref.isNotEmpty && mounted) {
        setState(() {
          _barcodeDisplayLabels[barcode] = '$ref | Box $boxKey';
        });
      }
    } catch (_) {
      // Silently ignore — raw barcode will be shown as fallback
    }
  }

  Future<void> _fetchAndShowBarcodeDetails(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return;

    final parts = cleanBarcode.split('/');
    if (parts.length < 2) {
      _showScannerErrorDialog('Invalid Barcode Format', 'The barcode "$cleanBarcode" is not a valid box barcode. Expected format: REF/BOX_NO.');
      return;
    }

    String boxKey = '';
    String ref = '';
    String? receivedId;

    if (parts.length >= 3 && parts[0].toLowerCase() == 'rc') {
      receivedId = parts[1].trim();
      boxKey = parts[2].trim();
      ref = 'REC/ID/$receivedId';
    } else {
      boxKey = parts.last.trim();
      ref = parts.sublist(0, parts.length - 1).join('/').trim();
    }

    // Show loading spinner dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      },
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      Map<String, dynamic> detailsData;

      if (receivedId != null) {
        // Direct fetch by received ID
        final detailsUrl = '$baseUrl/fetch-work-order-received-view-by-id/$receivedId';
        final detailsResponse = await http.get(Uri.parse(detailsUrl), headers: headers);

        if (detailsResponse.statusCode != 200) {
          throw 'Failed to load receipt details (Status: ${detailsResponse.statusCode}).';
        }

        detailsData = jsonDecode(detailsResponse.body);
      } else {
        // 1. Fetch received list fallback
        final listUrl = '$baseUrl/fetch-work-order-received-list';
        final listResponse = await http.get(Uri.parse(listUrl), headers: headers);

        if (listResponse.statusCode != 200) {
          throw 'Failed to fetch receipts list (Status: ${listResponse.statusCode}).';
        }

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

        // 2. Find matching receipt by reference
        final matchedReceipt = rawList.firstWhere(
          (item) {
            final itemRef = constructReceiptRef(item);
            final normalizedItemRef = formatWorkOrderRef(itemRef);
            final normalizedTargetRef = formatWorkOrderRef(ref);
            return normalizedItemRef.trim().toLowerCase() == normalizedTargetRef.trim().toLowerCase();
          },
          orElse: () => null,
        );

        if (matchedReceipt == null) {
          Navigator.pop(context); // Pop loading spinner
          _showScannerErrorDialog('Receipt Not Found', 'Could not find any receipt with reference "$ref" in the system.');
          return;
        }

        final id = matchedReceipt['id'];
        final detailsUrl = '$baseUrl/fetch-work-order-received-view-by-id/$id';
        final detailsResponse = await http.get(Uri.parse(detailsUrl), headers: headers);

        if (detailsResponse.statusCode != 200) {
          throw 'Failed to load receipt details (Status: ${detailsResponse.statusCode}).';
        }

        detailsData = jsonDecode(detailsResponse.body);
      }

      // Resolve reference name from details payload
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
      
      final List<dynamic> subList = detailsData['workorderrcsub'] ?? [];

      // 4. Filter for items matching the scanned box number
      final boxItems = subList.where((item) {
        final itemBox = item['work_order_rc_sub_box']?.toString() ??
                        item['work_order_rc_sub_box_no']?.toString() ??
                        item['box_no']?.toString() ??
                        '';
        return itemBox.trim() == boxKey;
      }).toList();

      Navigator.pop(context); // Pop loading spinner

      if (boxItems.isEmpty) {
        _showScannerErrorDialog('Box Empty or Not Found', 'Could not find any items in Box "$boxKey" for receipt reference "$ref".');
        return;
      }

      // 5. Group and summarize items
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

      _showScannerPreviewDialog(ref, boxKey, list, boxPcs, boxAmount);

    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Pop loading spinner
      }
      _showScannerErrorDialog('Error Occurred', 'An error occurred while fetching details: $e');
    }
  }

  void _showScannerErrorDialog(String title, String content) {
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

  Widget _buildScannerTableCell(String text, bool isDark, {bool isHeader = false}) {
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

  void _showScannerPreviewDialog(String ref, String boxKey, List<dynamic> items, int totalPcs, double totalAmount) {
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
                      colors: AppTheme.gradientColors,
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
                              'Box $boxKey Preview',
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
                            _buildScannerTableCell('Barcode', isDark, isHeader: true),
                            _buildScannerTableCell('Size', isDark, isHeader: true),
                            _buildScannerTableCell('Amount (₹)', isDark, isHeader: true),
                            _buildScannerTableCell('Quantity', isDark, isHeader: true),
                          ],
                        ),
                        ...items.map((row) {
                          final barcode = row['barcode'] as String;
                          final size = row['size'] as String;
                          final amount = row['amount'] as double;
                          final quantity = row['quantity'] as int;

                          return TableRow(
                            children: [
                              _buildScannerTableCell(barcode, isDark),
                              _buildScannerTableCell(size, isDark),
                              _buildScannerTableCell(amount.toStringAsFixed(2), isDark),
                              _buildScannerTableCell(quantity.toString(), isDark),
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

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final appBarTitle = widget.singleScan ? 'Scan Barcode' : 'Continuous Scan';

    Widget cameraViewport = Stack(
      children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              final barcode = barcodes.first;
              if (barcode.rawValue != null) {
                final val = barcode.rawValue!;
                if (widget.singleScan) {
                  if (!_hasPopped) {
                    _hasPopped = true;
                    _onBarcodeDetected(val);
                  }
                } else {
                  setState(() {
                    _latestDetectedBarcode = val;
                  });
                }
              }
            }
          },
        ),
        // Scanner viewfinder guide overlay
        Center(
          child: Container(
            width: 260,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(
                color: (!widget.singleScan && _latestDetectedBarcode != null) ? Colors.green : primaryColor,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(16),
              color: Colors.transparent,
            ),
          ),
        ),
        // Capture Barcode Button and Status Banner
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Visual feedback status banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.singleScan
                        ? 'Align barcode in box'
                        : _latestDetectedBarcode != null
                            ? 'Ready: $_latestDetectedBarcode'
                            : 'Align barcode in box',
                    style: TextStyle(
                      color: (!widget.singleScan && _latestDetectedBarcode != null) ? Colors.green.shade400 : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!widget.singleScan) ...[
                  const SizedBox(height: 12),
                  // Shutter button for capture
                  GestureDetector(
                    onTap: _captureBarcode,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.9),
                        border: Border.all(
                          color: _latestDetectedBarcode != null ? Colors.green : Colors.grey.shade400,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_latestDetectedBarcode != null ? Colors.green : Colors.black).withValues(alpha: 0.2),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.qr_code_scanner,
                          color: _latestDetectedBarcode != null ? Colors.green.shade700 : Colors.grey.shade600,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(appBarTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            onPressed: () {
              controller.toggleTorch();
              setState(() {
                _isTorchOn = !_isTorchOn;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera, color: Colors.white),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: widget.singleScan
          ? cameraViewport
          : Column(
              children: [
                Expanded(
                  flex: 5,
                  child: cameraViewport,
                ),
                // 2. Scanned items list and action panel
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Panel Header
                        Padding(
                          padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Scanned Barcodes (${_scannedBarcodes.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                              ),
                              if (_scannedBarcodes.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _scannedBarcodes.clear();
                                    });
                                  },
                                  child: Text(
                                    'Clear All',
                                    style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // Scanned Chips View
                        Expanded(
                          child: _scannedBarcodes.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.qr_code_scanner, color: Colors.grey.shade300, size: 40),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Aim at a barcode, then tap the Scan button',
                                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: _scannedBarcodes.length,
                                  itemBuilder: (context, index) {
                                    final barcode = _scannedBarcodes[index];
                                    return Card(
                                      elevation: 0,
                                      color: Colors.grey.shade50,
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: Colors.grey.shade100),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Icon(Icons.inventory, size: 16, color: primaryColor.withValues(alpha: 0.8)),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          // Show resolved label if available, else raw barcode
                                                          _barcodeDisplayLabels[barcode] ?? barcode,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                                                        ),
                                                        // Show raw barcode below as secondary info when label resolved
                                                        if (_barcodeDisplayLabels.containsKey(barcode))
                                                          Text(
                                                            barcode,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.visibility, color: Colors.blueAccent, size: 20),
                                                  onPressed: () => _fetchAndShowBarcodeDetails(barcode),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 20),
                                                  onPressed: () {
                                                    setState(() {
                                                      _scannedBarcodes.removeAt(index);
                                                    });
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),

                        // Confirm button
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: ElevatedButton(
                            onPressed: _scannedBarcodes.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(context, _scannedBarcodes);
                                  },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: Text(
                              'Add Scanned Barcodes (${_scannedBarcodes.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
