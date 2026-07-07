import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'app_theme.dart';
import 'api.dart';
import 'package:http/http.dart' as http;

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
  int currentStep = 1;
  
  // Form controllers
  final TextEditingController _dcNoController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _factoryNoController = TextEditingController();
  final TextEditingController _fabricReceivedByController = TextEditingController();
  final TextEditingController _fabricLeftOverController = TextEditingController();
  
  // Barcode entries
  List<Map<String, dynamic>> boxes = [];
  int totalBoxes = 0;
  int totalPieces = 0;
  int totalBarcodeEntries = 0; // Track total barcode entries for work_order_rc_count
  
  bool isLoading = false;
  bool isSaving = false;
  String brandName = '';
  String _fabricReceived = 'Yes';

  // API endpoints
  final String brandApi = '$baseUrl/fetch-work-order-brand';
  final String dcNoApi = '$baseUrl/fetch-work-order-received-dcno';
  final String barcodeCheckApi = '$baseUrl/fetch-work-order-finish-check';
  final String saveApi = '$baseUrl/create-work-order-received';

  // Scanner state
  bool isScannerOpen = false;
  int? scanningBoxIndex;
  int? scanningBarcodeIndex;

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
    
    // Dispose all barcode controllers
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        if (barcode['controller'] != null) {
          (barcode['controller'] as TextEditingController).dispose();
        }
      }
    }
    super.dispose();
  }

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

    // Add initial box
    _addBox();

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
    _dcNoController.text = 'DC-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}–${widget.workOrderId}';
  }

  void _addBox() {
    setState(() {
      boxes.add({
        'id': boxes.length + 1,
        'pieces': 0,
        'barcodes': [],
        'isExpanded': true,
        'boxNumber': boxes.length + 1,
      });
      totalBoxes = boxes.length;
      _updateTotals();
    });
  }
void _removeMergedBarcode(int boxIndex, String barcodeCode) {
  final barcodes = boxes[boxIndex]['barcodes'];

  // Find the last occurrence of this barcode
  for (int i = barcodes.length - 1; i >= 0; i--) {
    if (barcodes[i]['code'] == barcodeCode) {
      if (barcodes[i]['controller'] != null) {
        (barcodes[i]['controller'] as TextEditingController).dispose();
      }

      barcodes.removeAt(i);
      totalBarcodeEntries--;

      // Re-number ids
      for (int j = 0; j < barcodes.length; j++) {
        barcodes[j]['id'] = j + 1;
      }

      _updateBoxPieces(boxIndex);

      setState(() {});
      return;
    }
  }
}
  void _removeBox(int index) {
    setState(() {
      final box = boxes[index];
      // Remove all barcodes in this box
      for (var barcode in box['barcodes']) {
        if (barcode['controller'] != null) {
          (barcode['controller'] as TextEditingController).dispose();
        }
        totalBarcodeEntries--;
      }
      boxes.removeAt(index);
      for (int i = 0; i < boxes.length; i++) {
        boxes[i]['id'] = i + 1;
        boxes[i]['boxNumber'] = i + 1;
      }
      totalBoxes = boxes.length;
      _updateTotals();
    });
  }
