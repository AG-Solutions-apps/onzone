import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';

import 'api.dart';

// ─────────────────────────────────────────────────────────────
// COMPANY CONSTANTS
// ─────────────────────────────────────────────────────────────
const String kCompanyName = 'ONZONE CLOTHING CO.';
const String kCompanyAddress =
    '# 19, Parekh Square, 3rd Cross, H. Siddaiah Road, Bangalore - 560 027.  Phone : 080-41248938.  Mob.: 99160 82518';

const List<String> kTerms = [
  'Order once placed cannot be cancelled.',
  'Our responsibility ceases when the goods leave our godown.',
  'Subject to stock. Disputes if any should be settled in Bangalore Court Only.',
  'Verbal commitments shall be invalid until and unless written on the order sheet.',
  'Interest will be charged at the rate of 24% per annum after the due date.',
];

// ─────────────────────────────────────────────────────────────
// SIZE SETS — a row shows ONLY the set matching its kind
// ─────────────────────────────────────────────────────────────
const List<String> kPantSizes = [
  '28', '30', '32', '34', '36', '38', '40', '42', '44',
];

// [alpha, number]  ->  rendered as "S" over "36".
// Shared by full shirts and half shirts (half sizes arrive as "H-S-36").
const List<List<String>> kShirtSizes = [
  ['S', '36'],
  ['M', '38'],
  ['L', '40'],
  ['XL', '42'],
  ['2XL', '44'],
  ['3XL', '46'],
  ['4XL', '48'],
  ['5XL', '50'],
];

/// What kind of row this is. Pant rows print under their own header;
/// shirt and half-shirt rows SHARE one header, since their columns
/// are identical.
enum _Kind { pant, shirt, shirtHalf }

/// The band above the size columns — identical for every table.
const String _sizeBandTitle = 'SIZES';

// ─────────────────────────────────────────────────────────────
// PALETTE
// ─────────────────────────────────────────────────────────────
final PdfColor _kRed = PdfColor.fromInt(0xFFA31D1D);
final PdfColor _kBlue = PdfColor.fromInt(0xFF1F5FA8);
final PdfColor _kInk = PdfColor.fromInt(0xFF1A1A1A);
final PdfColor _kGrey = PdfColor.fromInt(0xFF808080);
final PdfColor _kBorder = PdfColor.fromInt(0xFF3C3C3C);

// ─────────────────────────────────────────────────────────────
// GEOMETRY
// ─────────────────────────────────────────────────────────────
const double _tableW = 546;
const double _wQty = 36;
const double _wRate = 42;
const double _wSizeArea = 252; // shared by every size set
const double _wStyle = _tableW - _wSizeArea - _wQty - _wRate; // 216

const double _rowH = 24; // minimum / blank row height
const double _headTopH = 12;
const double _headSubH = 22;
const double _headH = _headTopH + _headSubH;
const double _totalH = 22;

// Style-code cell text metrics — used to work out how many lines a
// long label needs, and therefore how tall its row must be.
const double _styleFontSize = 8;
const double _styleLineH = 10; // line box height at that size
const double _stylePadH = 12; // 8 left + 4 right
const int _styleMaxLines = 6;
/// Rough average glyph width for Helvetica-Bold at [_styleFontSize].
const double _styleCharW = _styleFontSize * 0.52;

const double _footerH = 64;
const double _footerTermsW = 240;
const double _footerOrderedW = 160;

// Line 1 — fixed right block so a 5-digit order number never overflows.
const double _dateFieldW = 58; // underlined date value
const double _orderChipW = 112; // "ORDER NUMBER" + value box
const double _line1RightW = 26 + 5 + _dateFieldW + 12 + _orderChipW; // 213
const double _retailerNameMaxW = 150; // name truncates here, dots take the rest

// Masthead + info block — every element has a fixed height so the
// remaining table space can be computed exactly.
const double _hTitle = 26;
const double _hAddress = 10;
const double _hRule = 1.2;
const double _hLine1 = 22;
const double _hLine2 = 16;
const double _kHeaderH =
    _hTitle + 4 + _hAddress + 6 + _hRule + 10 + _hLine1 + 6 + _hLine2 + 8;

