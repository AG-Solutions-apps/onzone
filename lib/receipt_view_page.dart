import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_theme.dart';
import 'api.dart';

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
            final boxKey = item['work_order_rc_sub_box']?.toString() ?? '1';
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
    final date = details['work_order_rc_date']?.toString() ?? 'N/A';
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
            ...boxGroups.keys.map((boxKey) {
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
                              'Ref: $ref',
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
                              data: ref,
                              width: 80,
                              height: 24,
                              drawText: false,
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              ref,
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
                              pw.Text('Box (Total Pcs: $boxPcs)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
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
    final hash = data.hashCode.abs();
    final list = <int>[];
    int temp = hash;
    for (int i = 0; i < 18; i++) {
      list.add((temp % 4) + 1);
      temp = temp ~/ 3 + i;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: list.map((w) => Container(
        width: w.toDouble() * 1.5,
        height: 28,
        color: isDark ? Colors.white : Colors.black,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
      )).toList(),
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
    String ref,
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
                    'Ref: $ref',
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
                  _buildBarcode(ref, isDark),
                  const SizedBox(height: 4),
                  Text(
                    ref,
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
    final date = details['work_order_rc_date']?.toString() ?? 'N/A';
    final dcNo = details['work_order_rc_dc_no']?.toString() ?? 'N/A';
    final totalPcs = details['work_order_rc_pcs']?.toString() ?? '0';
    final remarks = details['work_order_rc_remarks']?.toString() ?? 'N/A';
    final dcDate = details['work_order_rc_dc_date']?.toString() ?? 'N/A';
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
          ...boxGroups.keys.map((boxKey) {
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
                  ref,
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
                      'Box (Total Pcs: $boxPcs)',
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
