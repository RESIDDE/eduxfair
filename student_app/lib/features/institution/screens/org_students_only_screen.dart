import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';

/// Where staff land if something links them to a screen that only makes sense
/// for a student — a passport, an application, saved programmes.
///
/// It exists so that such a link can never crash the app. Redirecting staff
/// to their dashboard instead was the old answer, and it was fine for a `go`
/// but fatal for a `push`: pushing the dashboard put a second copy of the tab
/// shell's page on the navigator, and two pages with one key is the red
/// `keyReservation` screen. This is an ordinary page, so pushing it is safe,
/// and the back arrow returns to wherever the tap came from.
class OrgStudentsOnlyScreen extends StatelessWidget {
  const OrgStudentsOnlyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: AppConstants.routeOrgHome),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.school_outlined,
                    size: 32, color: colors.textSecondary),
              ),
              const SizedBox(height: 18),
              Text('This part of the app is for students',
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'You are signed in for your institution, so there is nothing '
                'here for you to do. Everything you need is on your Home tab.',
                textAlign: TextAlign.center,
                style: text.bodyMedium
                    ?.copyWith(color: colors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => context.go(AppConstants.routeOrgHome),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.background,
                ),
                child: const Text('Go to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
