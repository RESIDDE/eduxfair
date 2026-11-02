import 'package:flutter/material.dart';

/// Layout that grows with the reader's text size.
///
/// Flutter already honours the system text size — nothing here turns that on.
/// What was missing is the other half of Apple's rule: **scale the layout with
/// the text**. A button pinned at 54pt, a tab bar pinned at 52pt and 546 other
/// hardcoded spacings do not move when someone turns text up, so the text
/// grows inside boxes that do not, and the first thing that happens is
/// clipping.
///
/// That matters more here than in most apps. Students read entry requirements,
/// grade conversions and visa checklists on a phone, and anyone who needs
/// larger text needs it exactly where the detail is densest.
extension DynamicType on BuildContext {
  /// The reader's text scale, clamped for layout purposes.
  ///
  /// The clamp is on *spacing*, never on the text itself: type keeps scaling
  /// all the way up, while the boxes around it stop growing at a point where
  /// the design still holds. Letting a 54pt button become 190pt helps nobody.
  double get layoutScale =>
      MediaQuery.textScalerOf(this).scale(1).clamp(1.0, 1.6);

  /// A fixed dimension, grown with the text.
  ///
  /// Use for the height of anything containing text — buttons, bars, rows.
  double scaled(double value) => value * layoutScale;

  /// True once the reader is at an accessibility size, where horizontal room
  /// has effectively run out and side-by-side layouts should stack instead.
  bool get isLargeText => MediaQuery.textScalerOf(this).scale(1) >= 1.35;
}
