import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/app_notification.dart';

/// In-app notifications, delivered live.
///
/// The RLS policy on `notifications` already restricts rows to the caller, so
/// the realtime subscription is filtered by profile_id as well — not for
/// safety, but so the client is not woken for rows it will discard.
class NotificationsProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  List<AppNotification> _notifications = [];
  RealtimeChannel? _channel;
  bool _loading = false;
  String? _error;

  List<AppNotification> get notifications => _notifications;
  bool get loading => _loading;
  String? get error => _error;

  int get unreadCount => _notifications.where((n) => n.isUnread).length;
  bool get hasUnread => unreadCount > 0;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final id = _service.userId;
      if (id == null) return;

      final rows = await _service.client
          .from('notifications')
          .select()
          .eq('profile_id', id)
          .order('created_at', ascending: false)
          .limit(100);

      _notifications = (rows as List)
          .map((r) => AppNotification.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void subscribe() {
    final id = _service.userId;
    if (id == null || _channel != null) return;

    _channel = _service.client
        .channel('notifications:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'profile_id',
            value: id,
          ),
          callback: (payload) {
            final notification = AppNotification.fromMap(payload.newRecord);
            if (_notifications.any((n) => n.id == notification.id)) return;
            _notifications = [notification, ..._notifications];
            notifyListeners();
          },
        )
        .subscribe();
  }

  void unsubscribe() {
    final channel = _channel;
    if (channel != null) _service.client.removeChannel(channel);
    _channel = null;
  }

  Future<void> markRead(AppNotification notification) async {
    if (!notification.isUnread) return;
    final now = DateTime.now();

    // Optimistic: a badge that lingers after a tap reads as a bug.
    _notifications = _notifications
        .map((n) => n.id == notification.id
            ? AppNotification(
                id: n.id, kind: n.kind, title: n.title, body: n.body,
                payload: n.payload, readAt: now, createdAt: n.createdAt)
            : n)
        .toList();
    notifyListeners();

    try {
      await _service.client
          .from('notifications')
          .update({'read_at': now.toUtc().toIso8601String()})
          .eq('id', notification.id);
    } catch (e) {
      if (kDebugMode) debugPrint('markRead failed: $e');
      await load();
    }
  }

  Future<void> markAllRead() async {
    final unread = _notifications.where((n) => n.isUnread).toList();
    if (unread.isEmpty) return;

    try {
      await _service.client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('profile_id', _service.userId!)
          .isFilter('read_at', null);
      await load();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
