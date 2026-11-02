import 'package:flutter/material.dart';

import '../utils/dynamic_type.dart';

/// Geometry of the floating chrome.
///
/// The student nav bar is a capsule that floats clear of the screen edges, so
/// every scrollable behind it has to leave room at the bottom. Before this
/// existed, the five tab screens did that with five different hardcoded
/// numbers — 100, 90, 32, 24 and 8 — and the last three were small enough that
/// their final row sat underneath the bar.
class AppChrome {
  AppChrome._();

  /// The capsule's height when expanded, before text scaling.
  static const double navBarHeight = 56;

  /// How far the capsule floats above the bottom safe area.
  static const double navBarInset = 10;

  /// The height the nav bar reserves in the `bottomNavigationBar` slot.
  ///
  /// Deliberately **constant across the collapse animation**. The capsule
  /// shrinks *within* this slot rather than shrinking the slot itself, because
  /// `Scaffold` republishes `MediaQuery.padding.bottom` to the body whenever
  /// the slot's measured height changes — which would re-resolve the padding
  /// of every list and re-run sliver layout on every frame of the animation,
  /// while a scroll is already in flight.
  static double navSlotHeight(BuildContext context) =>
      context.scaled(navBarHeight) + navBarInset;

  /// What a scrollable must leave at the bottom to clear the nav bar.
  ///
  /// This reads the number the framework already computed rather than
  /// recomputing it: `Scaffold` measures `bottomNavigationBar` and publishes
  /// `max(systemPadding.bottom, barHeight)` as the body's
  /// `MediaQuery.padding.bottom`. So this is device-correct and text-scale
  /// correct for free, where a hardcoded constant drifts the moment either
  /// changes.
  static double navClearance(BuildContext context, {double gap = 12}) =>
      MediaQuery.paddingOf(context).bottom + gap;
}
