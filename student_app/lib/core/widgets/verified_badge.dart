import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// What a verification badge is attesting to.
///
/// Each badge is a trust claim, so each one is deliberately narrow and the
/// tooltip says exactly what was checked. Overstating this would be the easiest
/// way for the platform to mislead a student about an institution.
enum VerifiedSubject {
  institution(
    label: 'Verified institution',
    explanation: 'Someone with an email address on this institution’s own '
        'domain confirmed this listing. Eduxfair does not assess accreditation '
        'or programme quality.',
  ),
  student(
    label: 'Verified student',
    explanation: 'An Eduxfair reviewer checked your uploaded documents against '
        'the qualifications you entered.',
  ),
  educator(
    label: 'Verified educator',
    explanation: 'This person’s affiliation with the institution has been '
        'confirmed.',
  );

  const VerifiedSubject({required this.label, required this.explanation});

  final String label;
  final String explanation;
}

/// A compact verification badge. Tapping it explains the claim, because a badge
/// nobody can interrogate is just decoration.
class VerifiedBadge extends StatelessWidget {
  final VerifiedSubject subject;
  final bool compact;

  const VerifiedBadge({
    super.key,
    required this.subject,
    this.compact = false,
  });

  void _explain(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.verified_rounded, color: context.colors.success, size: 32),
        title: Text(subject.label),
        content: Text(subject.explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (compact) {
      return Tooltip(
        message: subject.explanation,
        child: Icon(Icons.verified_rounded, size: 16, color: colors.success),
      );
    }

    return Semantics(
      button: true,
      label: '${subject.label}. Tap to learn what this means.',
      child: InkWell(
        onTap: () => _explain(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: colors.successLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 14, color: colors.success),
              const SizedBox(width: 5),
              Text(
                subject.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.success,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows an unverified or pending state honestly rather than hiding it.
class VerificationStatusChip extends StatelessWidget {
  final String status;
  final VerifiedSubject subject;

  const VerificationStatusChip({
    super.key,
    required this.status,
    required this.subject,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (status == 'verified') return VerifiedBadge(subject: subject);

    final (label, fg, bg, icon) = switch (status) {
      'pending' => (
          'Verification pending',
          colors.warning,
          colors.warningLight,
          Icons.schedule_rounded,
        ),
      'rejected' => (
          'Verification declined',
          colors.error,
          colors.errorLight,
          Icons.error_outline_rounded,
        ),
      _ => (
          'Not verified',
          colors.textSecondary,
          colors.surfaceVariant,
          Icons.info_outline_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
