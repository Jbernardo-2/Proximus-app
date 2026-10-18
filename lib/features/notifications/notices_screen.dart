import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../bodega/presentation/online.dart';
import 'notices.dart';

/// The bell on the home bar, with how many notices are unread.
class NoticesBell extends ConsumerWidget {
  const NoticesBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(noticesProvider).value?.unread ?? 0;
    return IconButton(
      tooltip: unread == 0 ? 'Avisos' : '$unread avisos sin leer',
      onPressed: () => context.push('/notices'),
      icon: Badge(isLabelVisible: unread > 0, label: Text(unread > 99 ? '99+' : '$unread'), child: const Icon(Icons.notifications_outlined)),
    );
  }
}

class NoticesScreen extends ConsumerWidget {
  const NoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    final unread = notices.value?.unread ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos'),
        actions: [
          if (unread > 0)
            IconButton(tooltip: 'Marcar todos como leídos', icon: const Icon(Icons.done_all), onPressed: () => runOnline(context, () => ref.read(noticeActionsProvider).markAllRead())),
        ],
      ),
      body: notices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(noticesProvider)),
        data: (notices) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(noticesProvider),
          child: notices.items.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('No tienes avisos.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)))])
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: notices.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _NoticeTile(notice: notices.items[index]),
                ),
        ),
      ),
    );
  }
}

String _ago(DateTime? at) {
  if (at == null) return '';
  final minutes = DateTime.now().difference(at).inMinutes;
  if (minutes < 1) return 'ahora';
  if (minutes < 60) return 'hace $minutes min';
  if (minutes < 24 * 60) return 'hace ${minutes ~/ 60} h';
  return DateFormat('d MMM', 'es').format(at);
}

class _NoticeTile extends ConsumerWidget {
  const _NoticeTile({required this.notice});

  final Notice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settles = ref.watch(sessionProvider).value?.can('deliveries:settle') ?? false;
    final route = notice.route(settles: settles);
    final color = switch (notice.severity) {
      'warning' => AppColors.amber,
      'success' => AppColors.brand,
      'important' => AppColors.danger,
      _ => AppColors.muted,
    };

    return ListTile(
      leading: Icon(notice.read ? Icons.notifications_none : Icons.notifications_active, color: notice.read ? AppColors.muted : color),
      title: Text(notice.title, style: TextStyle(fontWeight: notice.read ? FontWeight.normal : FontWeight.w800)),
      subtitle: Text(notice.message),
      trailing: Text(_ago(notice.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      tileColor: notice.read ? null : AppColors.brand.withValues(alpha: 0.05),
      onTap: () {
        // Marking it read needs signal; opening what it is about does not wait for it.
        ref.read(noticeActionsProvider).markRead(notice).catchError((_) {});
        if (route != null) context.push(route);
      },
    );
  }
}
