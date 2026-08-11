import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_theme.dart';
import 'app_utils.dart';
import 'api.dart';
import 'order/barcode_scanner_page.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;

class ReceiptViewPage extends StatefulWidget {
  final int receivedId;

  const ReceiptViewPage({
    super.key,
    required this.receivedId,
  });

  @override
  State<ReceiptViewPage> createState() => _ReceiptViewPageState();
}

class _ReceiptViewPageState extends State<ReceiptViewPage> {
  bool isLoading = true;
  String errorMessage = '';
  Map<String, dynamic>? mainDetails;
  List<dynamic> subList = [];
  Map<String, List<Map<String, dynamic>>> boxGroups = {};

  List<String> get sortedBoxKeys {
    final keys = boxGroups.keys.toList();
    keys.sort((a, b) {
      final numA = int.tryParse(RegExp(r'^\d+').stringMatch(a) ?? '');
      final numB = int.tryParse(RegExp(r'^\d+').stringMatch(b) ?? '');
      if (numA != null && numB != null) {
        if (numA != numB) {
          return numA.compareTo(numB);
        }
        return a.compareTo(b);
      }
      return a.compareTo(b);
    });
    return keys;
  }

  String _getProductPrefix(Map<String, dynamic> item) {
    final barcode = (item['barcode'] ?? item['work_order_rc_sub_barcode'] ?? '').toString().trim();
    final match = RegExp(r'^([A-Z]*\d+)', caseSensitive: false).firstMatch(barcode);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.toUpperCase();
    }
    final fIdx = barcode.toUpperCase().indexOf('F');
    final hIdx = barcode.toUpperCase().indexOf('H');
    int splitIdx = -1;
    if (fIdx != -1 && hIdx != -1) splitIdx = fIdx < hIdx ? fIdx : hIdx;
    else if (fIdx != -1) splitIdx = fIdx;
    else if (hIdx != -1) splitIdx = hIdx;

