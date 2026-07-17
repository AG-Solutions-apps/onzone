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
        if (barcode['focusNode'] != null) {
          (barcode['focusNode'] as FocusNode).dispose();
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
        'isBoxValidated': false,
        'isValidatingBox': false,
      });
      totalBoxes = boxes.length;
      _ensureEmptyBarcodeRow(boxes.length - 1);
    });
  }

  void _removeBox(int index) {
    setState(() {
      final box = boxes[index];
      // Remove all barcodes in this box
      for (var barcode in box['barcodes']) {
        if (barcode['controller'] != null) {
          (barcode['controller'] as TextEditingController).dispose();
        }
        if (barcode['focusNode'] != null) {
          (barcode['focusNode'] as FocusNode).dispose();
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
  void _ensureEmptyBarcodeRow(int boxIndex) {
    final list = boxes[boxIndex]['barcodes'];
    bool hasEmpty = false;
    for (var barcode in list) {
      if ((barcode['code']?.toString().trim() ?? '').isEmpty && barcode['isValidated'] != true) {
        hasEmpty = true;
        if (barcode['focusNode'] != null) {
          final focusNode = barcode['focusNode'] as FocusNode;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (focusNode.canRequestFocus) {
              focusNode.requestFocus();
            }
          });
        }
        break;
      }
    }

    if (!hasEmpty) {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      setState(() {
        list.insert(0, {
          'id': list.isEmpty ? 1 : list.map((e) => e['id'] as int).reduce((a, b) => a > b ? a : b) + 1,
          'code': '',
          'pieces': 0,
          'isValidated': false,
          'isLoading': false,
          'barcodeData': null,
          'controller': controller,
          'focusNode': focusNode,
        });
        totalBarcodeEntries++;
        _updateTotals();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusNode.canRequestFocus) {
          focusNode.requestFocus();
        }
      });
    }
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
  _ensureEmptyBarcodeRow(boxIndex);
}
  void _removeBarcode(int boxIndex, int barcodeIndex) {
    setState(() {
      final barcode = boxes[boxIndex]['barcodes'][barcodeIndex];
      if (barcode['controller'] != null) {
        (barcode['controller'] as TextEditingController).dispose();
      }
      if (barcode['focusNode'] != null) {
        (barcode['focusNode'] as FocusNode).dispose();
      }
      boxes[boxIndex]['barcodes'].removeAt(barcodeIndex);
      for (int i = 0; i < boxes[boxIndex]['barcodes'].length; i++) {
        boxes[boxIndex]['barcodes'][i]['id'] = i + 1;
      }
      _updateBoxPieces(boxIndex);
      _ensureEmptyBarcodeRow(boxIndex);
    });
  }

  void _updateTotals() {
    int total = 0;
    int totalEntries = 0;
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        final pieces = int.tryParse(barcode['pieces'].toString()) ?? 0;
        total += pieces;
        totalEntries += pieces;
      }
    }
    setState(() {
      totalPieces = total;
      totalBarcodeEntries = totalEntries;
    });
  }

  void _updateTotalPieces() {
    _updateTotals();
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

  // Per-box API validation
  Future<void> _validateBox(int boxIndex) async {
    final barcodes = boxes[boxIndex]['barcodes'] as List<dynamic>;
    final nonEmptyBarcodes = barcodes
        .asMap()
        .entries
        .where((e) => (e.value['code']?.toString().trim() ?? '').isNotEmpty)
        .toList();

    if (nonEmptyBarcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one barcode before validating'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      boxes[boxIndex]['isValidatingBox'] = true;
      boxes[boxIndex]['isBoxValidated'] = false;
      // Reset error state for all barcodes
      for (var b in boxes[boxIndex]['barcodes']) {
        b['isError'] = false;
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      // Get unique non-empty codes to validate
      final uniqueCodes = nonEmptyBarcodes
          .map((e) => e.value['code']?.toString().trim() ?? '')
          .where((code) => code.isNotEmpty)
          .toSet()
          .toList();

      final Map<String, bool> results = {};

      for (final code in uniqueCodes) {
        try {
          final url = '$barcodeCheckApi/${widget.workOrderNo}/$code';
          final response = await http.get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );

          bool found = false;
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            found = data['code'] == 200;
          }
          results[code] = found;
        } catch (_) {
          results[code] = false;
        }
      }

      bool allOk = true;
      if (mounted) {
        setState(() {
          for (int i = 0; i < barcodes.length; i++) {
            final code = barcodes[i]['code']?.toString().trim() ?? '';
            if (code.isEmpty) continue;

            final isValid = results[code] ?? false;
            if (!isValid) {
              allOk = false;
            }
            boxes[boxIndex]['barcodes'][i]['isError'] = !isValid;
          }
          boxes[boxIndex]['isBoxValidated'] = allOk;
          boxes[boxIndex]['isValidatingBox'] = false;
        });
      }
      if (mounted) {
        if (allOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Box ${boxes[boxIndex]['id']} validated ✓'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Some barcodes are invalid — remove red ones and retry'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          boxes[boxIndex]['isValidatingBox'] = false;
        });
      }
    }
  }

  // No API validation — accept barcode immediately
  void _validateBarcode(
    int boxIndex,
    int barcodeIndex,
    String barcode,
  ) {
    final trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) return;

    setState(() {
      boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = trimmedBarcode;
      boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = true;
      boxes[boxIndex]['barcodes'][barcodeIndex]['isLoading'] = false;
      boxes[boxIndex]['barcodes'][barcodeIndex]['pieces'] = 1;
      _updateBoxPieces(boxIndex);
      _ensureEmptyBarcodeRow(boxIndex);
    });
  }

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
          final firstCode = barcodes.first.trim();
          setState(() {
            boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = firstCode;
            boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = true;
            boxes[boxIndex]['barcodes'][barcodeIndex]['pieces'] = 1;
            if (boxes[boxIndex]['barcodes'][barcodeIndex]['controller'] != null) {
              (boxes[boxIndex]['barcodes'][barcodeIndex]['controller'] as TextEditingController).text = firstCode;
            }
            _updateBoxPieces(boxIndex);
            _ensureEmptyBarcodeRow(boxIndex);
          });
          startScanIdx = 1;
        }

        for (int i = startScanIdx; i < barcodes.length; i++) {
          final code = barcodes[i].trim();
          _addBarcodeRow(boxIndex);
          final int index = boxes[boxIndex]['barcodes'].length - 1;
          setState(() {
            boxes[boxIndex]['barcodes'][index]['code'] = code;
            boxes[boxIndex]['barcodes'][index]['isValidated'] = true;
            boxes[boxIndex]['barcodes'][index]['pieces'] = 1;
            if (boxes[boxIndex]['barcodes'][index]['controller'] != null) {
              (boxes[boxIndex]['barcodes'][index]['controller'] as TextEditingController).text = code;
            }
            _updateBoxPieces(boxIndex);
            _ensureEmptyBarcodeRow(boxIndex);
          });
        }
      }
    } catch (e) {
      // ignore scanner errors
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
    // Check all boxes are validated
    final bool allBoxesValidated = boxes.isNotEmpty && boxes.every((b) => b['isBoxValidated'] == true);
    if (!allBoxesValidated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please validate all boxes before saving'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if there are any barcodes entered
    bool hasBarcodes = false;
    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        final code = barcode['code'].toString().trim();
        if (code.isNotEmpty) {
          hasBarcodes = true;
          break;
        }
      }
      if (hasBarcodes) break;
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

          if (code.isNotEmpty && pieces > 0) {
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentStep == 0 ? 'Add Packing Slip' : 'Scan Barcodes',
              style: const TextStyle(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStepIndicator(0, 'Details'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: List.generate(4, (i) => Container(
                      width: 6,
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: currentStep >= 1
                            ? Colors.white
                            : Colors.white.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )),
                  ),
                ),
                _buildStepIndicator(1, 'Barcodes'),
              ],
            ),
          ],
        ),
        toolbarHeight: 72,
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        boxShadow: isActive
            ? [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0, 2))]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primaryColor : Colors.white.withOpacity(0.35),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white.withOpacity(0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? AppTheme.primaryColor : Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
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
            onPressed: () {
              // Allow adding a new box only if at least one existing box is validated
              final bool anyValidated = boxes.any((b) => b['isBoxValidated'] == true);
              if (boxes.isNotEmpty && !anyValidated) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please validate the current box before adding a new one'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              _addBox();
            },
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
    final barcodes = box['barcodes'] as List<dynamic>;
    final bool isBoxValidated = box['isBoxValidated'] == true;
    final bool isValidatingBox = box['isValidatingBox'] == true;

    final List<Map<String, dynamic>> validatedBarcodes = [];
    final List<Map<String, dynamic>> activeBarcodes = [];
    final Set<String> seenCodes = {};

    for (int i = 0; i < barcodes.length; i++) {
      final barcode = barcodes[i];
      final code = barcode['code']?.toString().trim() ?? '';
      final isValidated = barcode['isValidated'] == true;

      if (code.isEmpty || !isValidated) {
        activeBarcodes.add({...barcode, 'originalIndex': i});
      } else if (!seenCodes.contains(code)) {
        seenCodes.add(code);
        validatedBarcodes.add({...barcode, 'originalIndex': i});
      }
    }

    return Card(
      key: ValueKey("box_${box['id']}"),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isBoxValidated ? Colors.green.shade600 : AppTheme.primaryColor,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (isBoxValidated)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.check_circle, color: Colors.white, size: 18),
                      ),
                    Text(
                      'Box ${box['id']} (${box['pieces']} pieces)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Validate button
                    if (!isBoxValidated)
                      isValidatingBox
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : TextButton(
                              onPressed: () => _validateBox(boxIndex),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.2),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: const Text(
                                'Validate',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            )
                    else
                      TextButton(
                        onPressed: () {
                          setState(() {
                            boxes[boxIndex]['isBoxValidated'] = false;
                            for (var b in boxes[boxIndex]['barcodes']) {
                              b['isError'] = false;
                            }
                          });
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'Re-validate',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (boxes.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                        splashRadius: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => _removeBox(boxIndex),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Validated barcodes grid (3 per row)
                if (validatedBarcodes.isNotEmpty) ...[
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 2.4,
                    ),
                    itemCount: validatedBarcodes.length,
                    itemBuilder: (context, i) {
                      final b = validatedBarcodes[i];
                      return _buildBarcodeChip(boxIndex, b['originalIndex'] as int, b);
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                // Active (input) barcodes
                if (activeBarcodes.isEmpty && validatedBarcodes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No barcodes added yet',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  )
                else
                  ...activeBarcodes.map((barcode) {
                    final int originalIndex = barcode['originalIndex'] as int;
                    return _buildBarcodeEntry(boxIndex, originalIndex, barcode);
                  }),

                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeChip(int boxIndex, int originalIndex, Map<String, dynamic> barcode) {
    final code = barcode['code']?.toString().trim() ?? '';
    final bool isError = barcode['isError'] == true;

    // Count occurrences of this code among validated barcodes in this box
    int occurrenceCount = 0;
    for (var bar in boxes[boxIndex]['barcodes']) {
      if (bar['code']?.toString().trim() == code && bar['isValidated'] == true) {
        occurrenceCount++;
      }
    }

    final bgColor = isError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);
    final borderColor = isError ? const Color(0xFFEF9A9A) : const Color(0xFFA5D6A7);
    final textColor = isError ? const Color(0xFFC62828) : const Color(0xFF2E7D32);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isError)
            const Padding(
              padding: EdgeInsets.only(right: 3),
              child: Icon(Icons.error_outline, size: 12, color: Color(0xFFC62828)),
            ),
          Flexible(
            child: Text(
              occurrenceCount > 1 ? '$code *$occurrenceCount' : code,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _removeBarcode(boxIndex, originalIndex),
            child: Icon(
              Icons.cancel,
              size: 14,
              color: isError ? const Color(0xFFC62828) : Colors.red,
            ),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isValidated ? Colors.green.shade50 : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isValidated ? Colors.green.shade300 : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: barcode['controller'] as TextEditingController,
                    focusNode: barcode['focusNode'] as FocusNode?,
                    autofocus: barcode['code'].toString().isEmpty,
                    decoration: InputDecoration(
                      hintText: 'Enter barcode',
                      border: InputBorder.none,
                      isDense: true,
                      suffixIcon: isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : isValidated
                              ? Icon(Icons.check_circle, size: 18, color: Colors.green.shade700)
                              : null,
                    ),
                    onChanged: (value) => _handleManualBarcodeEntry(boxIndex, barcodeIndex, value),
                    onFieldSubmitted: (value) => _validateBarcode(boxIndex, barcodeIndex, value),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, size: 20, color: AppTheme.primaryColor),
                  onPressed: () => _openScanner(boxIndex, barcodeIndex),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.check_circle_outline,
              size: 22,
              color: isValidated ? Colors.green.shade700 : Colors.grey[400],
            ),
            onPressed: isLoading
                ? null
                : () => _validateBarcode(boxIndex, barcodeIndex, barcode['code']?.toString() ?? ''),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            icon: const Icon(Icons.cancel, size: 18, color: Colors.red),
            onPressed: () => _removeBarcode(boxIndex, barcodeIndex),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
      now.difference(_lastScanTime!).inMilliseconds < 1500) {
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
