import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../applications/providers/applications_provider.dart';
import '../../matches/providers/matches_provider.dart';
import '../../passport/providers/passport_provider.dart';

enum ActionTone { good, warning }

/// Something the student needs to do, derived from state rather than stored.
///
/// These used to be cards pinned to the top of the feed, which put four
/// standing to-dos between the student and the thing they opened the app to
/// read — and repeated them on every visit, because nothing about a feed card
/// can be dismissed or marked seen.
///
/// They belong with the notifications instead, where the nav badge already
/// says how many are waiting. They are still computed, not stored: an offer
/// landing or a passport crossing the matching threshold is a fact about the
/// data, and writing a row for it would mean a trigger per rule and a way for
/// the row and the fact to disagree.
class ActionItem {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final String route;
  final ActionTone tone;

  const ActionItem({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.route,
    required this.tone,
  });
}

/// What is outstanding for this student, in the order it is worth seeing.
List<ActionItem> studentActions({
  required PassportProvider passport,
  required MatchesProvider matches,
  required ApplicationsProvider applications,
}) {
  final items = <ActionItem>[];

  if (!passport.isMatchable) {
    items.add(ActionItem(
      icon: Icons.badge_rounded,
      title: 'Finish your Education Passport',
      body: 'Institutions can only find you once it reaches '
          '${AppConstants.minCompletenessToMatch}%. Yours is at '
          '${passport.completeness}%.',
      actionLabel: 'Continue',
      route: AppConstants.routePassportEdit,
      tone: ActionTone.warning,
    ));
  }

  if (matches.invitationCount > 0) {
    items.add(ActionItem(
      icon: Icons.handshake_rounded,
      title: matches.invitationCount == 1
          ? 'An institution asked for you'
          : '${matches.invitationCount} institutions asked for you',
      body: 'They matched your profile and want to hear from you.',
      actionLabel: 'See who',
      route: AppConstants.routeMatches,
      tone: ActionTone.good,
    ));
  }

  if (applications.offerCount > 0) {
    items.add(ActionItem(
      icon: Icons.celebration_rounded,
      title: applications.offerCount == 1
          ? 'You have an offer'
          : 'You have ${applications.offerCount} offers',
      body: 'Review the terms and respond when you are ready.',
      actionLabel: 'View',
      route: AppConstants.routeApplications,
      tone: ActionTone.good,
    ));
  }

  if (applications.outstandingRequestCount > 0) {
    items.add(ActionItem(
      icon: Icons.upload_file_rounded,
      title: 'Documents requested',
      body: '${applications.outstandingRequestCount} outstanding — your '
          'application is waiting on these.',
      actionLabel: 'Upload',
      route: AppConstants.routeApplications,
      tone: ActionTone.warning,
    ));
  }

  return items;
}
