/// Application Utility Functions for Onzone App

/// Formats a work order reference string like "OZ/782/2024-25" 
/// to trim financial year/suffix and return "OZ/782".
String formatWorkOrderRef(String? ref, {String fallback = 'N/A'}) {
  if (ref == null || ref.trim().isEmpty) return fallback;
  final trimmed = ref.trim();
  final parts = trimmed.split('/');
  
  if (parts.length >= 2) {
    final lastPart = parts.last.trim();
    // Matches year patterns like "2024-25", "2024-2025", "24-25" or "2024"
    final yearRegex = RegExp(r'^(\d{2,4}-\d{2,4}|(19|20)\d{2})$');
    if (yearRegex.hasMatch(lastPart)) {
      return parts.sublist(0, parts.length - 1).join('/');
    }
  }
  
  return trimmed;
}

/// Formats dates to "date day and year" style for UI display, e.g., "20 Jul 2026 (Mon)"
String formatAppDate(dynamic rawDate, {String fallback = 'N/A'}) {
  if (rawDate == null) return fallback;
  final str = rawDate.toString().trim();
  if (str.isEmpty || str == 'N/A' || str == 'null') return fallback;

  DateTime? dt = DateTime.tryParse(str);

  if (dt == null) {
    try {
      final cleanStr = str.split(' ')[0]; // ignore time if present
      final delimiter = cleanStr.contains('-') ? '-' : (cleanStr.contains('/') ? '/' : '');
      if (delimiter.isNotEmpty) {
        final parts = cleanStr.split(delimiter);
        if (parts.length >= 3) {
          int? p1 = int.tryParse(parts[0]);
          int? p2 = int.tryParse(parts[1]);
          int? p3 = int.tryParse(parts[2]);
          if (p1 != null && p2 != null && p3 != null) {
            if (p1 > 1000) {
              // YYYY-MM-DD
              dt = DateTime(p1, p2, p3);
            } else if (p3 > 1000) {
              // DD-MM-YYYY
              dt = DateTime(p3, p2, p1);
            }
          }
        }
      }
    } catch (_) {}
  }

  if (dt == null) return str;

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  const weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  final day = dt.day.toString().padLeft(2, '0');
  final month = months[dt.month - 1];
  final year = dt.year.toString();
  final weekday = weekdays[dt.weekday - 1];

  return '$day $month $year ($weekday)';
}

/// Formats dates to "year month date" style for backend payload (yyyy-MM-dd), e.g., "2026-07-20"
String formatBackendDate(dynamic rawDate) {
  if (rawDate == null) return '';
  final str = rawDate.toString().trim();
  if (str.isEmpty || str == 'N/A' || str == 'null') return '';

  DateTime? dt = DateTime.tryParse(str);

  if (dt == null) {
    try {
      final cleanStr = str.split(' ')[0]; // ignore time if present
      final delimiter = cleanStr.contains('-') ? '-' : (cleanStr.contains('/') ? '/' : '');
      if (delimiter.isNotEmpty) {
        final parts = cleanStr.split(delimiter);
        if (parts.length >= 3) {
          int? p1 = int.tryParse(parts[0]);
          int? p2 = int.tryParse(parts[1]);
          int? p3 = int.tryParse(parts[2]);
          if (p1 != null && p2 != null && p3 != null) {
            if (p1 > 1000) {
              // YYYY-MM-DD
              dt = DateTime(p1, p2, p3);
            } else if (p3 > 1000) {
              // DD-MM-YYYY
              dt = DateTime(p3, p2, p1);
            }
          }
        }
      }
    } catch (_) {}
  }

  // If parsed string e.g. "20 Jul 2026 (Mon)"
  if (dt == null) {
    try {
      final parts = str.replaceAll('(', ' ').replaceAll(')', ' ').trim().split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        int? day = int.tryParse(parts[0]);
        int? year = int.tryParse(parts[2]);
        const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
        int month = months.indexOf(parts[1].toLowerCase()) + 1;
        if (day != null && year != null && month > 0) {
          dt = DateTime(year, month, day);
        }
      }
    } catch (_) {}
  }

  if (dt == null) return str;

  final year = dt.year.toString();
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');

  return '$year-$month-$day';
}
