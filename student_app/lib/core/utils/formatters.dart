import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Shared number and date formatting.
///
/// Replaces the two helpers carried over from consult_client — `formatNaira`
/// and `shortRef` were both logistics-specific and unused here — with the one
/// that three different models had each written privately.

final _groupedNumber = NumberFormat('#,##0', 'en_US');
final _dayMonthYear = DateFormat('d MMM yyyy', 'en_US');
final _dayMonth = DateFormat('d MMM', 'en_US');

/// `18000` → `18,000`.
String formatThousands(num value) => _groupedNumber.format(value.round());

/// Formats a raw number or string representation with thousands comma separators.
/// Useful for populating initial values of amount controllers.
/// e.g. `15000` -> `'15,000'`, `'1200000'` -> `'1,200,000'`, `null` -> `''`.
String formatAmountWithCommas(dynamic value) {
  if (value == null) return '';
  final s = value.toString().trim();
  if (s.isEmpty) return '';
  final stripped = s.replaceAll(',', '');
  if (stripped.contains('.')) {
    final parts = stripped.split('.');
    final integerPart = int.tryParse(parts[0]);
    if (integerPart != null) {
      final formattedInt = _groupedNumber.format(integerPart);
      return parts.length > 1 ? '$formattedInt.${parts[1]}' : formattedInt;
    }
    return s;
  }
  final n = num.tryParse(stripped);
  if (n != null) {
    return _groupedNumber.format(n.round());
  }
  return s;
}

/// A [TextInputFormatter] that automatically adds comma separators as the user types amounts.
///
/// Preserves cursor position accurately across comma insertions and deletions,
/// including when the user deletes a comma with backspace.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final bool allowDecimal;
  final int maxDigits;

  const ThousandsSeparatorInputFormatter({
    this.allowDecimal = false,
    this.maxDigits = 14,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String text = newValue.text;
    int selectionIndex = newValue.selection.end;

    // Detect if user pressed backspace on a comma
    final oldDigits = oldValue.text.replaceAll(RegExp(r'[^\d]'), '');
    final newDigits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (oldValue.text.length > newValue.text.length &&
        oldDigits == newDigits &&
        selectionIndex > 0) {
      final beforeIndex = selectionIndex - 1;
      if (beforeIndex >= 0 && beforeIndex < oldValue.text.length) {
        final before = oldValue.text.substring(0, beforeIndex);
        final after = oldValue.text.substring(selectionIndex);
        text = before + after;
        selectionIndex = beforeIndex;
      }
    }

    if (!allowDecimal) {
      final rawDigits = text.replaceAll(RegExp(r'[^\d]'), '');
      if (rawDigits.isEmpty) {
        return const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );
      }

      final digits = rawDigits.length > maxDigits
          ? rawDigits.substring(0, maxDigits)
          : rawDigits;

      int digitsBeforeCursor = 0;
      final safeEnd = selectionIndex.clamp(0, text.length);
      for (int i = 0; i < safeEnd; i++) {
        if (RegExp(r'\d').hasMatch(text[i])) {
          digitsBeforeCursor++;
        }
      }
      if (digitsBeforeCursor > digits.length) {
        digitsBeforeCursor = digits.length;
      }

      final stripped = digits.length > 1
          ? digits.replaceFirst(RegExp(r'^0+(?=\d)'), '')
          : digits;
      final formatted = stripped.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );

      int newCursor = 0;
      int countedDigits = 0;
      for (int i = 0; i < formatted.length; i++) {
        if (countedDigits >= digitsBeforeCursor) {
          break;
        }
        if (RegExp(r'\d').hasMatch(formatted[i])) {
          countedDigits++;
        }
        newCursor = i + 1;
      }

      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: newCursor),
      );
    } else {
      final hasDot = text.contains('.');
      String intPart = '';
      String decPart = '';

      if (hasDot) {
        final parts = text.split('.');
        intPart = parts[0].replaceAll(RegExp(r'[^\d]'), '');
        decPart = parts.sublist(1).join('').replaceAll(RegExp(r'[^\d]'), '');
        if (decPart.length > 2) decPart = decPart.substring(0, 2);
      } else {
        intPart = text.replaceAll(RegExp(r'[^\d]'), '');
      }

      if (intPart.isEmpty && decPart.isEmpty && !hasDot) {
        return const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );
      }

      final clampedInt = intPart.length > maxDigits
          ? intPart.substring(0, maxDigits)
          : intPart;

      final strippedInt = clampedInt.isEmpty
          ? (hasDot ? '0' : '')
          : (clampedInt.length > 1
              ? clampedInt.replaceFirst(RegExp(r'^0+(?=\d)'), '')
              : clampedInt);

      final formattedInt = strippedInt.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );

      String formatted = formattedInt;
      if (hasDot) {
        formatted = '$formattedInt.$decPart';
      }

      int nonCommaBeforeCursor = 0;
      final safeEnd = selectionIndex.clamp(0, text.length);
      for (int i = 0; i < safeEnd; i++) {
        if (text[i] != ',') {
          nonCommaBeforeCursor++;
        }
      }

      int newCursor = 0;
      int countedNonComma = 0;
      for (int i = 0; i < formatted.length; i++) {
        if (countedNonComma >= nonCommaBeforeCursor) {
          break;
        }
        if (formatted[i] != ',') {
          countedNonComma++;
        }
        newCursor = i + 1;
      }

      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: newCursor),
      );
    }
  }
}

/// `USD 18,000`. The currency leads because these are rarely the local one and
/// a bare number invites the wrong assumption.
String formatMoney(num value, String currency) =>
    '$currency ${formatThousands(value)}';

/// A range, collapsing to a single figure when both ends match.
String formatMoneyRange(num? min, num? max, String currency) {
  if (min == null && max == null) return 'Not published';
  if (min == null) return 'Up to ${formatMoney(max!, currency)}';
  if (max == null || max == min) return formatMoney(min, currency);
  return '$currency ${formatThousands(min)}–${formatThousands(max)}';
}

/// `7 September 2026` → `7 Sep 2026`.
String formatDate(DateTime date) => _dayMonthYear.format(date);

/// Without the year, for dates inside the current one.
String formatDayMonth(DateTime date) => _dayMonth.format(date);

/// A weekday, a date and a 12-hour time: `Tue 4 Nov, 2:30pm`.
///
/// Hand-rolled rather than a DateFormat pattern so the lower-case am/pm and the
/// comma placement match what the appointment cards have always shown — this
/// started life as a private helper there and moved here when the Spaces tabs
/// needed the same line.
String formatDateTime(DateTime when) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final period = when.hour < 12 ? 'am' : 'pm';
  final minute = when.minute.toString().padLeft(2, '0');
  return '${days[when.weekday - 1]} ${when.day} ${months[when.month - 1]}, '
      '$hour:$minute$period';
}

/// `2h`, `3d`, `5w` — compact relative time for lists.
String formatRelative(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 365) return '${(diff.inDays / 7).floor()}w';
  return '${(diff.inDays / 365).floor()}y';
}
