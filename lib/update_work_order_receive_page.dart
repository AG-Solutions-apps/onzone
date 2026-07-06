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
            });
          }

          setState(() {
            boxes = parsedBoxes;
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
      });
      _updateTotalPieces();
    });
  }

  void _removeBox(int index) {
    setState(() {
      final box = boxes[index];
      for (var barcode in box['barcodes']) {
        if (barcode['controller'] != null) {
          (barcode['controller'] as TextEditingController).dispose();
        }
      }
      boxes.removeAt(index);
      for (int i = 0; i < boxes.length; i++) {
        boxes[i]['id'] = i + 1;
      }
      _updateTotalPieces();
    });
  }

  void _addBarcode(int boxIndex) {
    setState(() {
      final controller = TextEditingController(text: '');
      boxes[boxIndex]['barcodes'].add({
        'id': boxes[boxIndex]['barcodes'].length + 1,
        'code': '',
        'pieces': 0,
        'isValidated': false,
        'isLoading': false,
        'controller': controller,
        'ids': [null],
      });
      _updateTotalPieces();
    });
  }

  void _removeBarcode(int boxIndex, int barcodeIndex) {
    setState(() {
      final barcode = boxes[boxIndex]['barcodes'][barcodeIndex];
      final codeToRemove = barcode['code']?.toString().trim() ?? '';
      
      if (codeToRemove.isNotEmpty) {
        final list = boxes[boxIndex]['barcodes'];
        for (var i = list.length - 1; i >= 0; i--) {
          if (list[i]['code']?.toString().trim() == codeToRemove) {
            if (list[i]['controller'] != null) {
              (list[i]['controller'] as TextEditingController).dispose();
            }
            list.removeAt(i);
          }
        }
      } else {
        if (barcode['controller'] != null) {
          (barcode['controller'] as TextEditingController).dispose();
        }
        boxes[boxIndex]['barcodes'].removeAt(barcodeIndex);
      }
      for (int i = 0; i < boxes[boxIndex]['barcodes'].length; i++) {
        boxes[boxIndex]['barcodes'][i]['id'] = i + 1;
      }
      _updateBoxPieces(boxIndex);
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

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      // API Check: /fetch-work-order-finish-check/{work_order_no}/{barcode}
      final url = '$barcodeCheckApi/$workOrderNo/$trimmedBarcode';
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
        final bool isFound = (data['code'] == 200 || data['msg']?.toString().toLowerCase().contains('found') == true);

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

    // Do NOT search or merge duplicate scan rows. Set pieces = 1.
    setState(() {
      boxes[boxIndex]['barcodes'][barcodeIndex]['code'] = trimmedBarcode;
      boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = true;
      boxes[boxIndex]['barcodes'][barcodeIndex]['isLoading'] = false;
      boxes[boxIndex]['barcodes'][barcodeIndex]['pieces'] = 1;
      boxes[boxIndex]['barcodes'][barcodeIndex]['ids'] = [null];

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
          if (boxes[boxIndex]['barcodes'][barcodeIndex]['controller'] != null) {
            (boxes[boxIndex]['barcodes'][barcodeIndex]['controller'] as TextEditingController).text = barcode;
          }
          // Reset validation when scanned
          boxes[boxIndex]['barcodes'][barcodeIndex]['isValidated'] = false;
          boxes[boxIndex]['barcodes'][barcodeIndex]['barcodeData'] = null;
        });
        
        // Auto-validate after scanning
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

  bool allValidated = true;

  for (var box in boxes) {
    for (var barcode in box['barcodes']) {
      final code = barcode['code'].toString().trim();

      if (code.isEmpty || barcode['isValidated'] != true) {
        allValidated = false;
        break;
      }
    }

    if (!allValidated) break;
  }

  if (!allValidated) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Please validate all barcodes before saving'),
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
                        onPressed: () {
                          setState(() {
                            currentStep = 0;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Back'),
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
                      onPressed: () {
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
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
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
                      TextButton(onPressed: _addBox, child: const Text('Add Box')),
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
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _addBox,
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

    return Card(
      key: ValueKey("box_${box['id']}"),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Box ${box['id']} (${box['pieces']} pieces)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryColor),
                ),
                if (boxes.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => _removeBox(boxIndex),
                  ),
              ],
            ),
            const Divider(height: 16),
            if (barcodes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No barcodes added to this box', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              )
            else ...(() {
              final List<Map<String, dynamic>> renderedBarcodes = [];
              final Set<String> seenValidatedCodes = {};
              
              for (int i = 0; i < barcodes.length; i++) {
                final barcode = barcodes[i];
                final code = barcode['code']?.toString().trim() ?? '';
                final isValidated = barcode['isValidated'] == true;
                
                if (code.isEmpty) {
                  renderedBarcodes.add({...barcode, 'originalIndex': i});
                } else if (isValidated) {
                  if (!seenValidatedCodes.contains(code)) {
                    seenValidatedCodes.add(code);
                    renderedBarcodes.add({...barcode, 'originalIndex': i});
                  }
                } else {
                  renderedBarcodes.add({...barcode, 'originalIndex': i});
                }
              }
              
              return renderedBarcodes.map((barcode) {
                final int originalIndex = barcode['originalIndex'];
                return _buildBarcodeEntry(boxIndex, originalIndex, barcode);
              }).toList();
            })(),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _addBarcode(boxIndex),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Barcode', style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                padding: EdgeInsets.zero,
                minimumSize: const Size(60, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodeEntry(int boxIndex, int barcodeIndex, Map<String, dynamic> barcode) {
    final isLoading = barcode['isLoading'] ?? false;
    final isValidated = barcode['isValidated'] ?? false;

    int occurrenceCount = 0;
    int totalPiecesForCode = 0;
    final currentCode = barcode['code']?.toString().trim() ?? '';
    final isValidatedCode = barcode['isValidated'] == true;

    if (currentCode.isNotEmpty && isValidatedCode) {
      for (var bar in boxes[boxIndex]['barcodes']) {
        if (bar['code']?.toString().trim() == currentCode && bar['isValidated'] == true) {
          occurrenceCount++;
          totalPiecesForCode += int.tryParse(bar['pieces']?.toString() ?? '') ?? 0;
        }
      }
    } else {
      totalPiecesForCode = int.tryParse(barcode['pieces']?.toString() ?? '') ?? 0;
    }

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
                      icon: Icon(Icons.qr_code_scanner, size: 20, color: primaryColor),
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
                  totalPiecesForCode.toString(),
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

// Barcode Scanner Page
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
  bool _hasCalledScanned = false; // Prevent multiple events firing in quick succession

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
        title: const Text('Scan Barcode', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () {
              _controller.switchCamera();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_isProcessing || _hasCalledScanned) return;
              
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final code = barcode.rawValue;
                if (code != null && code.isNotEmpty) {
                  _isProcessing = true;
                  _hasCalledScanned = true;
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
                    foregroundColor: AppTheme.primaryColor,
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