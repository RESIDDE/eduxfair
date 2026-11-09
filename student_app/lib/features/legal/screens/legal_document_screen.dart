import 'package:flutter/material.dart';

import '../../../core/constants/app_chrome.dart';
import '../../../core/theme/app_colors.dart';
import '../models/legal_document.dart';

/// Renders a [LegalDocument].
///
/// Selectable throughout, because someone being asked to agree to a document
/// should be able to copy a clause out of it.
class LegalDocumentScreen extends StatelessWidget {
  final LegalDocument document;

  const LegalDocumentScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SelectionArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, AppChrome.navClearance(context, gap: 32)),
          children: [
            Text(document.summary,
                style: text.bodyLarge?.copyWith(height: 1.5)),
            const SizedBox(height: 8),
            Text(
              'Last updated ${document.lastUpdated}',
              style: text.labelSmall?.copyWith(color: colors.textLight),
            ),
            const SizedBox(height: 8),
            Divider(color: colors.divider),
            for (final section in document.sections) ...[
              const SizedBox(height: 22),
              Text(section.heading, style: text.headlineSmall),
              for (final paragraph in section.body) ...[
                const SizedBox(height: 10),
                Text(paragraph, style: text.bodyMedium?.copyWith(height: 1.55)),
              ],
              if (section.bullets.isNotEmpty) const SizedBox(height: 10),
              for (final bullet in section.bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7, right: 10),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.textLight,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          bullet,
                          style: text.bodyMedium?.copyWith(height: 1.55),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