    if (splitIdx > 0) {
      return barcode.substring(0, splitIdx).toUpperCase();
    }
    return barcode.toUpperCase();
  }

  int _getSleevePriority(Map<String, dynamic> item) {
    final size = (item['size'] ?? item['finished_stock_size'] ?? '').toString().trim().toUpperCase();
    final barcode = (item['barcode'] ?? item['work_order_rc_sub_barcode'] ?? '').toString().trim().toUpperCase();

    // Check Size first: F... = Full (1), H... = Half (2)
    if (size.startsWith('F') || size.contains('FULL')) {
      return 1;
    }
    if (size.startsWith('H') || size.contains('HALF')) {
      return 2;
    }

    // Check Barcode: e.g. P651F... vs P651H...
    final fIdx = barcode.indexOf('F');
    final hIdx = barcode.indexOf('H');
    if (fIdx != -1 && (hIdx == -1 || fIdx < hIdx)) {
      return 1;
    }
    if (hIdx != -1 && (fIdx == -1 || hIdx < fIdx)) {
      return 2;
    }

    return 3;
  }

  int _getSizePriority(Map<String, dynamic> item) {
    final size = (item['size'] ?? item['finished_stock_size'] ?? '').toString().trim().toUpperCase();
    final barcode = (item['barcode'] ?? item['work_order_rc_sub_barcode'] ?? '').toString().trim().toUpperCase();

    final text = '$size $barcode';

    if (text.contains('/XS') || text.contains('XS') || text.contains('34/')) return 1;

    if (text.contains('/S') || text.contains(' 36/') || text.contains('S/') || barcode.endsWith('FS') || barcode.endsWith('HS') || text.endsWith(' S')) return 2;

    if (text.contains('/M') || text.contains(' 38/') || text.contains('M/') || barcode.endsWith('FM') || barcode.endsWith('HM') || text.endsWith(' M')) return 3;

    if (text.contains('/L') || text.contains(' 40/') || text.contains('L/') || barcode.endsWith('FL') || barcode.endsWith('HL') || text.endsWith(' L')) return 4;

    if (text.contains('2XL') || text.contains('XXL') || text.contains(' 44/') || barcode.endsWith('F2') || barcode.endsWith('H2') || barcode.endsWith('2XL')) return 6;

    if (text.contains('3XL') || text.contains('XXXL') || text.contains(' 46/') || barcode.endsWith('F3') || barcode.endsWith('H3') || barcode.endsWith('3XL')) return 7;

    if (text.contains('4XL') || text.contains(' 48/') || barcode.endsWith('F4') || barcode.endsWith('H4')) return 8;

    if (text.contains('5XL') || text.contains(' 50/') || barcode.endsWith('F5') || barcode.endsWith('H5')) return 9;

    if (text.contains('XL') || text.contains(' 42/') || text.contains('XL/') || barcode.endsWith('FX') || barcode.endsWith('HX') || text.endsWith(' XL')) return 5;

    final numMatch = RegExp(r'\b(34|36|38|40|42|44|46|48|50)\b').firstMatch(text);
    if (numMatch != null) {
      final num = int.tryParse(numMatch.group(1)!);
      if (num != null) {
        return (num - 34) ~/ 2 + 1;
      }
    }

    return 99;
  }

  int _compareBoxItems(Map<String, dynamic> a, Map<String, dynamic> b) {
    // Tier 1: Product Code Prefix (e.g. P651, P654, P661...)
    final prefixA = _getProductPrefix(a);
    final prefixB = _getProductPrefix(b);
    final prefixComp = prefixA.compareTo(prefixB);
    if (prefixComp != 0) return prefixComp;

    // Tier 2: Sleeve Type (Full = 1, Half = 2)
    final sleeveA = _getSleevePriority(a);
    final sleeveB = _getSleevePriority(b);
    if (sleeveA != sleeveB) return sleeveA.compareTo(sleeveB);

    // Tier 3: Garment Size Order (S -> M -> L -> XL -> 2XL -> 3XL...)
    final sizeA = _getSizePriority(a);
    final sizeB = _getSizePriority(b);
    if (sizeA != sizeB) return sizeA.compareTo(sizeB);

    // Tie-breaker: Barcode
    final barcodeA = (a['barcode'] ?? a['work_order_rc_sub_barcode'] ?? '').toString();
    final barcodeB = (b['barcode'] ?? b['work_order_rc_sub_barcode'] ?? '').toString();
    return barcodeA.compareTo(barcodeB);
  }

  @override
  void initState() {
    super.initState();
    _fetchReceiptDetails();
  }

  Future<void> _fetchReceiptDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final url = '$baseUrl/fetch-work-order-received-view-by-id/${widget.receivedId}';
      print('Fetching receipt details from: $url');

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
        Map<String, dynamic>? details;
        List<dynamic> subs = [];

        if (data is Map) {
          final rc = data['workorderrc'];
          if (rc is List && rc.isNotEmpty) {
            details = rc.first;
          } else if (rc is Map<String, dynamic>) {
            details = rc;
          }
          subs = data['workorderrcsub'] ?? [];
        }

        if (details != null) {
          // Group sub items by box number
          final Map<String, List<Map<String, dynamic>>> groups = {};
          for (var item in subs) {
            var boxVal = item['work_order_rc_sub_box']?.toString() ??
                         item['work_order_rc_sub_box_no']?.toString() ??
                         item['box_no']?.toString() ??
                         '';
            if (boxVal.trim().isEmpty) {
              boxVal = '1';
            }
            final boxKey = boxVal.trim();
            groups.putIfAbsent(boxKey, () => []).add(Map<String, dynamic>.from(item));
          }

          setState(() {
            mainDetails = details;
            subList = subs;
            boxGroups = groups;
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = 'Receipt details not found in response.';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Failed to load receipt details (Status: ${response.statusCode}).';
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching receipt details: $e');
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _generateAndDownloadPDF() async {
    final pdf = pw.Document();

    if (mainDetails == null) return;

    final details = mainDetails!;
    final factory = details['work_order_rc_factory']?.toString() ?? 'N/A';
    final brand = details['work_order_rc_brand']?.toString() ?? 'N/A';
    final boxCount = details['work_order_rc_box']?.toString() ?? '0';
    final workOrderNo = details['work_order_rc_id']?.toString() ?? details['work_order_rc_ref']?.toString() ?? 'N/A';
    final date = formatAppDate(details['work_order_rc_date']);
    final dcNo = details['work_order_rc_dc_no']?.toString() ?? 'N/A';
    final totalPcs = details['work_order_rc_pcs']?.toString() ?? '0';
    final remarks = details['work_order_rc_remarks']?.toString() ?? 'N/A';
    final ref = details['work_order_rc_ref']?.toString() ?? 'N/A';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Title
            
        

            // Box sections with repeated metadata headers
            ...sortedBoxKeys.map((boxKey) {
              final boxItems = boxGroups[boxKey] ?? [];

              // Group items
              final Map<String, Map<String, dynamic>> grouped = {};
              for (var item in boxItems) {
                final barcode = item['work_order_rc_sub_barcode']?.toString() ?? '';
                final size = item['finished_stock_size']?.toString() ?? 'N/A';
                final amount = double.tryParse(item['finished_stock_amount']?.toString() ?? '') ?? 0.0;

                final key = '$barcode|$size|$amount';
                if (!grouped.containsKey(key)) {
                  grouped[key] = {
                    'barcode': barcode,
                    'size': size,
                    'amount': amount,
                    'quantity': 1,
                  };
                } else {
                  grouped[key]!['quantity'] = (grouped[key]!['quantity'] as int) + 1;
                }
              }
              final list = grouped.values.toList();
              list.sort(_compareBoxItems);

              // Compute box totals
              int boxPcs = 0;
              double boxAmount = 0.0;
              for (var x in list) {
                final q = x['quantity'] as int;
                final a = x['amount'] as double;
                boxPcs += q;
                boxAmount += q * a;
              }

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Metadata header card layout in PDF
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Left column
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              // Factory name in bold
                              pw.Text(
                                factory,
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 6),
                              // Brand / WO No
                              pw.Text(
                                'Brand: $brand  |  WO No: $workOrderNo',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              // DC No / Boxes / Pcs
                              // pw.Text(
                              //   'DC No: $dcNo  |  Boxes: $boxCount  |  Pcs: $totalPcs',
                              //   style: const pw.TextStyle(
                              //     fontSize: 9,
                              //   ),
                              // ),
                              // if (remarks.isNotEmpty && remarks != 'N/A') ...[
                              //   pw.SizedBox(height: 4),
                              //   pw.Text(
                              //     'Remarks: $remarks',
                              //     style: pw.TextStyle(
                              //       fontSize: 9,
                              //       fontStyle: pw.FontStyle.italic,
                              //     ),
                              //   ),
                              // ],
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 16),
                        // Right column
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'Ref: $ref/$boxKey',
                              style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              'Date: $date',
                              style: const pw.TextStyle(
                                fontSize: 9,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            // Barcode widget in PDF
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.code128(),
                              data: 'RC/${widget.receivedId}/$boxKey',
                              width: 80,
                              height: 24,
                              drawText: false,
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              '$ref/$boxKey',
                              style: const pw.TextStyle(
                                fontSize: 6,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 12),

                  // Box container details
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Box header bar
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          color: PdfColors.grey200,
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Box $boxKey (Total Pcs: $boxPcs)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                              // pw.Text('Total Amount: Rs ${boxAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                            ],
                          ),
                        ),
                        // Table
                        pw.Table(
                          border: pw.TableBorder.symmetric(
                            inside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                          ),
                          children: [
                            pw.TableRow(
                              children: [
                                _buildPdfTableCell('Barcode', isHeader: true),
                                _buildPdfTableCell('Size', isHeader: true),
                                _buildPdfTableCell('Description', isHeader: true),
                                _buildPdfTableCell('Amount (Rs)', isHeader: true),
                                _buildPdfTableCell('Quantity', isHeader: true),
                              ],
                            ),
                            ...list.map((row) {
                              final barcode = row['barcode'] as String;
                              final size = row['size'] as String;
                              final description = row['description'] as String? ?? '';
                              final amount = row['amount'] as double;
                              final quantity = row['quantity'] as int;

                              return pw.TableRow(
                                children: [
                                  _buildPdfTableCell(barcode),
                                  _buildPdfTableCell(size),
                                  _buildPdfTableCell(description),
                                  _buildPdfTableCell(amount.toStringAsFixed(2)),
                                  _buildPdfTableCell(quantity.toString()),
                                ],
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 24),
                ],
              );
            }),
            // Signature section in PDF
            pw.SizedBox(height: 24),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'dc_receipt_${widget.receivedId}.pdf',
    );
  }


  pw.Widget _buildPdfTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
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
              colors: AppTheme.gradientColors,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'DC RECEIPT',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
            onPressed: () => _scanAndShowBoxDetails(context),
            tooltip: 'Scan Box Barcode',
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildReceiptContent(isDark),
    );
  }

  Widget _buildBarcode(String data, bool isDark) {
    return Container(
      width: 170, // Increased width for better scanability of longer data strings
      height: 48, // Increased height for camera focus
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: bw.BarcodeWidget(
        barcode: bw.Barcode.code128(),
        data: data,
        drawText: false,
      ),
    );
  }

  Widget _buildMetadataTable(
    bool isDark,
    String factory,
    String date,
    String dcDate,
    String brand,
    String dcNo,
    String receivedBy,
    String boxCount,
    String totalPcs,
    String remarks,
    String workOrderNo,
    String barcodeData,
    String displayText,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Factory name in bold
                    Text(
                      factory,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Brand / Work Order No
                    Text(
                      'Brand: $brand  |  WO No: $workOrderNo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.grey[300] : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'DC No: $dcNo  |  Boxes: $boxCount  |  Pcs: $totalPcs',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                      ),
                    ),
                    if (remarks.isNotEmpty && remarks != 'N/A') ...[
                      const SizedBox(height: 6),
                      Text(
                        'Remarks: $remarks',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.grey[450] : const Color(0xFF64748B),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right Column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Ref / Date
                  Text(
                    'Ref: $displayText',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Date: $date',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Visual Barcode for Reference Number
                  _buildBarcode(barcodeData, isDark),
                  const SizedBox(height: 4),
                  Text(
                    displayText,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[450] : const Color(0xFF64748B),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptContent(bool isDark) {
    if (mainDetails == null) return const SizedBox.shrink();

    final details = mainDetails!;

    final factory = details['work_order_rc_factory']?.toString() ?? 'N/A';
    final brand = details['work_order_rc_brand']?.toString() ?? 'N/A';
    final boxCount = details['work_order_rc_box']?.toString() ?? '0';
    final workOrderNo = details['work_order_rc_id']?.toString() ?? details['work_order_rc_ref']?.toString() ?? 'N/A';
    final date = formatAppDate(details['work_order_rc_date']);
    final dcNo = details['work_order_rc_dc_no']?.toString() ?? 'N/A';
    final totalPcs = details['work_order_rc_pcs']?.toString() ?? '0';
    final remarks = details['work_order_rc_remarks']?.toString() ?? 'N/A';
    final dcDate = formatAppDate(details['work_order_rc_dc_date']);
    final receivedBy = details['work_order_rc_received_by']?.toString() ?? 'N/A';
    final ref = details['work_order_rc_ref']?.toString() ?? 'N/A';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // All Received tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  'All Received',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              // Download PDF Button
              ElevatedButton.icon(
                onPressed: _generateAndDownloadPDF,
                icon: const Icon(Icons.download, size: 16),
                label: const Text(
                  'Download PDF',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Repeated Box sections containing metadata table + box list details
          ...sortedBoxKeys.map((boxKey) {
            final boxItems = boxGroups[boxKey] ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetadataTable(
                  isDark,
                  factory,
                  date,
                  dcDate,
                  brand,
                  dcNo,
                  receivedBy,
                  boxCount,
                  totalPcs,
                  remarks,
                  workOrderNo,
                  'RC/${widget.receivedId}/$boxKey',
                  '$ref/$boxKey',
                ),
                const SizedBox(height: 12),
                _buildBoxSection(boxKey, boxItems, isDark),
                const SizedBox(height: 24),
              ],
            );
          }),

          // Space for signatures at the bottom of the receipt view
          
        ],
      ),
    );
  }


  Widget _buildBoxSection(String boxNo, List<Map<String, dynamic>> items, bool isDark) {
    // Group items inside this box by barcode, size, amount to count quantity
    final Map<String, Map<String, dynamic>> grouped = {};
    for (var item in items) {
      final barcode = item['work_order_rc_sub_barcode']?.toString() ?? '';
      final size = item['finished_stock_size']?.toString() ?? 'N/A';
      final amount = double.tryParse(item['finished_stock_amount']?.toString() ?? '') ?? 0.0;

      final key = '$barcode|$size|$amount';
      if (!grouped.containsKey(key)) {
        grouped[key] = {
          'barcode': barcode,
          'size': size,
          'amount': amount,
          'quantity': 1,
        };
      } else {
        grouped[key]!['quantity'] = (grouped[key]!['quantity'] as int) + 1;
      }
    }

    final list = grouped.values.toList();
    list.sort(_compareBoxItems);

    // Compute totals for this box
    int boxPcs = 0;
    double boxAmount = 0.0;
    for (var x in list) {
      final q = x['quantity'] as int;
      final a = x['amount'] as double;
      boxPcs += q;
      boxAmount += q * a;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Box header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
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
                      Icons.check_box_outline_blank,
                      size: 18,
                      color: isDark ? Colors.grey[400] : const Color(0xFF475569),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Box $boxNo (Total Pcs: $boxPcs)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                // Row(
                //   children: [
                //     Text(
                //       'Total Amount: ₹${boxAmount.toStringAsFixed(2)}',
                //       style: TextStyle(
                //         fontWeight: FontWeight.w800,
                //         fontSize: 13,
                //         color: isDark ? Colors.white : const Color(0xFF0F172A),
                //       ),
                //     ),
                //     const SizedBox(width: 8),
                //     Icon(
                //       Icons.menu,
                //       size: 16,
                //       color: isDark ? Colors.grey[400] : const Color(0xFF475569),
                //     ),
                //   ],
                // ),
              ],
            ),
          ),

          // Box table
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2.0),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1.0),
            },
            border: TableBorder.symmetric(
              inside: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
            children: [
              // Table Headers
              TableRow(
                children: [
                  _buildTableCell('Barcode', isDark, isHeader: true),
                  _buildTableCell('Size', isDark, isHeader: true),
                  _buildTableCell('Amount (₹)', isDark, isHeader: true),
                  _buildTableCell('Quantity', isDark, isHeader: true),
                ],
              ),
              // Table Body Rows
              ...list.map((row) {
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
        ],
      ),
    );
  }

  Future<void> _scanAndShowBoxDetails(BuildContext context) async {
    final List<String>? barcodes = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerPage()),
    );

    if (barcodes != null && barcodes.isNotEmpty) {
      final scannedCode = barcodes.first.trim();
      _handleScannedBoxBarcode(scannedCode);
    }
  }

  void _handleScannedBoxBarcode(String scannedCode) {
    final cleanScanned = scannedCode.trim().toLowerCase();
    final parts = cleanScanned.split('/');
    String? matchedBoxKey;

    if (parts.length >= 3 && parts[0] == 'rc') {
      final scannedId = parts[1].trim();
      if (scannedId == widget.receivedId.toString()) {
        final scannedBox = parts[2].trim();
        for (final boxKey in sortedBoxKeys) {
          if (scannedBox == boxKey.toLowerCase()) {
            matchedBoxKey = boxKey;
            break;
          }
        }
      }
    } else if (parts.length >= 2) {
      final scannedBoxKey = parts.last.trim();
      final scannedRef = parts.sublist(0, parts.length - 1).join('/').trim();
      
      final normalizedScannedRef = formatWorkOrderRef(scannedRef).toLowerCase();
      final normalizedRcRef = formatWorkOrderRef(mainDetails?['work_order_rc_ref']?.toString()).toLowerCase();

      if (normalizedScannedRef == normalizedRcRef) {
        for (final boxKey in sortedBoxKeys) {
          if (scannedBoxKey == boxKey.toLowerCase()) {
            matchedBoxKey = boxKey;
            break;
          }
        }
      }
    }

    if (matchedBoxKey == null) {
      // Fallback: check if matches boxKey directly or ends with /$boxKey
      for (final boxKey in sortedBoxKeys) {
        if (cleanScanned == boxKey.toLowerCase() || cleanScanned.endsWith('/$boxKey')) {
          matchedBoxKey = boxKey;
          break;
        }
      }
    }

    if (matchedBoxKey != null) {
      _showBoxDetailsDialog(matchedBoxKey);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Matching Box'),
          content: Text('No box found matching the barcode "$scannedCode".'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showBoxDetailsDialog(String boxKey) {
    final boxItems = boxGroups[boxKey] ?? [];

    final Map<String, Map<String, dynamic>> grouped = {};
    for (var item in boxItems) {
      final barcode = item['work_order_rc_sub_barcode']?.toString() ?? '';
      final size = item['finished_stock_size']?.toString() ?? 'N/A';
      final amount = double.tryParse(item['finished_stock_amount']?.toString() ?? '') ?? 0.0;

      final key = '$barcode|$size|$amount';
      if (!grouped.containsKey(key)) {
        grouped[key] = {
          'barcode': barcode,
          'size': size,
          'amount': amount,
          'quantity': 1,
        };
      } else {
        grouped[key]!['quantity'] = (grouped[key]!['quantity'] as int) + 1;
      }
    }

    final list = grouped.values.toList();
    list.sort(_compareBoxItems);

    int boxPcs = 0;
    double boxAmount = 0.0;
    for (var x in list) {
      final q = x['quantity'] as int;
      final a = x['amount'] as double;
      boxPcs += q;
      boxAmount += q * a;
    }

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
            constraints: const BoxConstraints(maxHeight: 500, maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title header
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
                      Text(
                        'Box $boxKey Details',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
                // Summary bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Pcs: $boxPcs',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? Colors.grey[300] : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Amount: ₹${boxAmount.toStringAsFixed(2)}',
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
                        1: FlexColumnWidth(1.5),
                        2: FlexColumnWidth(1.5),
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
                        ...list.map((row) {
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
}
