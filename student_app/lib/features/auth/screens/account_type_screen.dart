import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';

/// The fork at the top of sign-up: student, or organisation.
///
/// The two sides of this product are not variations on one form. A student
/// builds a private passport and is found by institutions; an institution
/// builds a public listing and goes looking. They need different fields,
/// different terms, and they land in different shells — so the choice is made
/// before either form is shown rather than as a toggle inside one.
///
/// Signing *in* stays a single screen: the role is already on the account by
/// then, and the router reads it.
class AccountTypeScreen extends StatelessWidget {
  const AccountTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        // Reached with `go` from login and from onboarding, both of which
        // replace the stack, so this falls back rather than popping.
        leading: const AppBackButton(fallback: AppConstants.routeLogin),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: EduxfairLogo(
                      size: 64,
                      borderRadius: 18,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Join ${AppConstants.appName}', style: text.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Which of these are you? It decides what you set up next, '
                    'so pick the one that fits.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  _AccountCard(
                    icon: Icons.badge_outlined,
                    title: "I'm a student",
                    body: 'Build an Education Passport once. Institutions '
                        'that match you reach out — and they only see you '
                        'when you let them.',
                    bullets: const [
                      'Your passport stays private until you share it',
                      'Offers and invitations come to you',
                      'Apply, track visas, book a Fair Passport',
                    ],
                    onTap: () => context.push(AppConstants.routeRegister),
                  ),
                  const SizedBox(height: 14),
                  _AccountCard(
                    icon: Icons.apartment_outlined,
                    title: "We're an institution",
                    body: 'Universities, colleges, embassies and agencies. '
                        'Put up a full page, post to the feed, and find '
                        'students who already fit your requirements.',
                    bullets: const [
                      'A page students read in their own country’s terms',
                      'Post, host Spaces, answer questions',
                      'Search matched students and run a pipeline',
                    ],
                    onTap: () =>
                        context.push(AppConstants.routeRegisterInstitution),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account?', style: text.bodyMedium),
                      TextButton(
                        onPressed: () => context.go(AppConstants.routeLogin),
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
  final VoidCallback onTap;

  const _AccountCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.bullets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 21, color: colors.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(title, style: text.headlineSmall),
                ),
                Icon(Icons.arrow_forward_rounded,
                    size: 19, color: colors.textLight),
              ],
            ),
            const SizedBox(height: 14),
            Text(body, style: text.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: 14),
            for (final b in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_rounded,
                          size: 15, color: colors.success),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(b,
                          style: text.bodySmall?.copyWith(height: 1.4)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
