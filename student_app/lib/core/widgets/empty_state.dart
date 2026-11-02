import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// An empty state that tells the student what to do next.
///
/// Most empty states in this app are not errors — a new student genuinely has
/// no matches yet — so each one carries the action that resolves it.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: colors.textLight),
            ),
            const SizedBox(height: 20),
            Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                child: ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A full-width error state with a retry.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load',
        message: message,
        actionLabel: onRetry == null ? null : 'Try again',
        onAction: onRetry,
      );
}
