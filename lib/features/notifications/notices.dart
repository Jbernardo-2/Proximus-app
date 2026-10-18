import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api.dart';

/// A notice the server sent this user.
final class Notice {
  const Notice({required this.id, required this.type, required this.title, required this.message, required this.read, this.severity = 'info', this.createdAt, this.deliveryRunId});

  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
    id: json['id'].toString(),
    type: json['type']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Aviso',
    message: json['message']?.toString() ?? '',
    severity: json['severity']?.toString() ?? 'info',
    read: json['read'] == true,
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
    deliveryRunId: json['delivery_run_id']?.toString(),
  );

  final String id;
  final String type;
  final String title;
  final String message;
  final String severity;
  final bool read;
  final DateTime? createdAt;
  final String? deliveryRunId;

  /// Where tapping it leads, by what it is about; null when there is nothing to open.
  String? route({required bool settles}) => switch (type) {
    'delivery_run_awaiting_settlement' when deliveryRunId != null && settles => '/settlements/$deliveryRunId',
    'delivery_outcome' when deliveryRunId != null && settles => '/runs/$deliveryRunId/review',
    'delivery_run_loaded' => '/deliveries',
    'product_count_adjusted' => '/counts',
    'order_confirmed' => '/warehouse-runs',
    _ => null,
  };
}

typedef Notices = ({List<Notice> items, int unread});

Notices _parse(Map<String, dynamic> response) => (
  items: [for (final json in (response['data'] as List? ?? const []).cast<Map>()) Notice.fromJson(json.cast<String, dynamic>())],
  unread: (response['unread_count'] as num?)?.toInt() ?? 0,
);

const _cacheKey = 'notifications';

/// The latest notices: read from the server whenever the phone syncs, and the last ones
/// kept on the phone to show without signal.
final noticesProvider = FutureProvider<Notices>((ref) async {
  ref.watch(syncProvider.select((status) => status.lastReport));
  // Between syncs (every 15 minutes) the bell asks again every few minutes while the app is open.
  final refresh = Timer(const Duration(minutes: 3), ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  final api = ref.watch(apiProvider);
  final db = ref.watch(databaseProvider);
  try {
    if (api == null) throw ApiException('Sin conexión con el servidor.');
    final response = await api.get('/notifications', query: {'per_page': 30});
    await db.writeState(_cacheKey, jsonEncode(response));
    return _parse(response);
  } on ApiException {
    final cached = await db.readState(_cacheKey);
    return cached == null ? (items: const <Notice>[], unread: 0) : _parse((jsonDecode(cached) as Map).cast<String, dynamic>());
  }
});

final noticeActionsProvider = Provider<NoticeActions>((ref) => NoticeActions(ref));

class NoticeActions {
  NoticeActions(this._ref);

  final Ref _ref;

  Future<void> markRead(Notice notice) async {
    if (notice.read) return;
    await _ref.read(apiProvider)?.post('/notifications/${notice.id}/read');
    _ref.invalidate(noticesProvider);
  }

  Future<void> markAllRead() async {
    await _ref.read(apiProvider)?.post('/notifications/read-all');
    _ref.invalidate(noticesProvider);
  }
}
