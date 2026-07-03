import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

class AddPackingSlipPage extends StatefulWidget {
  final int workOrderId;
  final String workOrderRef;
  final String brand;
  final int workOrderNo;

  const AddPackingSlipPage({
    super.key,
    required this.workOrderId,
    required this.workOrderRef,
    required this.brand,
    required this.workOrderNo,
  });

  @override
  State<AddPackingSlipPage> createState() => _AddPackingSlipPageState();
}

class _AddPackingSlipPageState extends State<AddPackingSlipPage> {
  // Step management
  int currentStep = 0;
  
  // Form controllers
  final TextEditingController _dcNoController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _factoryNoController = TextEditingController();
  final TextEditingController _fabricReceivedByController = TextEditingController();
  final TextEditingController _fabricLeftOverController = TextEditingController();
  
  // Barcode entries - New structure
  List<Map<String, dynamic>> boxes = [];
  int totalBoxes = 0;
  int totalPieces = 0;
  
  bool isLoading = false;
  bool isSaving = false;
  String brandName = '';
  String _fabricReceived = 'Yes';
  
  // Work order items and barcode lookup
  List<Map<String, dynamic>> workOrderItems = [];
  Map<String, List<Map<String, dynamic>>> barcodeLookup = {};
  
  // API endpoints
  final String brandApi = 'https://houseofonzone.com/admin/public/api/fetch-work-order-brand';
  final String dcNoApi = 'https://houseofonzone.com/admin/public/api/fetch-work-order-received-dcno';
  final String workOrderDetailsApi = 'https://houseofonzone.com/admin/public/api/fetch-work-order-received-view-by-id';
  final String saveApi = 'https://houseofonzone.com/admin/public/api/create-work-order-received';
  final String fetchApi = 'https://houseofonzone.com/admin/public/api/fetch-work-order-finish-check';

  // Scanner state
  bool isScannerOpen = false;
  int? scanningBoxIndex;
  int? scanningBarcodeIndex;
int? workOrderRcId;
  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _dcNoController.dispose();
    _dateController.dispose();
    _remarksController.dispose();
    _yearController.dispose();
    _factoryNoController.dispose();
    _fabricReceivedByController.dispose();
    _fabricLeftOverController.dispose();
    super.dispose();
  }

  // ==================== NEW: Fetch work order details ====================
