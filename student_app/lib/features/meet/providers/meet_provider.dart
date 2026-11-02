import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/appointment.dart';

/// Meet Me: requesting, tracking and cancelling appointments.
///
/// Requesting one writes a `passport_shares` row via a database trigger, since
/// asking an institution for a meeting is an unambiguous request to be
/// identified by it. The request screen says so before the student confirms.
class MeetProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  List<Appointment> _appointments = [];
  bool _loading = false;
  bool _busy = false;
  String? _error;

  List<Appointment> get appointments => _appointments;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;

  List<Appointment> get upcoming =>
      _appointments.where((a) => a.isUpcoming).toList();

  List<Appointment> get past =>
      _appointments.where((a) => !a.isUpcoming).toList();

  int get pendingCount => _appointments.where((a) => a.isRequested).length;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final id = _service.userId;
      if (id == null) return;

      final rows = await _service.client
          .from('appointments')
          .select('*, institutions!inner(id, name, slug, country, city, '
              'logo_url, verification_status, tier), programs(id, name)')
          .eq('student_id', id)
          // Nulls last so a request with no agreed time yet still sits at the
          // top where the student is waiting on it.
          .order('scheduled_for', ascending: true, nullsFirst: true);

      _appointments = (rows as List)
          .map((r) => Appointment.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Open slots for an institution, from now forward.
  Future<List<AvailabilitySlot>> fetchSlots(String institutionId) async {
    try {
      final rows = await _service.client
          .from('availability_slots')
          .select()
          .eq('institution_id', institutionId)
          .eq('is_booked', false)
          .gte('starts_at', DateTime.now().toUtc().toIso8601String())
          .order('starts_at')
          .limit(60);
      return (rows as List)
          .map((r) => AvailabilitySlot.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return [];
    }
  }

  /// Requests a meeting. A slot is optional: a student may ask for a time that
  /// is not published and let the institution propose one.
  Future<bool> request({
    required String institutionId,
    String? programId,
    AvailabilitySlot? slot,
    String channel = 'video',
    String? message,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _service.client.from('appointments').insert({
        'student_id': _service.userId,
        'institution_id': institutionId,
        'program_id': programId,
        'slot_id': slot?.id,
        'host_profile_id': slot?.hostProfileId,
        'scheduled_for': slot?.startsAt.toUtc().toIso8601String(),
        'duration_min': slot == null ? 30 : slot.duration.inMinutes,
        'channel': channel,
        'student_message': message,
      });
      await load();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> cancel(Appointment appointment) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _service.client
          .from('appointments')
          .update({'status': 'cancelled'})
          .eq('id', appointment.id);
      await load();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
