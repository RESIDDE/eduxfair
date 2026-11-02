import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/core/utils/formatters.dart';

void main() {
  group('formatAmountWithCommas', () {
    test('formats numbers properly', () {
      expect(formatAmountWithCommas(null), '');
      expect(formatAmountWithCommas(''), '');
      expect(formatAmountWithCommas(0), '0');
      expect(formatAmountWithCommas(500), '500');
      expect(formatAmountWithCommas(1000), '1,000');
      expect(formatAmountWithCommas(25000), '25,000');
      expect(formatAmountWithCommas(1234567), '1,234,567');
      expect(formatAmountWithCommas('1234567'), '1,234,567');
      expect(formatAmountWithCommas('1,234,567'), '1,234,567');
      expect(formatAmountWithCommas('5000.50'), '5,000.50');
    });
  });

  group('ThousandsSeparatorInputFormatter', () {
    const formatter = ThousandsSeparatorInputFormatter();

    test('adds commas to typed integer digits', () {
      final res1 = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '1000',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(res1.text, '1,000');
      expect(res1.selection.baseOffset, 5);

      final res2 = formatter.formatEditUpdate(
        res1,
        const TextEditingValue(
          text: '1,0000',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(res2.text, '10,000');
      expect(res2.selection.baseOffset, 6);
    });

    test('maintains cursor position when typing in middle', () {
      // User types '2' in "1|,000" -> "12,000"
      final res = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '1,000',
          selection: TextSelection.collapsed(offset: 1),
        ),
        const TextEditingValue(
          text: '12,000',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(res.text, '12,000');
      expect(res.selection.baseOffset, 2);
    });

    test('handles backspacing over a comma cleanly', () {
      // User has "1|,000" and presses backspace -> deletes comma -> "1000"
      final res = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '1,000',
          selection: TextSelection.collapsed(offset: 2),
        ),
        const TextEditingValue(
          text: '1000',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      // Deleting comma also deleted the digit '1' before it
      expect(res.text, '0');
    });

    test('handles decimal formatting when allowDecimal is true', () {
      const decFormatter = ThousandsSeparatorInputFormatter(allowDecimal: true);
      final res = decFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '25000.75',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(res.text, '25,000.75');
    });
  });
}
