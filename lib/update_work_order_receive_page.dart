import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'app_theme.dart';
import 'api.dart';
import 'package:http/http.dart' as http;

class UpdateWorkOrderReceivePage extends StatefulWidget {
  final int id;

  const UpdateWorkOrderReceivePage({
    super.key,
    required this.id,
  });

  @override
  State<UpdateWorkOrderReceivePage> createState() => _UpdateWorkOrderReceivePageState();
}

class _UpdateWorkOrderReceivePageState extends State<UpdateWorkOrderReceivePage> {
  Color get primaryColor => AppTheme.primaryColor;
  bool get isDark => false;
  bool isLoading = true;
  bool isSaving = false;
  String errorMessage = '';
  int currentStep = 1;

  // Form Key & Controllers
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _factoryController = TextEditingController();
  final TextEditingController _workOrderIdController = TextEditingController();
  final TextEditingController _receiveDateController = TextEditingController();
  final TextEditingController _dcNoController = TextEditingController();
  final TextEditingController _dcDateController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _fabricReceivedByController = TextEditingController();
  final TextEditingController _fabricLeftOverController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _noOfBoxController = TextEditingController();
  final TextEditingController _totalPiecesController = TextEditingController();

  String _fabricReceived = 'Yes';
  String _status = 'On the Way';

  // Stepper box data
  List<Map<String, dynamic>> boxes = [];
  int totalBoxes = 0;
  int totalPieces = 0;
  int totalBarcodeEntries = 0; // Track total barcode entries
  int? workOrderNo;

  // Original fields to prevent database overwrite/vanishing values
  String? workOrderRcYear;
  int? workOrderRcNo;
  String? workOrderRcRef;
  String? workOrderRcDate;
  int? workOrderRcFactoryNo;
  String? workOrderRcFactory;
  int? workOrderRcId;
  String? workOrderRcWRef;
  String? workOrderRcBrand;

  // API endpoints
  final String barcodeCheckApi = '$baseUrl/fetch-work-order-finish-check';