void _addBarcodeRow(int boxIndex) {
  final controller = TextEditingController();

  setState(() {
    boxes[boxIndex]['barcodes'].add({
      'id': boxes[boxIndex]['barcodes'].length + 1,
      'code': '',
      'pieces': 0,
      'isValidated': false,
      'isLoading': false,
      'barcodeData': null,
      'controller': controller,
    });

    totalBarcodeEntries++;
    _updateTotals();
  });
}
void _addBarcode(int boxIndex) {
  _addBarcodeRow(boxIndex);

  _openScanner(
    boxIndex,
    boxes[boxIndex]['barcodes'].length - 1,
  );
}
  void _removeBarcode(int boxIndex, int barcodeIndex) {
    setState(() {
      final barcode = boxes[boxIndex]['barcodes'][barcodeIndex];
      if (barcode['controller'] != null) {
        (barcode['controller'] as TextEditingController).dispose();
      }
      boxes[boxIndex]['barcodes'].removeAt(barcodeIndex);
      totalBarcodeEntries--;

      for (int i = 0; i < boxes[boxIndex]['barcodes'].length; i++) {
        boxes[boxIndex]['barcodes'][i]['id'] = i + 1;
      }
      _updateBoxPieces(boxIndex);
    });
  }

  void _updateTotals() {
    int total = 0;
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        total += int.tryParse(barcode['pieces'].toString()) ?? 0;
      }
    }
    setState(() {
      totalPieces = total;
    });
  }

  void _updateTotalPieces() {
    int total = 0;
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        total += int.tryParse(barcode['pieces'].toString()) ?? 0;
      }
    }
    setState(() {
      totalPieces = total;
    });
  }

  void _updateBoxPieces(int boxIndex) {
    int total = 0;
    for (var barcode in boxes[boxIndex]['barcodes']) {
      total += int.tryParse(barcode['pieces'].toString()) ?? 0;
    }
    setState(() {
      boxes[boxIndex]['pieces'] = total;
      _updateTotalPieces();
    });
  }

  // Validate barcode against API
  Future<void> _validateBarcode(
    int boxIndex,
    int barcodeIndex,
    String barcode,
  ) async {
    final trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter barcode"),
        ),
      );
      return;
    }

    setState(() {
      boxes[boxIndex]['barcodes'][barcodeIndex]['isLoading'] = true;
    });
    print("VALIDATING = $trimmedBarcode");
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      // API Check: /fetch-work-order-finish-check/{work_order_no}/{barcode}
      final url = '$barcodeCheckApi/${widget.workOrderNo}/$trimmedBarcode';
      print('Validating barcode at URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Barcode Check Response Status: ${response.statusCode}');
      print('Barcode Check Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool isFound = data['code'] == 200;

        if (!isFound) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['msg'] ?? "Barcode not in Work Order"),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() {
            boxes[boxIndex]['barcodes'][barcodeIndex]['isLoading'] = false;
            boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = false;
          });
          return;
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Validation failed (Status: ${response.statusCode})"),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          boxes[boxIndex]['barcodes'][barcodeIndex]['isLoading'] = false;
          boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = false;
        });
        return;
      }
    } catch (e) {
      print('Error validating barcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error validating barcode: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        boxes[boxIndex]['barcodes'][barcodeIndex]['isLoading'] = false;
        boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = false;
      });
      return;
    }

    setState(() {
      boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = trimmedBarcode;
      boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = true;
      boxes[boxIndex]['barcodes'][barcodeIndex]['isLoading'] = false;
      boxes[boxIndex]['barcodes'][barcodeIndex]['pieces'] = 1;

      _updateBoxPieces(boxIndex);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Barcode Added"),
        backgroundColor: Colors.green,
      ),
    );
  }

  // Open scanner
  Future<void> _openScanner(int boxIndex, int barcodeIndex) async {
    setState(() {
      scanningBoxIndex = boxIndex;
      scanningBarcodeIndex = barcodeIndex;
      isScannerOpen = true;
    });

    try {
      final List<String>? barcodes = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (context) => BarcodeScannerPage(
            onDone: (scanned) {},
          ),
        ),
      );

      if (barcodes != null && barcodes.isNotEmpty) {
        final currentCode = boxes[boxIndex]['barcodes'][barcodeIndex]['code']?.toString() ?? '';
        final currentValidated = boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] == true;
        
        int startScanIdx = 0;
        
        if (currentCode.isEmpty && !currentValidated) {
          final firstCode = barcodes.first;
          setState(() {
            boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = firstCode;
            if (boxes[boxIndex]['barcodes'][barcodeIndex]['controller'] != null) {
              (boxes[boxIndex]['barcodes'][barcodeIndex]['controller'] as TextEditingController).text = firstCode;
            }
          });
          await _validateBarcode(boxIndex, barcodeIndex, firstCode);
          startScanIdx = 1;
        }

        for (int i = startScanIdx; i < barcodes.length; i++) {
          final code = barcodes[i];
         _addBarcodeRow(boxIndex);
          int index = boxes[boxIndex]['barcodes'].length - 1;
          
          setState(() {
            boxes[boxIndex]['barcodes'][index]['code'] = code;
            if (boxes[boxIndex]['barcodes'][index]['controller'] != null) {
              (boxes[boxIndex]['barcodes'][index]['controller'] as TextEditingController).text = code;
            }
          });
          await _validateBarcode(boxIndex, index, code);
        }
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

  // Manual barcode entry with validation
  void _handleManualBarcodeEntry(int boxIndex, int barcodeIndex, String value) {
    setState(() {
      boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = value;
      // Reset validation when user manually changes
      if (boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated']) {
        boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = false;
        boxes[boxIndex]['barcodes'][barcodeIndex]['barcodeData'] = null;
      }
    });
  }

  Future<void> _savePackingSlip() async {
    // Check if there are any barcodes
    bool hasBarcodes = false;
    for (var box in boxes) {
      if (box['barcodes'].isNotEmpty) {
        hasBarcodes = true;
        break;
      }
    }

    if (!hasBarcodes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one barcode'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate all barcodes are successfully validated against the API and not empty
    bool allValidated = true;
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        final code = barcode['code'].toString().trim();
        if (code.isEmpty || !barcode['isValidated']) {
          allValidated = false;
          break;
        }
      }
      if (!allValidated) break;
    }

    if (!allValidated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please validate all barcodes (using the Check icon) before saving'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(saveApi),
      );

      request.headers['Authorization'] = 'Bearer $token';

      request.fields['work_order_rc_year'] = _yearController.text.trim();
      request.fields['work_order_rc_date'] = _dateController.text.trim();
      request.fields['work_order_rc_factory_no'] = _factoryNoController.text.trim().isEmpty ? '1' : _factoryNoController.text.trim();
      
      // Essential keys to map backend Work Order relations correctly
      request.fields['work_order_rc_id'] = widget.workOrderId.toString();
      request.fields['work_order_id'] = widget.workOrderId.toString();
      request.fields['work_order_no'] = widget.workOrderNo.toString();
      request.fields['work_order_ref'] = widget.workOrderRef;
      request.fields['work_order_rc_ref'] = widget.workOrderRef;

      request.fields['work_order_rc_dc_no'] = _dcNoController.text.trim();
      request.fields['work_order_rc_dc_date'] = _dateController.text.trim();
      request.fields['work_order_rc_brand'] = brandName;
      request.fields['work_order_rc_box'] = totalBoxes.toString();
      request.fields['work_order_rc_pcs'] = totalPieces.toString();
      
      if (_fabricReceivedByController.text.trim().isNotEmpty) {
        request.fields['work_order_rc_received_by'] = _fabricReceivedByController.text.trim();
      }
      request.fields['work_order_rc_fabric_received'] = _fabricReceived;
      
      if (_fabricLeftOverController.text.trim().isNotEmpty) {
        request.fields['work_order_rc_fabric_count'] = _fabricLeftOverController.text.trim();
      }
      if (_remarksController.text.trim().isNotEmpty) {
        request.fields['work_order_rc_remarks'] = _remarksController.text.trim();
      }
      
      // CRITICAL FIX: work_order_rc_count should be the total number of barcode entries
      request.fields['work_order_rc_count'] = totalBarcodeEntries.toString();

      int subIndex = 0;
      for (var box in boxes) {
        for (var barcode in box['barcodes']) {
          final code = barcode['code'].toString().trim();
          final pieces = int.tryParse(barcode['pieces'].toString()) ?? 0;

          if (code.isNotEmpty && barcode['isValidated'] && pieces > 0) {
            for (int i = 0; i < pieces; i++) {
              request.fields['workorder_sub_rc_data[$subIndex][work_order_rc_sub_box]'] = box['id'].toString();
              request.fields['workorder_sub_rc_data[$subIndex][work_order_rc_sub_barcode]'] = code;
              request.fields['workorder_sub_rc_data[$subIndex][work_order_sub_brand]'] = brandName;
              subIndex++;
            }
          }
        }
      }

      print('Saving Packaging Slip via MultipartRequest fields: ${request.fields}');
      print('Total Barcode Entries (work_order_rc_count): $totalBarcodeEntries');
      print('Total Sub Entries: $subIndex');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTheme.gradientColors,
            ),
          ),
        ),
        title: Text(
          currentStep == 0 ? 'Add New Packing Slip – Details' : 'Add New Packing Slip – Barcodes',
          style: const TextStyle(fontSize: 18, color: Colors.white),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.primaryColor,
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
                  backgroundColor: AppTheme.primaryColor,
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
              color: isActive ? AppTheme.primaryColor : Colors.white.withOpacity(0.3),
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
              color: AppTheme.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
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
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
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
              labelStyle: const TextStyle(color: AppTheme.primaryColor),
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
              labelStyle: const TextStyle(color: AppTheme.primaryColor),
              suffixIcon: const Icon(Icons.calendar_today, color: AppTheme.primaryColor),
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
              labelStyle: const TextStyle(color: AppTheme.primaryColor),
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
              labelStyle: const TextStyle(color: AppTheme.primaryColor),
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
              labelStyle: const TextStyle(color: AppTheme.primaryColor),
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
              labelStyle: const TextStyle(color: AppTheme.primaryColor),
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
              labelStyle: const TextStyle(color: AppTheme.primaryColor),
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
              labelStyle: const TextStyle(color: AppTheme.primaryColor),
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
                'Barcode Entries (Box: $totalBoxes, Pieces: $totalPieces, Entries: $totalBarcodeEntries)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'WO #${widget.workOrderNo}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
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
                        'No boxes added yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        'Tap "Add Box" to get started',
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
              backgroundColor: AppTheme.primaryColor,
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
    final Map<String, Map<String, dynamic>> mergedBarcodes = {};

for (final barcode in box['barcodes']) {
  final code = barcode['code']?.toString() ?? '';

  if (code.isEmpty) continue;

  if (mergedBarcodes.containsKey(code)) {
    mergedBarcodes[code]!['count']++;
  } else {
    mergedBarcodes[code] = {
      'barcode': barcode,
      'count': 1,
    };
  }
}
    return Card(
      key: ValueKey("box_${box['id']}"),
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
                        color: AppTheme.primaryColor,
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
                        color: AppTheme.primaryColor,
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
            
            // Barcodes (Render all rows directly, preserving individual list inputs)
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
            
             ...mergedBarcodes.values.map((item) {
  return _buildMergedBarcodeEntry(
    boxIndex,
    item['barcode'],
    item['count'],
  );
}).toList(),
            
            // Add Barcode Button
            TextButton(
              onPressed: () => _addBarcode(boxIndex),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
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
Widget _buildMergedBarcodeEntry(
   int boxIndex,
  Map<String, dynamic> barcode,
  int count,
) {
  final isValidated = barcode['isValidated'] ?? false;

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isValidated ? Colors.green.shade50 : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: isValidated
            ? Colors.green.shade300
            : Colors.grey.shade300,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Duplicate message
        if (count > 1)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.content_copy,
                  size: 16,
                  color: Colors.orange,
                ),
                SizedBox(width: 6),
                Text(
                  "Duplicate barcodes in this box",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

        Row(
          children: [

            Icon(
              isValidated
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: isValidated
                  ? Colors.green
                  : Colors.grey,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  const Text(
                    "6-DIGIT BARCODE",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    barcode['code'] ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [

                const Text(
                  "PIECES",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                Text(
                  "$count",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            if (count > 1)
              Container(
                margin: const EdgeInsets.only(left: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "×$count",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                  
                ),
                
              ),
              const SizedBox(width: 8),

IconButton(
  icon: const Icon(
    Icons.close,
    color: Colors.red,
    size: 18,
  ),
  onPressed: () {
    _removeMergedBarcode(
      boxIndex,
      barcode['code'],
    );
  },
),
          ],
        ),
      ],
    ),
  );
}
  Widget _buildBarcodeEntry(int boxIndex, int barcodeIndex, Map<String, dynamic> barcode) {
    final isLoading = barcode['isLoading'] ?? false;
    final isValidated = barcode['isValidated'] ?? false;

    return Container(
      key: ValueKey("box_${boxIndex}_barcode_${barcode['id']}"),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isValidated ? Colors.green.shade50 : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isValidated ? Colors.green.shade300 : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '6-DIGIT BARCODE',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isValidated)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Colors.green.shade700,
                        ),
                      ),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: barcode['controller'] as TextEditingController,
                        decoration: const InputDecoration(
                          hintText: 'Enter barcode',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (value) => _handleManualBarcodeEntry(boxIndex, barcodeIndex, value),
                        onFieldSubmitted: (value) => _validateBarcode(boxIndex, barcodeIndex, value),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner, size: 20, color: AppTheme.primaryColor),
                      onPressed: () => _openScanner(boxIndex, barcodeIndex),
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
                Text(
                  barcode['pieces'].toString(),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.check,
              size: 20,
              color: isValidated ? Colors.green.shade700 : Colors.grey,
            ),
            onPressed: isLoading ? null : () => _validateBarcode(boxIndex, barcodeIndex, barcode['code']?.toString() ?? ''),
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

// Continuous Barcode Scanner Page
class BarcodeScannerPage extends StatefulWidget {
  final Function(List<String>) onDone;

  const BarcodeScannerPage({
    super.key,
    required this.onDone,
  });

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
  detectionSpeed: DetectionSpeed.unrestricted,
);
  
  List<String> scannedBarcodes = [];
  DateTime? _lastScanTime;
bool _isProcessing = false;
Map<String, int> get scannedSummary {
  final Map<String, int> summary = {};

  for (final code in scannedBarcodes) {
    summary[code] = (summary[code] ?? 0) + 1;
  }

  return summary;
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Continuous Scan'),
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
            icon: const Icon(Icons.done, size: 28),
            onPressed: () {
              widget.onDone(scannedBarcodes);
              Navigator.pop(context, scannedBarcodes);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
           onDetect: (capture) async {
  if (_isProcessing) return;

  final now = DateTime.now();

  if (_lastScanTime != null &&
      now.difference(_lastScanTime!).inMilliseconds < 800) {
    return;
  }

  final code = capture.barcodes.first.rawValue;

  if (code == null || code.isEmpty) return;

  _isProcessing = true;
  _lastScanTime = now;

  setState(() {
    scannedBarcodes.add(code);
  });

  // Small vibration-like delay
  await Future.delayed(const Duration(milliseconds: 800));

  _isProcessing = false;
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
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
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
                      decoration: const BoxDecoration(
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
                      decoration: const BoxDecoration(
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
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white, width: 4),
                          right: BorderSide(color: Colors.white, width: 4),
                        ),
                      ),
                    ),
                  ),
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
          // Bottom list showing scanned items immediately
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 180,
              color: Colors.white,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Text(
                    "Scanned (${scannedBarcodes.length})",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                  ),
                  const Divider(),
                  Expanded(
  child: Builder(
    builder: (_) {
      final items = scannedSummary.entries.toList();

      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];

          return ListTile(
            dense: true,
            leading: const Icon(
              Icons.check_circle,
              color: Colors.green,
            ),
            title: Text(item.key),
            trailing: item.value > 1
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "×${item.value}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  )
                : null,
          );
        },
      );
    },
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