const double _pageMarginV = 20;
const double _pageMarginH = 24;

final double _contentH = PdfPageFormat.a4.height - _pageMarginV * 2;
final double _tableSpaceH = _contentH - _kHeaderH - _totalH - _footerH;

/// Number of size columns for a kind.
int _sizeCount(_Kind k) =>
    k == _Kind.pant ? kPantSizes.length : kShirtSizes.length;

/// Per-column widths that always sum to exactly [_wSizeArea].
List<double> _colWidths(int n) {
  final list = List<double>.filled(n, _wSizeArea / n);
  double used = 0;
  for (int i = 0; i < n - 1; i++) {
    used += list[i];
  }
  list[n - 1] = _wSizeArea - used;
  return list;
}

/// How tall a row must be for its style label to print in full.
double _rowHeightFor(String label) {
  final double usable = _wStyle - _stylePadH;
  final int perLine = math.max(1, (usable / _styleCharW).floor());
  final int lines =
      math.max(1, math.min(_styleMaxLines, (label.length / perLine).ceil()));
  if (lines <= 1) return _rowH;
  return math.max(_rowH, lines * _styleLineH + 8);
}

// ─────────────────────────────────────────────────────────────
// PUBLIC ENTRY POINT
// ─────────────────────────────────────────────────────────────
Future<void> downloadOrderPdf(BuildContext context, dynamic orderId) async {
  try {
    final data = await _fetchOrder(orderId);
    if (data == null) {
      debugPrint('PDF: could not load order details for $orderId');
      return;
    }

    final Uint8List bytes = await _buildPdf(data);
    final ref = (data['fair_order_ref'] ?? 'ORDER').toString();
    final fileName =
        'ONZONE_${ref.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.pdf';

    final file = await _savePdf(bytes, fileName);

    if (file != null) {
      await OpenFilex.open(file.path);
    } else {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  } catch (e) {
    debugPrint('PDF error: $e');
  }
}

// ─────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────
Future<Map<String, dynamic>?> _fetchOrder(dynamic id) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');

  final res = await http.get(
    Uri.parse('$baseUrl/fairOrderFormViewById/$id'),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
  );

  if (res.statusCode != 200) return null;
  final decoded = jsonDecode(res.body);
  if (decoded is Map && decoded['data'] is Map) {
    return Map<String, dynamic>.from(decoded['data']);
  }
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return null;
}