  // Scanner state
  bool isScannerOpen = false;
  int? scanningBoxIndex;
  int? scanningBarcodeIndex;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  @override
  void dispose() {
    _factoryController.dispose();
    _workOrderIdController.dispose();
    _receiveDateController.dispose();
    _dcNoController.dispose();
    _dcDateController.dispose();
    _brandController.dispose();
    _fabricReceivedByController.dispose();
    _fabricLeftOverController.dispose();
    _remarksController.dispose();
    _noOfBoxController.dispose();
    _totalPiecesController.dispose();

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

  Future<void> _fetchDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.get(
        Uri.parse('$baseUrl/fetch-work-order-received-by-id/${widget.id}'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Update Fetch Details Status: ${response.statusCode}');
      print('Update Fetch Details Response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Map<String, dynamic>? mainDetails;
        List<dynamic> subList = [];

        // Parse workorderrc (main details)
        if (data is Map) {
          final rc = data['workorderrc'];
          if (rc is List && rc.isNotEmpty) {
            mainDetails = rc.first;
          } else if (rc is Map<String, dynamic>) {
            mainDetails = rc;
          }

          // Use workorderrcsubNew primarily for IDs, fallback to workorderrcsub
          subList = data['workorderrcsubNew'] ?? data['workorderrcsub'] ?? [];
        }

        if (mainDetails != null) {
          // Store original backend relation properties to prevent them from vanishing on PUT update
          workOrderRcYear = mainDetails['work_order_rc_year']?.toString();
          workOrderRcNo = int.tryParse(mainDetails['work_order_rc_no']?.toString() ?? '');
          workOrderRcRef = mainDetails['work_order_rc_ref']?.toString();
          workOrderRcDate = mainDetails['work_order_rc_date']?.toString();
          workOrderRcFactoryNo = int.tryParse(mainDetails['work_order_rc_factory_no']?.toString() ?? '');
          workOrderRcFactory = mainDetails['work_order_rc_factory']?.toString();
          workOrderRcId = int.tryParse(mainDetails['work_order_rc_id']?.toString() ?? '');
          workOrderRcWRef = mainDetails['work_order_rc_w_ref']?.toString();
          workOrderRcBrand = mainDetails['work_order_rc_brand']?.toString();

          workOrderNo = workOrderRcId; // For validation checks

          // Pre-populate text fields
          _factoryController.text = workOrderRcFactory ?? '';
          _workOrderIdController.text = workOrderRcId?.toString() ?? '';
          _receiveDateController.text = workOrderRcDate ?? '';
          _dcNoController.text = mainDetails['work_order_rc_dc_no']?.toString() ?? '';
          _dcDateController.text = mainDetails['work_order_rc_dc_date']?.toString() ?? '';
          _brandController.text = workOrderRcBrand ?? '';
          _fabricReceived = mainDetails['work_order_rc_fabric_received']?.toString() ?? 'Yes';
          _fabricReceivedByController.text = mainDetails['work_order_rc_received_by']?.toString() ?? '';
          _fabricLeftOverController.text = mainDetails['work_order_rc_fabric_count']?.toString() ?? 
                                           mainDetails['work_order_rc_fabric_left_over']?.toString() ?? '';
          _remarksController.text = mainDetails['work_order_rc_remarks']?.toString() ?? '';
          _status = mainDetails['work_order_rc_status']?.toString() ?? 'On the Way';

          // Map database sub items directly to UI rows (1-to-1 without duplicate grouping)
          List<Map<String, dynamic>> parsedBoxes = [];

          for (int i = 0; i < subList.length; i++) {
            final sub = subList[i];
            final boxNo = int.tryParse(sub['work_order_rc_sub_box']?.toString() ?? '') ?? 
                          int.tryParse(sub['work_order_rc_sub_box_no']?.toString() ?? '') ?? 
                          int.tryParse(sub['box_no']?.toString() ?? '') ?? 1;
            final barcode = (sub['work_order_rc_sub_barcode'] ?? sub['barcode'] ?? sub['code'] ?? '').toString().trim();
            
            // Extract the database ID from this item or fallback to check workorderrcsubNew
            int? dbId = int.tryParse(sub['id']?.toString() ?? '');
            if (dbId == null && data['workorderrcsubNew'] is List && (data['workorderrcsubNew'] as List).length > i) {
              dbId = int.tryParse(data['workorderrcsubNew'][i]['id']?.toString() ?? '');
            }

            if (barcode.isNotEmpty) {
              while (parsedBoxes.length < boxNo) {
                parsedBoxes.add({
                  'id': parsedBoxes.length + 1,
                  'pieces': 0,
                  'barcodes': [],
                  'isExpanded': true,
                  'isFromDatabase': true,
                  'isBoxValidated': true,
                  'isValidatingBox': false,
                });
              }

              parsedBoxes[boxNo - 1]['barcodes'].add({
                'id': parsedBoxes[boxNo - 1]['barcodes'].length + 1,
                'code': barcode,
                'pieces': 1,
                'isValidated': true,
                'isLoading': false,
                'controller': TextEditingController(text: barcode),
                'ids': [dbId],
                'isFromDb': true,
              });

              parsedBoxes[boxNo - 1]['pieces']++;
            }
          }

          if (parsedBoxes.isEmpty) {
            parsedBoxes.add({
              'id': 1,
              'pieces': 0,
              'barcodes': [],
              'isExpanded': true,
              'isBoxValidated': false,
              'isValidatingBox': false,
            });
          }

          setState(() {
            boxes = parsedBoxes;
            for (int i = 0; i < boxes.length; i++) {
              _ensureEmptyBarcodeRow(i);
            }
            _updateTotalPieces();
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = 'Work order details not found in API response.';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Failed to load work order receive details (Status: ${response.statusCode}).';
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error parsing received details: $e');
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
    }
  }

  void _updateTotalPieces() {
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
      totalBoxes = boxes.length;
      _noOfBoxController.text = totalBoxes.toString();
      _totalPiecesController.text = totalPieces.toString();
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

  void _addBox() {
    setState(() {
      boxes.add({
        'id': boxes.length + 1,
        'pieces': 0,
        'barcodes': [],
        'isExpanded': true,
        'isBoxValidated': false,
        'isValidatingBox': false,
      });
      _ensureEmptyBarcodeRow(boxes.length - 1);
    });
  }

  Future<void> _removeBox(int index) async {
    final box = boxes[index];
    final bool isFromDb = box['isFromDatabase'] == true;

    if (isFromDb) {
      final bool confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Box'),
          content: Text('Are you sure you want to permanently delete Box ${box['id']} from the database? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('DELETE'),
            ),
          ],
        ),
      ) ?? false;

      if (!confirm) return;

      setState(() {
                                                                                    
        isLoading = true;
      });

      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token') ?? '';
        
        final response = await http.delete(
          Uri.parse('$baseUrl/delete-work-order-received-box-sub'),
          headers: {
            "Authorization": "Bearer $token",
            "Accept": "application/json",
            "Content-Type": "application/json",
          },
          body: jsonEncode({
            "work_order_rc_ref": workOrderRcRef,
            "work_order_rc_sub_box": box['id'].toString(),
          }),
        );

        print('Delete Box Status: ${response.statusCode}');
        print('Delete Box Response: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Box ${box['id']} deleted from database successfully'),
              backgroundColor: Colors.green,
            ),
          );

          setState(() {
            for (var barcode in box['barcodes']) {
              if (barcode['controller'] != null) {
                (barcode['controller'] as TextEditingController).dispose();
              }
              if (barcode['focusNode'] != null) {
                (barcode['focusNode'] as FocusNode).dispose();
              }
            }
            boxes.removeAt(index);
            for (int i = 0; i < boxes.length; i++) {
              boxes[i]['id'] = i + 1;
            }
            _updateTotalPieces();
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete box from database: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      setState(() {
        for (var barcode in box['barcodes']) {
          if (barcode['controller'] != null) {
            (barcode['controller'] as TextEditingController).dispose();
          }
          if (barcode['focusNode'] != null) {
            (barcode['focusNode'] as FocusNode).dispose();
          }
        }
        boxes.removeAt(index);
        for (int i = 0; i < boxes.length; i++) {
          boxes[i]['id'] = i + 1;
        }
        _updateTotalPieces();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Box removed locally'),
        ),
      );
    }
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
          final url = '$barcodeCheckApi/$workOrderNo/$code';
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

  // Validate barcode against API
  // No API validation on scan/entry — accept barcode immediately
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
      boxes[boxIndex]['barcodes'][barcodeIndex]['ids'] = [null];

      _updateBoxPieces(boxIndex);
      _ensureEmptyBarcodeRow(boxIndex);
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
          'ids': [null],
        });
        _updateTotalPieces();
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
          final firstCode = barcodes.first.trim();
          setState(() {
            boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = firstCode;
            boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = true;
            boxes[boxIndex]['barcodes'][barcodeIndex]['pieces'] = 1;
            boxes[boxIndex]['barcodes'][barcodeIndex]['ids'] = [null];
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
            boxes[boxIndex]['barcodes'][index]['ids'] = [null];
            if (boxes[boxIndex]['barcodes'][index]['controller'] != null) {
              (boxes[boxIndex]['barcodes'][index]['controller'] as TextEditingController).text = code;
            }
            _updateBoxPieces(boxIndex);
            _ensureEmptyBarcodeRow(boxIndex);
          });
        }
      }
    } catch (e) {
      // ignore
    } finally {
      setState(() {
        isScannerOpen = false;
        scanningBoxIndex = null;
        scanningBarcodeIndex = null;
      });
    }
  }

  // Manual barcode entry
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

  Future<void> _updateWorkOrderReceive() async {
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
    isLoading = true;
  });

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token") ?? "";

    ///========================
    /// Create barcode array
    ///========================

    List<Map<String, dynamic>> subData = [];

    for (var box in boxes) {
      for (var barcode in box['barcodes']) {
        final code = barcode['code'].toString().trim();

        if (code.isEmpty) continue;

        final ids = barcode['ids'] as List<dynamic>? ?? [];

        subData.add({
          "id": ids.isNotEmpty && ids.first != null
              ? ids.first.toString()
              : "",
          "work_order_rc_sub_barcode": code,
          "work_order_rc_sub_box": box['id'].toString(),
        });
      }
    }

    ///========================
    /// Create JSON Payload
    ///========================

    final Map<String, dynamic> payload = {
      "work_order_rc_dc_no": _dcNoController.text.trim(),
      "work_order_rc_dc_date": _dcDateController.text.trim(),
      "work_order_rc_box": totalBoxes.toString(),
      "work_order_rc_pcs": totalPieces.toString(),
      "work_order_rc_fabric_received": _fabricReceived,
      "work_order_rc_fabric_count":
          _fabricLeftOverController.text.trim(),
      "work_order_rc_count":
          totalBarcodeEntries.toString(),
      "work_order_rc_remarks":
          _remarksController.text.trim(),
      "workorder_sub_rc_data": subData,
    };

    print("============== JSON Payload ==============");
    print(jsonEncode(payload));

    final response = await http.put(
      Uri.parse(
          '$baseUrl/update-work-orders-received/${widget.id}'),
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
        "Content-Type": "application/json",
      },
      body: jsonEncode(payload),
    );

    print("Status : ${response.statusCode}");
    print("Response : ${response.body}");

    setState(() {
      isSaving = false;
      isLoading = false;
    });

    if (response.statusCode == 200 ||
        response.statusCode == 201) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Work Order Receive Updated Successfully"),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context, true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Update Failed (${response.statusCode})\n${response.body}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    setState(() {
      isSaving = false;
      isLoading = false;
    });

    print(e);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString()),
        backgroundColor: Colors.red,
      ),
    );
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
        title: const Text('Update Work Order Receive', style: TextStyle(fontSize: 18, color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading || isSaving
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Go Back'),
                        ),
                      ],
                    ),
                  ),
                )
              : Container(
                  color: Colors.grey[50],
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stepper bar
                      _buildStepProgressBar(),
                      const SizedBox(height: 16),
                      // Step content
                      Expanded(
                        child: Form(
                          key: _formKey,
                          child: currentStep == 0
                              ? _buildDetailsStep()
                              : _buildBarcodesStep(),
                        ),
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: isLoading || isSaving || errorMessage.isNotEmpty
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 4,
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (currentStep == 1)
                      OutlinedButton(
                        onPressed: totalPieces == 0
                            ? null
                            : () {
                                setState(() {
                                  currentStep = 0;
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Edit'),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ElevatedButton(
                      onPressed: (currentStep == 1 && totalPieces == 0)
                          ? null
                          : () {
                              if (currentStep == 0) {
                                if (_formKey.currentState!.validate()) {
                                  setState(() {
                                    currentStep = 1;
                                  });
                                }
                              } else {
                                _updateWorkOrderReceive();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (currentStep == 1 && totalPieces == 0) ? Colors.grey[300] : primaryColor,
                        foregroundColor: (currentStep == 1 && totalPieces == 0) ? Colors.grey[500] : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(currentStep == 0 ? 'Next' : 'Update'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStepProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Step ${currentStep + 1} of 2',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
            ),
            Text(
              currentStep == 0 ? 'Details Configuration' : 'Box Barcode Configurations',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (currentStep + 1) / 2,
            minHeight: 6,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;
              final crossAxisCount = width > 800 ? 4 : (width > 550 ? 2 : 1);
              
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: crossAxisCount == 1 ? 4.5 : 2.5,
                children: [
                  _buildReadOnlyField('Factory', _factoryController),
                  _buildReadOnlyField('Work Order ID', _workOrderIdController),
                  _buildReadOnlyField('Receive Date', _receiveDateController),
                  _buildEditableField('DC No', _dcNoController),
                  _buildEditableField('DC Date', _dcDateController),
                  _buildReadOnlyField('Brand', _brandController),
                  _buildReadOnlyField('No of Box', _noOfBoxController, hint: 'Auto-calculated'),
                  _buildReadOnlyField('Total No of Pcs', _totalPiecesController, hint: 'Auto-calculated'),
                  _buildDropdownField('Fabric Received *'),
                  _buildEditableField('Fabric Received By', _fabricReceivedByController),
                  _buildEditableField('Fabric Left Over', _fabricLeftOverController),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Remarks field (spans full width)
          TextFormField(
            controller: _remarksController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Remarks',
              hintText: 'Enter remarks here (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField(String label, TextEditingController controller, {String? hint}) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey[100],
      ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (value) {
        if (label.contains('*') && (value == null || value.trim().isEmpty)) {
          return 'This field is required';
        }
        return null;
      },
    );
  }

  Widget _buildDropdownField(String label) {
    return DropdownButtonFormField<String>(
      value: _fabricReceived,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
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
    );
  }

  Widget _buildBarcodesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Barcode Entries (Box: $totalBoxes, Pieces: $totalPieces, Entries: $totalBarcodeEntries)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryColor),
              ),
              const SizedBox(height: 4),
              Text(
                'Add boxes and barcodes below. You can type a 6-digit code or use the camera to scan.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        Expanded(
          child: boxes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      const Text('No boxes added yet'),
                      TextButton(
                        onPressed: () {
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
                        child: const Text('Add Box'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: boxes.length,
                  itemBuilder: (context, index) {
                    final box = boxes[index];
                    return _buildBoxCard(index, box);
                  },
                ),
        ),
        if (totalPieces == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'At least one barcode/piece is required to update.',
              style: TextStyle(color: Colors.red[700], fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ElevatedButton.icon(
          onPressed: () {
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
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildBoxCard(int boxIndex, Map<String, dynamic> box) {
    final barcodes = box['barcodes'] as List<dynamic>;
    final bool isBoxValidated = box['isBoxValidated'] == true;
    final bool isValidatingBox = box['isValidatingBox'] == true;

    return Card(
      key: ValueKey("box_${box['id']}"),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isBoxValidated ? Colors.green.shade600 : primaryColor,
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
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 20,
                        ),
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
                if (barcodes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No barcodes added to this box', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  )
                else ...(() {
                  final List<Map<String, dynamic>> dbBarcodes = [];
                  final List<Map<String, dynamic>> newValidatedBarcodes = [];
                  final List<Map<String, dynamic>> activeBarcodes = [];

                  final Set<String> dbCodes = {};
                  int totalDbPieces = 0;

                  // 1. Identify database codes and sum up their pieces
                  for (var barcode in barcodes) {
                    final code = barcode['code']?.toString().trim() ?? '';
                    final bool isBarcodeFromDb = barcode['isFromDb'] == true;
                    final isValidated = barcode['isValidated'] == true;
                    if (code.isNotEmpty && isBarcodeFromDb) {
                      dbCodes.add(code);
                      if (isValidated) {
                        totalDbPieces++;
                      }
                    }
                  }

                  // 2. Classify and partition
                  final Set<String> seenDbCodes = {};
                  final Set<String> seenNewCodes = {};

                  for (int i = 0; i < barcodes.length; i++) {
                    final barcode = barcodes[i];
                    final code = barcode['code']?.toString().trim() ?? '';
                    final isValidated = barcode['isValidated'] == true;
                    final bool isBarcodeFromDb = barcode['isFromDb'] == true;

                    if (code.isEmpty) {
                      activeBarcodes.add({...barcode, 'originalIndex': i});
                    } else if (isValidated) {
                      if (isBarcodeFromDb) {
                        if (!seenDbCodes.contains(code)) {
                          seenDbCodes.add(code);
                          dbBarcodes.add({...barcode, 'originalIndex': i});
                        }
                      } else {
                        if (!seenNewCodes.contains(code)) {
                          seenNewCodes.add(code);
                          newValidatedBarcodes.add({...barcode, 'originalIndex': i});
                        }
                      }
                    } else {
                      activeBarcodes.add({...barcode, 'originalIndex': i});
                    }
                  }

                  box['showSavedBarcodes'] = box['showSavedBarcodes'] ?? false;
                  final bool showSaved = box['showSavedBarcodes'] == true;

                  return [
                    // 1. Active/editing barcodes
                    ...activeBarcodes.map((barcode) {
                      final int originalIndex = barcode['originalIndex'];
                      return _buildBarcodeEntry(boxIndex, originalIndex, barcode);
                    }),

                    // 2. New validated barcodes rendered as 3 per row grid
                    if (newValidatedBarcodes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 2.8,
                        ),
                        itemCount: newValidatedBarcodes.length,
                        itemBuilder: (context, index) {
                          final barcode = newValidatedBarcodes[index];
                          return _buildBarcodeChip(boxIndex, barcode['originalIndex'], barcode, canDelete: true);
                        },
                      ),
                    ],

                    // 3. Collapsible database barcodes
                    if (dbBarcodes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                box['showSavedBarcodes'] = !showSaved;
                              });
                            },
                            icon: Icon(
                              showSaved ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              size: 18,
                            ),
                            label: Text(
                              '${showSaved ? "Hide" : "View"} Saved Barcodes ($totalDbPieces pieces)',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: primaryColor,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(100, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      if (showSaved) ...[
                        const SizedBox(height: 8),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.8,
                          ),
                          itemCount: dbBarcodes.length,
                          itemBuilder: (context, index) {
                            final barcode = dbBarcodes[index];
                            return _buildBarcodeChip(boxIndex, barcode['originalIndex'], barcode, canDelete: false);
                          },
                        ),
                      ],
                    ],
                  ];
                })(),
            const SizedBox(height: 8),
            
          ],
        ),
      ),
          ],
  ),
);
  }

  Widget _buildBarcodeEntry(int boxIndex, int barcodeIndex, Map<String, dynamic> barcode) {
    final isLoading = barcode['isLoading'] ?? false;
    final isValidated = barcode['isValidated'] ?? false;

    final bool isBarcodeFromDb = barcode['isFromDb'] == true;

    int occurrenceCount = 0;
    final currentCode = barcode['code']?.toString().trim() ?? '';
    final isValidatedCode = barcode['isValidated'] == true;

    if (currentCode.isNotEmpty && isValidatedCode) {
      for (var bar in boxes[boxIndex]['barcodes']) {
        if (bar['code']?.toString().trim() == currentCode && bar['isValidated'] == true) {
          occurrenceCount++;
        }
      }
    }

    return Container(
      key: ValueKey("box_${boxIndex}_barcode_${barcode['id']}"),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isValidated ? Colors.green.shade50 : const Color.fromARGB(255, 255, 255, 255),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isValidated ? Colors.green.shade300 : const Color.fromARGB(255, 146, 141, 255),
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
                   
                    if (occurrenceCount > 1)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B), width: 0.5),
                        ),
                        child: Text(
                          '* $occurrenceCount',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFD97706),
                          ),
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
    focusNode: barcode['focusNode'] as FocusNode?,
    autofocus: barcode['code'].toString().isEmpty,
    style: const TextStyle(
      color: Colors.black, // Text color
      fontSize: 16,
    ),
    decoration: InputDecoration(
      hintText: 'Enter barcode',
      hintStyle: TextStyle(
        color: primaryColor, // Hint text color
      ),
      border: InputBorder.none,
      isDense: true,
    ),
    onChanged: (value) =>
        _handleManualBarcodeEntry(boxIndex, barcodeIndex, value),
    onFieldSubmitted: (value) =>
        _validateBarcode(boxIndex, barcodeIndex, value),
  ),
),
                    
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
             
            ),
          ),

          IconButton(
                      icon: Icon(Icons.qr_code_scanner, size: 20, color: primaryColor),
                      onPressed: () => _openScanner(boxIndex, barcodeIndex),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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
            icon: Icon(
              Icons.close,
              size: 16,
              color: isBarcodeFromDb ? Colors.grey : Colors.red,
            ),
            onPressed: isBarcodeFromDb ? null : () => _removeBarcode(boxIndex, barcodeIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeChip(int boxIndex, int originalIndex, Map<String, dynamic> barcode, {required bool canDelete}) {
    final code = barcode['code']?.toString().trim() ?? '';
    final bool isBarcodeFromDb = barcode['isFromDb'] == true;
    final bool isError = barcode['isError'] == true;

    // Calculate occurrenceCount for this code in its respective category
    int occurrenceCount = 0;
    for (var bar in boxes[boxIndex]['barcodes']) {
      if (bar['code']?.toString().trim() == code && bar['isValidated'] == true) {
        final bool barFromDb = bar['isFromDb'] == true;
        if (barFromDb == isBarcodeFromDb) {
          occurrenceCount++;
        }
      }
    }

    Color bgColor = canDelete ? const Color(0xFFE8F5E9) : const Color(0xFFF1F5F9);
    Color borderColor = canDelete ? const Color(0xFFA5D6A7) : const Color(0xFFE2E8F0);
    Color textColor = canDelete ? const Color(0xFF2E7D32) : const Color(0xFF475569);

    if (isError) {
      bgColor = const Color(0xFFFFEBEE);
      borderColor = const Color(0xFFEF9A9A);
      textColor = const Color(0xFFC62828);
    }

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
              code,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (occurrenceCount > 1) ...[
            const SizedBox(width: 4),
            Text(
              '*$occurrenceCount',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isError ? const Color(0xFFC62828) : const Color(0xFFE65100),
              ),
            ),
          ],
          if (canDelete) ...[
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
        ],
      ),
    );
  }
}

// Barcode Scanner Page
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
