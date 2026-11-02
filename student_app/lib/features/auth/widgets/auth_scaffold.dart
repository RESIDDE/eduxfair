import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/brand_glow.dart';

/// The shell every screen in the sign-in and sign-up flow sits in.
///
/// Those screens all hand-rolled the same
/// `Center > SingleChildScrollView > ConstrainedBox(420) > Column`, with the
/// logo sometimes left-aligned and sometimes absent and the "already have an
/// account" row floating at the end of the scroll. Pulling it into one place
/// is what makes the flow read as one flow.
///
/// The glow sits behind everything and is what the glass in front of it
/// refracts. The footer is pinned above a hairline rather than scrolling with
/// the form.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// The form, cards, or whatever this step is actually for.
  final List<Widget> children;

  /// Pinned to the bottom — usually the link to the other side of the flow.
  final Widget? footer;

  /// A back button, when this step has somewhere to go back to.
  final Widget? leading;

  final double maxWidth;

  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.footer,
    this.leading,
    this.maxWidth = 440,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -70,
            left: 0,
            right: 0,
            child: const Center(child: BrandGlow()),
          ),
          SafeArea(
            child: Column(
              children: [
                if (leading != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, top: 4),
                      // A bounded box: AppBackButton ends in a Center, which
                      // is right inside an AppBar's fixed leading slot and
                      // would otherwise fill this row and centre the arrow.
                      child: SizedBox(width: 48, height: 48, child: leading),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                          24, leading == null ? 24 : 8, 24, 8),
                      child: ConstrainedBox(
                        // This also ships to web, where an unconstrained form
                        // stretches across a desktop window and stops being
                        // readable.
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The plate stays white: the mark is navy on an
                            // opaque white artboard, so on a black canvas it
                            // is the plate that makes it legible at all.
                            const Center(
                              child: EduxfairLogo(size: 72, borderRadius: 22),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              title,
                              style: text.displaySmall,
                              textAlign: TextAlign.center,
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                subtitle!,
                                style: text.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 24),
                            ...children,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (footer != null)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colors.divider)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: footer,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "already have an account? / new here?" row every auth screen ends with.
class AuthFooterLink extends StatelessWidget {
  final String question;
  final String action;
  final VoidCallback? onTap;

  const AuthFooterLink({
    super.key,
    required this.question,
    required this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(question, style: Theme.of(context).textTheme.bodyMedium),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      );
}
