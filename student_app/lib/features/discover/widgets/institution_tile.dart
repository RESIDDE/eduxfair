import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/verified_badge.dart';
import '../models/institution.dart';

/// One organisation in the directory.
///
/// `DiscoverProvider` has fetched these on every load since the directory was
/// built, exposed them through a public getter, and nothing ever rendered one —
/// so a student could only reach a university by finding one of its programmes
/// first. Someone who knows they want to look at Canadian universities had no
/// route at all.
///
/// Deliberately quieter than a programme row: a listing is a place to go, not
/// an offer to compare, so it carries identity — who, what kind, where, and
/// whether the badge is earned — and leaves the detail to the page itself.
class InstitutionTile extends StatelessWidget {
  final Institution institution;
  final VoidCallback? onTap;

  const InstitutionTile({
    super.key,
    required this.institution,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Pressable.surface(
      onTap: onTap,
      haptic: null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InstitutionAvatar(
              logoUrl: institution.logoUrl,
              initials: institution.initials,
              size: 46,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // The name takes the room; the badge is fixed beside it
                      // so truncation can never eat the trust mark.
                      Flexible(
                        child: Text(
                          institution.name,
                          style: text.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (institution.isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(
                          subject: VerifiedSubject.institution,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${AppConstants.institutionKinds[institution.kind] ?? 'Institution'}'
                    ' · ${institution.location}'
                    '${institution.followerCount > 0 ? ' · ${formatThousands(institution.followerCount)} followers' : ''}',
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((institution.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      institution.description!.trim(),
                      style: text.bodySmall?.copyWith(height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Icon(Icons.chevron_right_rounded,
                  size: 20, color: colors.textLight),
            ),
          ],
        ),
      ),
    );
  }
}