Future<File?> _savePdf(Uint8List bytes, String name) async {
  try {
    Directory dir;
    if (Platform.isAndroid) {
      final dl = Directory('/storage/emulated/0/Download');
      dir = await dl.exists() ? dl : (await getApplicationDocumentsDirectory());
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  } catch (_) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      return f;
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// SIZE RESOLUTION  (token -> column index within its own set)
// ─────────────────────────────────────────────────────────────
String _normAlpha(String s) => s
    .toUpperCase()
    .replaceAll(' ', '')
    .replaceAll('XXXXXL', '5XL')
    .replaceAll('XXXXL', '4XL')
    .replaceAll('XXXL', '3XL')
    .replaceAll('XXL', '2XL');

/// Half sizes come through as "H-S-36", "H-2XL-44", ...
bool _isHalfToken(String token) => _normAlpha(token).startsWith('H-');

/// Drops the leading "H-" so the remainder resolves like a normal size.
String _stripHalf(String token) {
  final up = _normAlpha(token);
  return up.startsWith('H-') ? up.substring(2) : up;
}

/// "34" / "34 " / "P-34"  ->  index in [kPantSizes], or -1
int _pantIndex(String token) {
  final digits = token.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return -1;
  return kPantSizes.indexOf(digits);
}

/// "3XL-46" / "XXXL-46" / "46" / "3XL"  ->  index in [kShirtSizes], or -1
/// Also handles "H-3XL-46" by stripping the half prefix first.
int _shirtIndex(String token) {
  final up = _stripHalf(token);
  final parts = up.split('-');
  final String alpha = parts.length == 2 ? parts[0] : up;
  final String num =
      parts.length == 2 ? parts[1] : up.replaceAll(RegExp(r'[^0-9]'), '');

  for (int i = 0; i < kShirtSizes.length; i++) {
    if (kShirtSizes[i][0] == alpha) return i;
    if (num.isNotEmpty && kShirtSizes[i][1] == num) return i;
  }
  return -1;
}

/// Column index -> plain size label used in the half-size note.
///   3  ->  "XL-42"
String _halfLabel(int col) => '${kShirtSizes[col][0]}-${kShirtSizes[col][1]}';

// ─────────────────────────────────────────────────────────────
// ROW MODEL
//   The API sends PRE-GROUPED records: each entry in "subs" carries
//   a main-barcode list, a sub-barcode list, a dress type, a size
//   list and a quantity.
//
//   A record splits along TWO axes:
//
//   1. BARCODE
//      - Plain mains (no sub-barcodes) share ONE line, comma joined.
//      - EACH main that carries sub-barcodes gets its OWN line, with
//        its sub numbers/names inside the brackets:
//          mains SOKTAS,SATIN,GEMS + subs SOKTAS1,SOKTAS2,SATIN1,GEMS4
//            ->  SOKTAS (1, 2)
//                SATIN (1)
//                GEMS (4)
//        A long bracket list WRAPS onto extra lines and the row grows
//        taller — nothing is ever clipped.
//
//   2. SIZE SET — a shirt record can hold full sizes ("S-36") and
//      half sizes ("H-S-36"); each set gets its own rows, but BOTH
//      print under the SAME header since the columns are identical.
//      Which sizes are the half ones is spelled out on the TOTAL row.
//
//   MATHS — a line carries a number of UNITS: the count of plain
//   barcodes on it, or the count of entries inside its bracket.
//     size cell   = the quantity chosen for that record
//     line total  = units × quantity × number of selected sizes
// ─────────────────────────────────────────────────────────────
class _Row {
  final _Kind kind;
  final List<int> cols; // every size cell filled on this line
  final int qty; // quantity per barcode per size
  final int units; // barcodes (or bracket entries) on this line
  final String label; // "9701, 9702"  /  "SOKTAS (1, 2, 3)"

  _Row({
    required this.kind,
    required this.cols,
    required this.qty,
    required this.units,
    required this.label,
  });

  /// Line total = barcodes × quantity × number of selected sizes.
  int get total => units * qty * cols.length;

  /// Tall enough for the whole style label to show.
  double get height => _rowHeightFor(label);
}

/// One printed barcode label plus how many barcodes it stands for.
class _Label {
  final String text;
  final int units;

  const _Label(this.text, this.units);
}

bool _isShirtType(dynamic v) =>
    (v ?? '').toString().trim().toUpperCase().startsWith('S');

/// Splits a comma separated field into clean, de-duplicated parts.
List<String> _splitList(dynamic raw) {
  if (raw == null) return const [];
  final out = <String>[];
  for (final p in raw.toString().split(',')) {
    final v = p.trim();
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out;
}

/// Real sub number = whatever the sub-barcode carries beyond its main.
///   main 70702, sub 707023    ->  "3"
///   main SOKTAS, sub SOKTAS10 ->  "10"
String _subNumberOf(String main, String sub) {
  final m = main.trim();
  final s = sub.trim();
  if (s.isEmpty || m.isEmpty || s == m) return '';
  if (s.startsWith(m) && s.length > m.length) {
    final suffix = s.substring(m.length);
    final stripped = suffix.replaceFirst(RegExp(r'^[^0-9A-Za-z]+'), '');
    return stripped.isEmpty ? suffix : stripped;
  }
  return '';
}

/// Numbers first (numerically), then names (alphabetically).
int _bracketCompare(String a, String b) {
  final ai = int.tryParse(a);
  final bi = int.tryParse(b);
  if (ai != null && bi != null) return ai.compareTo(bi);
  if (ai != null) return -1;
  if (bi != null) return 1;
  return a.toUpperCase().compareTo(b.toUpperCase());
}

/// One record's barcodes -> the lines it should print as.
///   [ "9701, 9702" ]                          (plain mains together)
///   [ "SOKTAS (1, 2)", "SATIN (1)", ... ]     (one line per style)
List<_Label> _splitLabels(List<String> mains, List<String> subs) {
  // map every sub back to the main it belongs to
  final Map<String, List<String>> bySubMain = {};
  final unmatched = <String>[]; // subs with no resolvable main prefix

  for (final sub in subs) {
    // longest matching main wins, so SOKTAS beats SOK when both exist
    String best = '';
    for (final m in mains) {
      if (sub.startsWith(m) && sub.length > m.length && m.length > best.length) {
        best = m;
      }
    }
    if (best.isEmpty) {
      if (!unmatched.contains(sub)) unmatched.add(sub);
      continue;
    }
    final n = _subNumberOf(best, sub);
    if (n.isEmpty) continue;
    bySubMain.putIfAbsent(best, () => []);
    if (!bySubMain[best]!.contains(n)) bySubMain[best]!.add(n);
  }

  // a sub with no resolvable main still belongs to this record
  if (unmatched.isNotEmpty && mains.isNotEmpty) {
    final host = bySubMain.isNotEmpty ? bySubMain.keys.first : mains.first;
    bySubMain.putIfAbsent(host, () => []);
    for (final u in unmatched) {
      if (!bySubMain[host]!.contains(u)) bySubMain[host]!.add(u);
    }
    unmatched.clear();
  }

  final out = <_Label>[];

  // 1) every main WITHOUT subs shares a single comma-joined line
  final plain = <String>[];
  for (final m in mains) {
    final nos = bySubMain[m];
    if (nos == null || nos.isEmpty) plain.add(m);
  }
  if (plain.isNotEmpty) out.add(_Label(plain.join(', '), plain.length));

  // 2) every main WITH subs gets a line of its own
  for (final m in mains) {
    final nos = bySubMain[m];
    if (nos == null || nos.isEmpty) continue;
    nos.sort(_bracketCompare);
    out.add(_Label('$m (${nos.join(', ')})', nos.length));
  }

  // 3) no mains at all — the subs stand on their own
  if (mains.isEmpty && unmatched.isNotEmpty) {
    unmatched.sort(_bracketCompare);
    out.add(_Label(unmatched.join(', '), unmatched.length));
  }

  return out;
}

List<_Row> _buildRows(List subs) {
  final rows = <_Row>[];

  for (final s in subs) {
    if (s is! Map) continue;

    final mains = _splitList(s['fair_order_sub_barcode_main']);
    final subList = _splitList(s['fair_order_sub_barcode']);
    if (mains.isEmpty && subList.isEmpty) continue;

    final shirt = _isShirtType(s['fair_order_sub_dress_type']);
    final qty =
        int.tryParse((s['fair_order_sub_quantity'] ?? '1').toString()) ?? 1;

    // selected size cells, split by kind
    final Map<_Kind, List<int>> byKind = {};
    for (final t in _splitList(s['fair_order_sub_dress_size'])) {
      final _Kind kind;
      final int col;

      if (!shirt) {
        kind = _Kind.pant;
        col = _pantIndex(t);
      } else if (_isHalfToken(t)) {
        kind = _Kind.shirtHalf;
        col = _shirtIndex(t);
      } else {
        kind = _Kind.shirt;
        col = _shirtIndex(t);
      }

      if (col < 0) continue; // size outside the printed set
      byKind.putIfAbsent(kind, () => []);
      if (!byKind[kind]!.contains(col)) byKind[kind]!.add(col);
    }
    if (byKind.isEmpty) continue; // nothing printable on this record

    final labels = _splitLabels(mains, subList);

    // stable kind order: pant, shirt, shirt half
    for (final kind in [_Kind.pant, _Kind.shirt, _Kind.shirtHalf]) {
      final cols = byKind[kind];
      if (cols == null || cols.isEmpty) continue;
      cols.sort();

      for (final label in labels) {
        if (label.text.isEmpty || label.units == 0) continue;
        rows.add(_Row(
          kind: kind,
          cols: List<int>.from(cols),
          qty: qty,
          units: label.units,
          label: label.text,
        ));
      }
    }
  }

  return rows;
}

/// Every half size used anywhere in the order, in canonical order:
///   "Half Sizes - S-36, M-38"   — empty when no half sizes were selected.
String _halfSizeNote(List<_Row> rows) {
  final used = <int>{};
  for (final r in rows) {
    if (r.kind == _Kind.shirtHalf) used.addAll(r.cols);
  }
  if (used.isEmpty) return '';
  final cols = used.toList()..sort();
  return 'Half Sizes - ${cols.map(_halfLabel).join(', ')}';
}

// ─────────────────────────────────────────────────────────────
// FORMATTERS
// ─────────────────────────────────────────────────────────────
String _fmtDate(dynamic raw) {
  if (raw == null) return '';
  final s = raw.toString();
  if (s.length < 10) return s;
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year.toString().substring(2)}';
}

// ─────────────────────────────────────────────────────────────
// SHARED DECORATIONS
// ─────────────────────────────────────────────────────────────
pw.BoxDecoration get _cell =>
    pw.BoxDecoration(border: pw.Border.all(width: 0.6, color: _kBorder));

pw.Widget _dots({double fs = 8}) => pw.Text(
      '.' * 200,
      maxLines: 1,
      style: pw.TextStyle(fontSize: fs, color: _kGrey, letterSpacing: 1.2),
    );

pw.Widget _kv(String label, String value,
        {PdfColor? valueColor, bool boldValue = false, double fs = 8.5}) =>
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: fs, color: _kInk)),
        pw.SizedBox(width: 3),
        pw.Expanded(
          child: pw.Text(value,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: fs,
                color: valueColor ?? _kInk,
                fontWeight:
                    boldValue ? pw.FontWeight.bold : pw.FontWeight.normal,
              )),
        ),
      ],
    );

