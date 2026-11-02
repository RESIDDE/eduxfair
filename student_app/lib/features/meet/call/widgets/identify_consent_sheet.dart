import 'package:flutter/material.dart';

import '../../../../core/supabase/supabase_service.dart';

/// The one consent step in the whole feature.
///
/// Shown before a listener's first microphone, camera, hand or message. The
/// wording is the same sentence the React console uses, and the last line is
/// true because `identify_in_space` writes an ordinary revocable
/// `passport_shares` row — the same row applying, booking and a booth scan
/// produce. Saying so is what makes asking acceptable.
///
/// Returns true when they agreed and the upgrade succeeded.
Future<bool> showIdentifyConsent(
  BuildContext context, {
  required String institution,
  required Future<void> Function() onConfirm,
}) async {
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16181C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => _ConsentSheet(
      institution: institution,
      onConfirm: onConfirm,
    ),
  );
  return agreed ?? false;
}

class _ConsentSheet extends StatefulWidget {
  final String institution;
  final Future<void> Function() onConfirm;

  const _ConsentSheet({required this.institution, required this.onConfirm});

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.verified_user_rounded, color: Colors.white, size: 28),
          const SizedBox(height: 12),
          const Text(
            'Share your passport to speak?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
              children: [
                const TextSpan(text: 'Speaking here shares your Education Passport with '),
                TextSpan(
                  text: widget.institution,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(
                  text: ', so they will see your name and verified documents. '
                      'You can take that back any time in Passport → Sharing.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Until you do, you are only your handle in this room, and nobody '
            'can hear or see you.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2E1313),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFF87171), fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Keep listening',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _busy = true;
                            _error = null;
                          });
                          try {
                            await widget.onConfirm();
                            if (context.mounted) Navigator.of(context).pop(true);
                          } catch (e) {
                            if (context.mounted) {
                              setState(() {
                                _busy = false;
                                // describeError, not toString(): our guards
                                // raise P0001 with a sentence written for the
                                // person reading it, and toString() wraps that
                                // in `PostgrestException(message: …, code: …)`.
                                _error = SupabaseService.describeError(e);
                              });
                            }
                          }
                        },
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.black,
                          ),
                        )
                      : const Text('Share and speak'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