// ==================== FIXED: Fetch work order details ====================
Future<void> _fetchWorkOrderDetails() async {
  try {
    print("========== FETCH WORK ORDER DETAILS START ==========");

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    print("Token exists: ${token.isNotEmpty}");

    // Use workOrderId (822) not workOrderNo
    final url = '$workOrderDetailsApi/${widget.workOrderId}';
    print("URL: $url");

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );

    print("Status Code: ${response.statusCode}");
    print("Response Body: ${response.body}");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      print("Data keys: ${data.keys}");
      print("workorderrcsub exists: ${data.containsKey('workorderrcsub')}");
      
      if (data.containsKey('workorderrcsub')) {
        final items = data['workorderrcsub'] as List? ?? [];
        print("Number of items: ${items.length}");
        
        // Clear existing data
        workOrderItems.clear();
        barcodeLookup.clear();
        
        for (final item in items) {
          final barcode = item['work_order_rc_sub_barcode']?.toString() ?? '';
          if (barcode.isNotEmpty) {
            workOrderItems.add(Map<String, dynamic>.from(item));
            
            // Build lookup: barcode -> list of records
            barcodeLookup.putIfAbsent(barcode, () => []);
            barcodeLookup[barcode]!.add(Map<String, dynamic>.from(item));
          }
        }
        
        print("Total unique barcodes: ${barcodeLookup.keys.length}");
        print("Barcodes: ${barcodeLookup.keys.join(', ')}");
        
        // Group items by box
        _groupItemsByBox();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Loaded ${items.length} barcodes from work order'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print("No workorderrcsub found in response");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No barcodes found in work order'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else {
      print("API Error: ${response.statusCode}");
      print("Error Body: ${response.body}");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load work order: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  } catch (e, s) {
    print("ERROR in _fetchWorkOrderDetails: $e");
    print(s);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading work order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
  // ==================== NEW: Group items by box ====================
  // ==================== FIXED: Group items by box ====================
void _groupItemsByBox() {
  print("========== GROUPING ITEMS BY BOX ==========");
  print("Total workOrderItems: ${workOrderItems.length}");
  
  Map<int, List<Map<String, dynamic>>> boxMap = {};
  
  for (final item in workOrderItems) {
    // Get box number - handle both String and int
    final boxValue = item['work_order_rc_sub_box'];
    int boxNumber = 0;
    
    if (boxValue is String) {
      boxNumber = int.tryParse(boxValue) ?? 0;
    } else if (boxValue is int) {
      boxNumber = boxValue;
    } else {
      boxNumber = int.tryParse(boxValue?.toString() ?? '0') ?? 0;
    }
    
    print("Item barcode: ${item['work_order_rc_sub_barcode']}, Box: $boxNumber");
    
    if (boxNumber > 0) {
      boxMap.putIfAbsent(boxNumber, () => []);
      boxMap[boxNumber]!.add(item);
    }
  }
  
  print("Found ${boxMap.keys.length} boxes: ${boxMap.keys.toList()}");
  
  // Sort box numbers
  final sortedBoxNumbers = boxMap.keys.toList()..sort();
  
  boxes.clear();
  
  for (final boxNumber in sortedBoxNumbers) {
    final items = boxMap[boxNumber]!;
    print("Box $boxNumber has ${items.length} items");
    
    // Create barcode entries for this box
    List<Map<String, dynamic>> barcodeEntries = [];
    int boxPieces = 0;
    
    for (final item in items) {
      final barcode = item['work_order_rc_sub_barcode']?.toString() ?? '';
      final pcs = int.tryParse(item['work_order_rc_sub_pcs']?.toString() ?? '1') ?? 1;
      
      print("  Barcode: $barcode, PCS: $pcs");
      
      // Check if this barcode has been scanned (received)
      final isScanned = item['is_received'] == true || 
                        item['work_order_rc_sub_is_received'] == true ||
                        item['received'] == true;
      
      // Check if it's a duplicate count
      final isDuplicate = item['is_duplicate'] == true || 
                         item['work_order_rc_sub_is_duplicate'] == true;
      
      barcodeEntries.add({
        'id': barcodeEntries.length + 1,
        'code': barcode,
        'pieces': pcs,
        'isScanned': isScanned,
        'isDuplicate': isDuplicate,
        'barcodeData': item,
        'itemId': item['id'] ?? item['work_order_rc_sub_id'],
      });
      
      if (isScanned && !isDuplicate) {
        boxPieces += pcs;
      }
    }
    
    boxes.add({
      'id': boxNumber,
      'boxNumber': boxNumber,
      'pieces': boxPieces,
      'barcodes': barcodeEntries,
      'isExpanded': true,
    });
  }
  
  // If no boxes found, create a default one
  if (boxes.isEmpty) {
    print("No boxes found, creating default box");
    boxes.add({
      'id': 1,
      'boxNumber': 1,
      'pieces': 0,
      'barcodes': [],
      'isExpanded': true,
    });
  }
  
  totalBoxes = boxes.length;
  _updateTotalPieces();
  
  print("Total boxes: $totalBoxes");
  print("Total pieces: $totalPieces");
  print("=====================================");
}
Future<bool> validateBarcodeFromServer(String barcode) async {
  try {
   final url = Uri.parse(
  '$fetchApi/${widget.workOrderNo}/$barcode',
);

print(url.toString());

   final prefs = await SharedPreferences.getInstance();
final token = prefs.getString('token') ?? '';

final response = await http.get(
  url,
  headers: {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  },
);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      print("Finish Check Response: $data");

      // Change this according to your API response
      if (data['code'] == 200 &&
    data['msg'].toString().toLowerCase() == 'barcode found') {
  return true;
} else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Barcode not found'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server Error'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  } catch (e) {
    print(e);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red,
      ),
    );

    return false;
  }
}
  // ==================== NEW: Initialize data ====================
  Future<void> _initializeData() async {
    setState(() {
      isLoading = true;
    });

    // Set today's date
    final now = DateTime.now();
    final formattedDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _dateController.text = formattedDate;
    _yearController.text = '${now.year}-${(now.year + 1).toString().substring(2)}';

    // Set brand name
    brandName = widget.brand;

    // Fetch brand details
    await _fetchBrandDetails();

    // Fetch DC number
    await _fetchDCNumber();

    // Fetch work order details and build barcodes
    await _fetchWorkOrderDetails();

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _fetchBrandDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final url = '$brandApi/${widget.workOrderId}';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['brand'] != null) {
          setState(() {
            brandName = data['brand'] ?? widget.brand;
          });
        }
      }
    } catch (e) {
      print('Error fetching brand: $e');
      brandName = widget.brand;
    }
  }

  Future<void> _fetchDCNumber() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.get(
        Uri.parse(dcNoApi),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dcNo = data['work_order_rc_dc_no'] ?? data['dc_no'];
        if (dcNo != null) {
          setState(() {
            _dcNoController.text = dcNo.toString();
          });
        } else {
          _generateDefaultDCNo();
        }
      } else {
        _generateDefaultDCNo();
      }
    } catch (e) {
      print('Error fetching DC number: $e');
      _generateDefaultDCNo();
    }
  }

  void _generateDefaultDCNo() {
    final now = DateTime.now();
    _dcNoController.text = 'DC-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${widget.workOrderId}';
  }

  // ==================== UPDATED: Add box ====================
  void _addBox() {
    setState(() {
      final newBoxId = boxes.length + 1;
      boxes.add({
        'id': newBoxId,
        'boxNumber': newBoxId,
        'pieces': 0,
        'barcodes': [],
        'isExpanded': true,
      });
      totalBoxes = boxes.length;
      _updateTotalPieces();
    });
  }

  void _removeBox(int index) {
    setState(() {
      boxes.removeAt(index);
      for (int i = 0; i < boxes.length; i++) {
        boxes[i]['id'] = i + 1;
        boxes[i]['boxNumber'] = i + 1;
      }
      totalBoxes = boxes.length;
      _updateTotalPieces();
    });
  }

  // ==================== UPDATED: Add barcode entry ====================
  void _addBarcode(int boxIndex) {
    setState(() {
      boxes[boxIndex]['barcodes'].add({
        'id': boxes[boxIndex]['barcodes'].length + 1,
        'code': '',
        'pieces': 0,
        'isScanned': false,
        'isDuplicate': false,
        'barcodeData': null,
        'itemId': null,
      });
      _updateTotalPieces();
    });
  }

  void _removeBarcode(int boxIndex, int barcodeIndex) {
    setState(() {
      boxes[boxIndex]['barcodes'].removeAt(barcodeIndex);
      for (int i = 0; i < boxes[boxIndex]['barcodes'].length; i++) {
        boxes[boxIndex]['barcodes'][i]['id'] = i + 1;
      }
      _updateTotalPieces();
    });
  }

  void _updateTotalPieces() {
    int total = 0;
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        if (barcode['isScanned'] == true && barcode['isDuplicate'] != true) {
          total += int.tryParse(barcode['pieces'].toString()) ?? 0;
        }
      }
    }
    setState(() {
      totalPieces = total;
    });
  }

  void _updateBoxPieces(int boxIndex) {
    int total = 0;
    for (var barcode in boxes[boxIndex]['barcodes']) {
      if (barcode['isScanned'] == true && barcode['isDuplicate'] != true) {
        total += int.tryParse(barcode['pieces'].toString()) ?? 0;
      }
    }
    setState(() {
      boxes[boxIndex]['pieces'] = total;
      _updateTotalPieces();
    });
  }

  // ==================== NEW: Validate barcode (simplified) ====================
  Future<void> _validateBarcode(int boxIndex, int barcodeIndex, String barcode) async {
    if (barcode.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a barcode'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final trimmedBarcode = barcode.trim();

    // Check if barcode exists in lookup
   bool isValid = await validateBarcodeFromServer(trimmedBarcode);

if (!isValid) {
  return;
}

    print("STEP 1");

final items = barcodeLookup[trimmedBarcode];
print("STEP 2");

if (items == null) {
  print("items is null");
  return;
}

print("STEP 3");

Map<String, dynamic>? unreceivedItem;

for (final item in items) {
  print(item);
  unreceivedItem = item;
  break;
}

print("STEP 4");

print(unreceivedItem);

final pcs = int.tryParse(
    unreceivedItem?['work_order_rc_sub_pcs']?.toString() ?? '1') ?? 1;

print("STEP 5");
    
    // Find first unreceived record for this barcode
    
    if (unreceivedItem != null) {
      // Mark this barcode as scanned
      final pcs = int.tryParse(unreceivedItem['work_order_rc_sub_pcs']?.toString() ?? '0') ?? 0;
      
      setState(() {
        boxes[boxIndex]['barcodes'][barcodeIndex]['isScanned'] = true;
        boxes[boxIndex]['barcodes'][barcodeIndex]['isDuplicate'] = false;
        boxes[boxIndex]['barcodes'][barcodeIndex]['barcodeData'] = unreceivedItem;
        boxes[boxIndex]['barcodes'][barcodeIndex]['pieces'] = pcs;
        boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = trimmedBarcode;
        boxes[boxIndex]['barcodes'][barcodeIndex]['itemId'] = unreceivedItem?['id'] ?? unreceivedItem?['work_order_rc_sub_id'];
        
        // Mark item as received in lookup
        unreceivedItem!['is_received'] = true;
        unreceivedItem['work_order_rc_sub_is_received'] = true;
        
        _updateBoxPieces(boxIndex);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barcode scanned! Pieces: $pcs'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      // All records for this barcode are already scanned - treat as duplicate
      setState(() {
        boxes[boxIndex]['barcodes'][barcodeIndex]['isScanned'] = true;
        boxes[boxIndex]['barcodes'][barcodeIndex]['isDuplicate'] = true;
        boxes[boxIndex]['barcodes'][barcodeIndex]['barcodeData'] = items.first;
        boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = trimmedBarcode;
        // Keep existing pieces or set to 1
        if (int.tryParse(boxes[boxIndex]['barcodes'][barcodeIndex]['pieces'].toString() ?? '0') == 0) {
          boxes[boxIndex]['barcodes'][barcodeIndex]['pieces'] = 1;
        }
        _updateBoxPieces(boxIndex);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Duplicate barcode - Count: ${_getDuplicateCount(trimmedBarcode)}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ==================== NEW: Get duplicate count ====================
  int _getDuplicateCount(String barcode) {
    int count = 0;
    for (var box in boxes) {
      for (var b in box['barcodes']) {
        if (b['code'] == barcode && b['isDuplicate'] == true) {
          count++;
        }
      }
    }
    return count + 1; // +1 for the current one
  }

  // ==================== UPDATED: Open scanner ====================
  Future<void> _openScanner(int boxIndex, int barcodeIndex) async {
    setState(() {
      scanningBoxIndex = boxIndex;
      scanningBarcodeIndex = barcodeIndex;
      isScannerOpen = true;
    });

    try {
      final barcode = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => BarcodeScannerPage(
            onScanned: (code) {
              Navigator.pop(context, code);
            },
          ),
        ),
      );

      if (barcode != null && barcode.isNotEmpty) {
        setState(() {
          boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = barcode;
        });
        await _validateBarcode(boxIndex, barcodeIndex, barcode);
      }
    } catch (e) {
      print('Scanner error: $e');
    } finally {
      setState(() {
        isScannerOpen = false;
        scanningBoxIndex = null;
        scanningBarcodeIndex = null;
      });
    }
  }

  // ==================== UPDATED: Manual barcode entry ====================
  void _handleManualBarcodeEntry(int boxIndex, int barcodeIndex, String value) {
    setState(() {
      boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = value;
      // Reset scan state when user manually changes
      boxes[boxIndex]['barcodes'][barcodeIndex]['isScanned'] = false;
      boxes[boxIndex]['barcodes'][barcodeIndex]['isDuplicate'] = false;
      boxes[boxIndex]['barcodes'][barcodeIndex]['barcodeData'] = null;
      _updateBoxPieces(boxIndex);
    });
  }

  // ==================== UPDATED: Save packing slip ====================
  Future<void> _savePackingSlip() async {
    // Check if there are any scanned barcodes
    bool hasScannedBarcodes = false;
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        if (barcode['isScanned'] == true) {
          hasScannedBarcodes = true;
          break;
        }
      }
      if (hasScannedBarcodes) break;
    }

    if (!hasScannedBarcodes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please scan at least one barcode'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    // Prepare workorder_sub_rc_data - only scanned barcodes
    List<Map<String, dynamic>> subData = [];
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        if (barcode['isScanned'] == true) {
          subData.add({
            'work_order_rc_sub_barcode': barcode['code'].toString().trim(),
            'work_order_rc_sub_box': box['id'],
            'work_order_rc_sub_pcs': int.tryParse(barcode['pieces'].toString()) ?? 0,
            'work_order_rc_sub_is_received': true,
            'work_order_rc_sub_is_duplicate': barcode['isDuplicate'] == true,
          });
        }
      }
    }

    // Prepare full data
    final slipData = {
      'work_order_rc_year': _yearController.text.trim(),
      'work_order_rc_date': _dateController.text.trim(),
      'work_order_rc_factory_no': _factoryNoController.text.trim().isEmpty ? '1' : _factoryNoController.text.trim(),
      'work_order_rc_id': widget.workOrderId,
      'work_order_no': widget.workOrderNo,
      'work_order_rc_dc_no': _dcNoController.text.trim(),
      'work_order_rc_dc_date': _dateController.text.trim(),
      'work_order_rc_brand': brandName,
      'work_order_rc_box': totalBoxes.toString(),
      'work_order_rc_pcs': totalPieces.toString(),
      'work_order_rc_received_by': _fabricReceivedByController.text.trim(),
      'work_order_rc_fabric_received': _fabricReceived,
      'work_order_rc_fabric_count': _fabricLeftOverController.text.trim(),
      'work_order_rc_remarks': _remarksController.text.trim(),
      'work_order_rc_count': totalBoxes,
      'workorder_sub_rc_data': subData,
    };

    print('Saving Packaging Slip: ${jsonEncode(slipData)}');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.post(
        Uri.parse(saveApi),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(slipData),
      );

      print('Save Response Status: ${response.statusCode}');
      print('Save Response Body: ${response.body}');

      setState(() {
        isSaving = false;
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Packing Slip created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        String errorMsg = 'Failed to create packing slip.';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['message'] != null) {
            errorMsg = errorData['message'];
          }
        } catch (e) {
          // Ignore parsing error
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$errorMsg (Status: ${response.statusCode})'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        isSaving = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error saving packing slip: $e');
    }
  }

  // ==================== BUILD METHODS ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentStep == 0 ? 'Add New Packing Slip – Details' : 'Add New Packing Slip – Barcodes',
          style: const TextStyle(fontSize: 18),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (currentStep == 0) {
              Navigator.pop(context);
            } else {
              setState(() {
                currentStep = 0;
              });
            }
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _buildStepIndicator(0, 'Details'),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: currentStep >= 1 ? Colors.white : Colors.white.withOpacity(0.3),
                        ),
                      ),
                      _buildStepIndicator(1, 'Barcodes'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: isLoading || isSaving
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.deepPurple,
                    ),
                  ),
                ],
              ),
            )
          : currentStep == 0
              ? _buildDetailsStep()
              : _buildBarcodesStep(),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 2,
              blurRadius: 8,
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: () {
                  if (currentStep == 0) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      currentStep = 0;
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  foregroundColor: Colors.grey[800],
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(currentStep == 0 ? 'Back' : '← Back'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (currentStep == 0) {
                    if (_dcNoController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter DC Number'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    setState(() {
                      currentStep = 1;
                    });
                  } else {
                    _savePackingSlip();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(currentStep == 0 ? 'Next →' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = currentStep >= step;
    final isCompleted = currentStep > step;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isActive ? Colors.deepPurple : Colors.white.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Work Order Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.deepPurple.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Work Order',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          widget.workOrderRef,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'WO #${widget.workOrderNo}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Brand: ',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(
                      brandName.isNotEmpty ? brandName : 'Loading...',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Year
          TextField(
            controller: _yearController,
            decoration: InputDecoration(
              labelText: 'Year *',
              hintText: 'e.g., 2023-24',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              labelStyle: const TextStyle(color: Colors.deepPurple),
            ),
          ),
          const SizedBox(height: 16),

          // Date
          TextField(
            controller: _dateController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Date *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              labelStyle: const TextStyle(color: Colors.deepPurple),
              suffixIcon: const Icon(Icons.calendar_today, color: Colors.deepPurple),
            ),
          ),
          const SizedBox(height: 16),

          // DC No
          TextField(
            controller: _dcNoController,
            decoration: InputDecoration(
              labelText: 'DC No *',
              hintText: 'Enter DC number',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              labelStyle: const TextStyle(color: Colors.deepPurple),
            ),
          ),
          const SizedBox(height: 16),

          // Factory No
          TextField(
            controller: _factoryNoController,
            decoration: InputDecoration(
              labelText: 'Factory No',
              hintText: 'Enter factory number (default: 1)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              labelStyle: const TextStyle(color: Colors.deepPurple),
            ),
          ),
          const SizedBox(height: 16),

          // Fabric Received
          DropdownButtonFormField<String>(
            value: _fabricReceived,
            decoration: InputDecoration(
              labelText: 'Fabric Received *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              labelStyle: const TextStyle(color: Colors.deepPurple),
            ),
            items: const [
              DropdownMenuItem(value: 'Yes', child: Text('Yes')),
              DropdownMenuItem(value: 'No', child: Text('No')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _fabricReceived = value;
                });
              }
            },
          ),
          const SizedBox(height: 16),

          // Fabric Received By
          TextField(
            controller: _fabricReceivedByController,
            decoration: InputDecoration(
              labelText: 'Fabric Received By',
              hintText: 'Enter person name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              labelStyle: const TextStyle(color: Colors.deepPurple),
            ),
          ),
          const SizedBox(height: 16),

          // Fabric Left Over
          TextField(
            controller: _fabricLeftOverController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Fabric Left Over (yards)',
              hintText: 'Enter fabric left over',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              labelStyle: const TextStyle(color: Colors.deepPurple),
            ),
          ),
          const SizedBox(height: 16),

          // Remarks
          TextField(
            controller: _remarksController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Remarks',
              hintText: 'Enter remarks (optional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              labelStyle: const TextStyle(color: Colors.deepPurple),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Info Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Please fill all required fields (*) before proceeding to barcode entry.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodesStep() {
    return Column(
      children: [
        // Header info
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[50],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Barcode Entries (Total Box: $totalBoxes, Total Pieces: $totalPieces)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'WO #${widget.workOrderNo}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepPurple.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: boxes.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 60,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No boxes available',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        'Work order has no barcodes',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: boxes.length,
                  itemBuilder: (context, index) {
                    final box = boxes[index];
                    return _buildBoxCard(index, box);
                  },
                ),
        ),
        // Add Box Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _addBox,
            icon: const Icon(Icons.add),
            label: const Text('Add Box'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBoxCard(int boxIndex, Map<String, dynamic> box) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: Colors.deepPurple,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${box['id']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Box ${box['id']} - ${box['pieces']} pieces',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                if (boxes.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _removeBox(boxIndex),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Barcodes
            if (box['barcodes'].isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: const Center(
                  child: Text(
                    'No barcodes added yet',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ...List.generate(box['barcodes'].length, (barcodeIndex) {
                final barcode = box['barcodes'][barcodeIndex];
                return _buildBarcodeEntry(boxIndex, barcodeIndex, barcode);
              }),
            
            // Add Barcode Button
            TextButton(
              onPressed: () => _addBarcode(boxIndex),
              style: TextButton.styleFrom(
                foregroundColor: Colors.deepPurple,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16),
                  SizedBox(width: 4),
                  Text('Add Barcode'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodeEntry(int boxIndex, int barcodeIndex, Map<String, dynamic> barcode) {
    final isScanned = barcode['isScanned'] ?? false;
    final isDuplicate = barcode['isDuplicate'] ?? false;
    final hasCode = barcode['code']?.toString().isNotEmpty ?? false;

    // Determine status color
    Color statusColor;
    String statusText;
    if (isDuplicate) {
      statusColor = Colors.orange.shade300;
      statusText = 'Duplicate';
    } else if (isScanned && hasCode) {
      statusColor = Colors.green.shade300;
      statusText = '✓ Scanned';
    } else if (hasCode) {
      statusColor = Colors.grey.shade300;
      statusText = 'Pending';
    } else {
      statusColor = Colors.grey.shade200;
      statusText = 'Empty';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isScanned ? (isDuplicate ? Colors.orange.shade50 : Colors.green.shade50) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isScanned ? (isDuplicate ? Colors.orange.shade300 : Colors.green.shade300) : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: isDuplicate ? Colors.orange : (isScanned ? Colors.green : Colors.grey),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'BARCODE',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: barcode['code']?.toString() ?? '',
                        decoration: const InputDecoration(
                          hintText: 'Enter barcode',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (value) => _handleManualBarcodeEntry(boxIndex, barcodeIndex, value),
                        readOnly: isScanned && hasCode,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner, size: 20, color: Colors.deepPurple),
                      onPressed: (isScanned && hasCode) ? null : () => _openScanner(boxIndex, barcodeIndex),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PIECES',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextFormField(
                  initialValue: barcode['pieces']?.toString() ?? '0',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      barcode['pieces'] = value;
                      _updateBoxPieces(boxIndex);
                    });
                  },
                  readOnly: isScanned && hasCode,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.check,
              size: 20,
              color: isScanned ? (isDuplicate ? Colors.orange.shade700 : Colors.green.shade700) : Colors.grey,
            ),
            onPressed: () {
              if (barcode['code']?.toString().isNotEmpty ?? false) {
                _validateBarcode(boxIndex, barcodeIndex, barcode['code'].toString());
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            onPressed: () => _removeBarcode(boxIndex, barcodeIndex),
          ),
        ],
      ),
    );
  }
}

// ==================== BARCODE SCANNER PAGE ====================
class BarcodeScannerPage extends StatefulWidget {
  final Function(String) onScanned;

  const BarcodeScannerPage({
    super.key,
    required this.onScanned,
  });

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () {
              _controller.switchCamera();
            },
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, child) {
                return Icon(
                  value.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_isProcessing) return;
              
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final code = barcode.rawValue;
                if (code != null && code.isNotEmpty) {
                  _isProcessing = true;
                  _controller.stop();
                  widget.onScanned(code);
                  break;
                }
              }
            },
          ),
          // Scanning overlay guide
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  // Corner indicators
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.white, width: 4),
                          left: BorderSide(color: Colors.white, width: 4),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.white, width: 4),
                          right: BorderSide(color: Colors.white, width: 4),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white, width: 4),
                          left: BorderSide(color: Colors.white, width: 4),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white, width: 4),
                          right: BorderSide(color: Colors.white, width: 4),
                        ),
                      ),
                    ),
                  ),
                  // Center line
                  Center(
                    child: Container(
                      width: 200,
                      height: 2,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom info
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'Position the barcode within the frame',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    _controller.stop();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepPurple,
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}