// ── MASTHEAD + INFO BLOCK ────────────────────────────────────
List<pw.Widget> _headerWidgets(Map<String, dynamic> d, pw.Font titleFont) => [
      pw.SizedBox(
        height: _hTitle,
        width: _tableW,
        child: pw.Center(
          child: pw.Text(
            kCompanyName,
            style: pw.TextStyle(font: titleFont, fontSize: 21, color: _kRed),
          ),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.SizedBox(
        height: _hAddress,
        width: _tableW,
        child: pw.Center(
          child: pw.Text(kCompanyAddress,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 6.5)),
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Container(width: _tableW, height: _hRule, color: _kRed),
      pw.SizedBox(height: 10),

      // ── LINE 1 : TO / DATE / ORDER NUMBER ─────
      pw.SizedBox(
        width: _tableW,
        height: _hLine1,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // LEFT — flexes, dotted leader absorbs whatever is left
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('To, M/s', style: const pw.TextStyle(fontSize: 8.5)),
                  pw.SizedBox(width: 6),
                  pw.ConstrainedBox(
                    constraints:
                        const pw.BoxConstraints(maxWidth: _retailerNameMaxW),
                    child: pw.Text(
                        (d['fair_order_retailer'] ?? '').toString(),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Expanded(child: _dots()),
                  pw.SizedBox(width: 10),
                ],
              ),
            ),
            // RIGHT — fixed width, never squeezed
            pw.SizedBox(
              width: _line1RightW,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(
                    width: 26,
                    child: pw.Text('Date.',
                        style: const pw.TextStyle(fontSize: 8.5)),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Container(
                    width: _dateFieldW,
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                          bottom: pw.BorderSide(width: 0.6, color: _kInk)),
                    ),
                    child: pw.Text(_fmtDate(d['fair_order_date']),
                        maxLines: 1,
                        style: pw.TextStyle(
                            fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Container(
                    width: _orderChipW,
                    height: 20,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.6, color: _kRed),
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('ORDER NUMBER',
                            style: const pw.TextStyle(fontSize: 6)),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: pw.Text(
                              (d['fair_order_no'] ?? d['id'] ?? '').toString(),
                              maxLines: 1,
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _kRed)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 6),

      // ── LINE 2 : GSTIN / MOBILE / DELIVERY ────
      pw.SizedBox(
        width: _tableW,
        height: _hLine2,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(
              width: 186,
              child:
                  _kv('GSTIN. :', (d['fair_order_gst_no'] ?? '').toString()),
            ),
            pw.SizedBox(
              width: 190,
              child: _kv('Mobile Number :',
                  (d['fair_order_retailer_mobile'] ?? '').toString(),
                  valueColor: _kBlue),
            ),
            pw.Expanded(
              child: _kv('Date of Delivery :',
                  _fmtDate(d['fair_order_delivery_date']),
                  boldValue: true),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
    ];

// ── TABLE HEADER (size columns follow the kind) ──────────────
pw.Widget _tableHeader(_Kind kind) {
  final bool pant = kind == _Kind.pant;
  final int n = _sizeCount(kind);
  final widths = _colWidths(n);

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: _wStyle,
        height: _headH,
        alignment: pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.only(left: 8),
        decoration: _cell,
        child: pw.Text('Style Code / Particulars',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: _wSizeArea,
            height: _headTopH,
            alignment: pw.Alignment.center,
            decoration: _cell,
            child: pw.Text(_sizeBandTitle,
                style: pw.TextStyle(
                    fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: List.generate(
              n,
              (i) => pw.Container(
                width: widths[i],
                height: _headSubH,
                alignment: pw.Alignment.center,
                decoration: _cell,
                child: pant
                    ? pw.Text(kPantSizes[i],
                        style: pw.TextStyle(
                            fontSize: 7.5, fontWeight: pw.FontWeight.bold))
                    : pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(kShirtSizes[i][0],
                              style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 1),
                          pw.Text(kShirtSizes[i][1],
                              style:
                                  pw.TextStyle(fontSize: 5.5, color: _kGrey)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
      pw.Container(
        width: _wQty,
        height: _headH,
        alignment: pw.Alignment.center,
        decoration: _cell,
        child: pw.Text('Qty.',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Container(
        width: _wRate,
        height: _headH,
        alignment: pw.Alignment.center,
        decoration: _cell,
        child: pw.Text('Rate',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ),
    ],
  );
}

// ── ITEM ROW ─────────────────────────────────────────────────
//   The row is as tall as its style label needs; every cell in it
//   matches that height so the grid stays square.
pw.Widget _itemRow(_Row r) {
  final int n = _sizeCount(r.kind);
  final widths = _colWidths(n);
  final double h = r.height;

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: _wStyle,
        height: h,
        alignment: pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3)
            .copyWith(left: 8),
        decoration: _cell,
        child: pw.Text(r.label,
            maxLines: _styleMaxLines,
            softWrap: true,
            style: pw.TextStyle(
                fontSize: _styleFontSize,
                lineSpacing: 1.2,
                fontWeight: pw.FontWeight.bold)),
      ),
      ...List.generate(
        n,
        (i) => pw.Container(
          width: widths[i],
          height: h,
          alignment: pw.Alignment.center,
          decoration: _cell,
          child: pw.Text(r.cols.contains(i) ? '${r.qty}' : '',
              style: const pw.TextStyle(fontSize: 8)),
        ),
      ),
      pw.Container(
        width: _wQty,
        height: h,
        alignment: pw.Alignment.center,
        decoration: _cell,
        child: pw.Text('${r.total}',
            style:
                pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
      ),
      // Rate — intentionally left blank
      pw.Container(width: _wRate, height: h, decoration: _cell),
    ],
  );
}

// ── ELASTIC BLANK GRID ───────────────────────────────────────
//   Fills every remaining point of vertical space with evenly
//   divided empty rows, so the table always meets the terms block.
pw.Widget _fillerGrid(int sizeCols) => pw.CustomPaint(
      size: PdfPoint(_tableW, 0),
      painter: (canvas, size) {
        final double w = size.x;
        final double h = size.y;
        if (h <= 0.5 || w <= 0) return;

        canvas
          ..setStrokeColor(_kBorder)
          ..setLineWidth(0.6);

        // outer frame
        canvas
          ..drawRect(0, 0, w, h)
          ..strokePath();

        // horizontal dividers — as many whole rows as fit, spread evenly
        final int n = (h / _rowH).floor().clamp(1, 200);
        final double rh = h / n;
        for (int i = 1; i < n; i++) {
          canvas
            ..moveTo(0, i * rh)
            ..lineTo(w, i * rh);
        }

        // vertical dividers — same column stops as the header above
        final widths = _colWidths(sizeCols);
        double x = _wStyle;
        canvas
          ..moveTo(x, 0)
          ..lineTo(x, h);
        for (int i = 0; i < sizeCols; i++) {
          x += widths[i];
          canvas
            ..moveTo(x, 0)
            ..lineTo(x, h);
        }
        x += _wQty;
        canvas
          ..moveTo(x, 0)
          ..lineTo(x, h);

        canvas.strokePath();
      },
    );

// ── TOTAL ROW ────────────────────────────────────────────────
//   Left of "TOTAL QUANTITY:" the chosen half sizes are listed,
//   since the half rows share the full-size column labels.
pw.Widget _totalRow(int total, String halfNote) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: _wStyle + _wSizeArea,
          height: _totalH,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8),
          decoration: _cell,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Text(
                  halfNote,
                  maxLines: 1,
                  style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _kInk),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text('TOTAL QUANTITY:',
                  style: pw.TextStyle(
                      fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.Container(
          width: _wQty,
          height: _totalH,
          alignment: pw.Alignment.center,
          decoration: _cell,
          child: pw.Text('$total',
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: _kRed)),
        ),
        pw.Container(width: _wRate, height: _totalH, decoration: _cell),
      ],
    );

// ── FOOTER : TERMS / ORDERED BY / SIGNATURE ──────────────────
pw.Widget _footerBlock(Map<String, dynamic> d, pw.Font italic) => pw.Container(
      width: _tableW,
      height: _footerH,
      decoration: _cell,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // TERMS
          pw.Container(
            width: _footerTermsW,
            height: _footerH,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: pw.BoxDecoration(
              border:
                  pw.Border(right: pw.BorderSide(width: 0.6, color: _kBorder)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('TERMS & CONDITIONS :',
                    style: pw.TextStyle(
                      fontSize: 5.8,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline,
                    )),
                pw.SizedBox(height: 2),
                ...List.generate(
                  kTerms.length,
                  (i) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 1),
                    child: pw.Text('${i + 1}. ${kTerms[i]}',
                        maxLines: 2, style: const pw.TextStyle(fontSize: 5.2)),
                  ),
                ),
              ],
            ),
          ),
          // ORDERED BY
          pw.Container(
            width: _footerOrderedW,
            height: _footerH,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: pw.BoxDecoration(
              border:
                  pw.Border(right: pw.BorderSide(width: 0.6, color: _kBorder)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('Ordered by :',
                    style: pw.TextStyle(
                        fontSize: 6, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 36),
                _dots(fs: 6),
                pw.SizedBox(height: 1),
                pw.Text((d['created_by'] ?? '').toString(),
                    maxLines: 1,
                    style: pw.TextStyle(fontSize: 5.5, color: _kGrey)),
              ],
            ),
          ),
          // FOR : COMPANY
          pw.Container(
            width: _tableW - _footerTermsW - _footerOrderedW,
            height: _footerH,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('For : $kCompanyName',
                    maxLines: 1,
                    style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                        color: _kRed)),
                pw.SizedBox(height: 38),
                pw.Text('Authorized Signature',
                    style: pw.TextStyle(
                        font: italic, fontSize: 5.5, color: _kGrey)),
              ],
            ),
          ),
        ],
      ),
    );

// ─────────────────────────────────────────────────────────────
// PDF BUILD
// ─────────────────────────────────────────────────────────────
Future<Uint8List> _buildPdf(Map<String, dynamic> d) async {
  final doc = pw.Document();
  final subs = (d['subs'] is List) ? d['subs'] as List : [];
  final rows = _buildRows(subs);
  final totalQty = rows.fold<int>(0, (p, r) => p + r.total);
  final halfNote = _halfSizeNote(rows);

  // Two sections at most: PANT, then SHIRT (full rows followed by
  // half rows — they share one header, since the columns match).
  final pantRows = rows.where((r) => r.kind == _Kind.pant).toList();
  final shirtRows = [
    ...rows.where((r) => r.kind == _Kind.shirt),
    ...rows.where((r) => r.kind == _Kind.shirtHalf),
  ];

  final blocks = <pw.Widget>[];
  int headerCount = 0;
  int lastSizeCols = kPantSizes.length;

  if (pantRows.isNotEmpty) {
    blocks.add(_tableHeader(_Kind.pant));
    blocks.addAll(pantRows.map(_itemRow));
    headerCount++;
    lastSizeCols = kPantSizes.length;
  }
  if (shirtRows.isNotEmpty) {
    blocks.add(_tableHeader(_Kind.shirt));
    blocks.addAll(shirtRows.map(_itemRow));
    headerCount++;
    lastSizeCols = kShirtSizes.length;
  }
  if (blocks.isEmpty) {
    blocks.add(_tableHeader(_Kind.pant));
    headerCount = 1;
  }

  // rows are no longer a uniform height — sum the real ones
  final double rowsH = rows.fold<double>(0, (p, r) => p + r.height);
  final double usedH = headerCount * _headH + rowsH;

  final titleFont = pw.Font.timesBold();
  final italicFont = pw.Font.helveticaOblique();

  final theme = pw.PageTheme(
    pageFormat: PdfPageFormat.a4.copyWith(
      marginTop: _pageMarginV,
      marginBottom: _pageMarginV,
      marginLeft: _pageMarginH,
      marginRight: _pageMarginH,
    ),
    buildBackground: (ctx) => pw.FullPage(
      ignoreMargins: true,
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(12),
        child: pw.Container(
          decoration:
              pw.BoxDecoration(border: pw.Border.all(width: 1, color: _kInk)),
        ),
      ),
    ),
  );

  if (usedH <= _tableSpaceH) {
    // ── SINGLE SHEET : blank grid stretches to the terms block ──
    doc.addPage(
      pw.Page(
        pageTheme: theme,
        build: (ctx) => pw.Column(
          mainAxisSize: pw.MainAxisSize.max,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            ..._headerWidgets(d, titleFont),
            ...blocks,
            pw.Expanded(child: _fillerGrid(lastSizeCols)),
            _totalRow(totalQty, halfNote),
            _footerBlock(d, italicFont),
          ],
        ),
      ),
    );
  } else {
    // ── OVERFLOW : spill onto continuation pages ────────────────
    doc.addPage(
      pw.MultiPage(
        pageTheme: theme,
        footer: (ctx) => pw.SizedBox(
          width: _tableW,
          height: _footerH,
          child: ctx.pageNumber == ctx.pagesCount
              ? _footerBlock(d, italicFont)
              : pw.SizedBox(),
        ),
        build: (ctx) => [
          ..._headerWidgets(d, titleFont),
          ...blocks,
          _totalRow(totalQty, halfNote),
        ],
      ),
    );
  }

  return doc.save();
}