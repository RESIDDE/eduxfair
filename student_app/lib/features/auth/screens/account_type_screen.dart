import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/gradient_border.dart';
import '../../../core/widgets/pressable.dart';
import '../widgets/auth_scaffold.dart';

/// The fork at the top of sign-up: student, or organisation.
///
/// The two sides of this product are not variations on one form. A student
/// builds a private passport and is found by institutions; an institution
/// builds a public listing and goes looking. They need different fields,
/// different terms, and they land in different shells — so the choice is made
/// before either form is shown rather than as a toggle inside one.
///
/// Because this is the one screen where that choice is explained, the two
/// cards carry the weight: a full-height ramp down the leading edge, the
/// promise in display type, and what you actually get listed underneath. The
/// ramps differ so the two paths are told apart at a glance rather than by
/// reading — the brand gradient for the student, flat blue for the
/// institution, which is the same division the rest of the app uses between
/// what is yours and what is a control.
///
/// Signing *in* stays a single screen: the role is already on the account by
/// then, and the router reads it.
class AccountTypeScreen extends StatelessWidget {
  const AccountTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AuthScaffold(
      // Reached with `go` from login and from onboarding, both of which
      // replace the stack, so this falls back rather than popping.
      leading: const AppBackButton(fallback: AppConstants.routeLogin),
      maxWidth: 480,
      title: 'Join ${AppConstants.appName}',
      subtitle:
          'Which of these are you? It decides what you set up next, so '
          'pick the one that fits.',
      footer: AuthFooterLink(
        question: 'Already have an account?',
        action: 'Sign in',
        onTap: () => context.go(AppConstants.routeLogin),
      ),
      children: [
        _PathCard(
          icon: Icons.badge_outlined,
          eyebrow: 'For students',
          title: "I'm a student",
          body:
              'Build an Education Passport once. Institutions that match you '
              'reach out — and they only see you when you let them.',
          bullets: const [
            'Your passport stays private until you share it',
            'Offers and invitations come to you',
            'Apply, track visas, book a Fair Passport',
          ],
          cta: 'Build my passport',
          gradient: colors.brandGradient,
          onTap: () => context.push(AppConstants.routeRegister),
        ),
        const SizedBox(height: 16),
        _PathCard(
          icon: Icons.apartment_outlined,
          eyebrow: 'For institutions',
          title: "We're an institution",
          body: 'Universities, colleges, embassies and agencies. Put up a '
              'full page, post to the feed, and find students who already fit '
              'your requirements.',
          bullets: const [
            'A page students read in their own country’s terms',
            'Post, host Spaces, answer questions',
            'Search matched students and run a pipeline',
          ],
          cta: 'Create our page',
          gradient: colors.accentGradient,
          onTap: () => context.push(AppConstants.routeRegisterInstitution),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PathCard extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final List<String> bullets;
  final String cta;
  final Gradient gradient;
  final VoidCallback onTap;

  const _PathCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.bullets,
    required this.cta,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final plain = MediaQuery.highContrastOf(context);

    return Semantics(
      button: true,
      label: '$title. $body',
      child: Pressable(
        onTap: onTap,
        // A whole card is a big thing to move; it dips rather than shrinks.
        scale: 0.985,
        haptic: HapticKind.selection,
        child: GradientBorder(
          radius: 24,
          gradient: gradient,
          fill: colors.surface,
          // The ramp is a sibling that has to match the card's height, and the
          // card sits in a scroll view — so the Row has no height to stretch
          // to until something resolves one. Cheap here: two children, laid
          // out once, on a screen that does not scroll under the finger.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A full-height ramp down the leading edge — the card's one
                // piece of colour, and what tells the two paths apart before
                // either has been read.
                SizedBox(
                  width: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: plain ? null : gradient,
                      color: plain ? colors.border : null,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.surfaceVariant,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                icon,
                                size: 22,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    eyebrow.toUpperCase(),
                                    style: text.labelSmall?.copyWith(
                                      color: colors.textLight,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(title, style: text.headlineSmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          body,
                          style: text.bodyMedium?.copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 14),
                        for (final bullet in bullets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.check_rounded,
                                    size: 15,
                                    color: colors.success,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    bullet,
                                    style: text.bodySmall?.copyWith(
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        // A named next step rather than a bare arrow: the two
                        // cards lead somewhere different, and saying where is
                        // the whole job of this screen.
                        Row(
                          children: [
                            Text(
                              cta,
                              style: text.titleMedium?.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: colors.textPrimary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
