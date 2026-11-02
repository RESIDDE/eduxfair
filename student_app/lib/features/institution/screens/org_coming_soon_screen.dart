import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

/// A named placeholder for a recruitment screen not yet ported.
///
/// Registered at the real route rather than hidden from the menu: the shape of
/// the console is part of what is being reviewed, and a menu item that appears
/// later moves everything around it. Tapping one says what it will do instead
/// of throwing an unknown-route error.
class OrgComingSoonScreen extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const OrgComingSoonScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(icon: icon, title: 'Coming next', message: message),
      );
}
