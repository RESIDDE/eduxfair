import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Pushing the same location twice is not a double visit — it is a crash.
///
/// go_router derives a page key from the matched path, so two pages for one
/// location land in the same Navigator with the same key and trip
/// `!keyReservation.contains(key)`: the red screen that the legal pages used
/// to show. A fast double tap, or two live gesture recognizers on one link,
/// is enough to cause it.
extension PushOnce on BuildContext {
  void pushOnce(String location) {
    if (GoRouterState.of(this).matchedLocation == location) return;
    push(location);
  }
}
