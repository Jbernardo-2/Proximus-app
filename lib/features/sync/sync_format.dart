import 'package:intl/intl.dart';

/// "hace 5 min", "hoy 14:05", "12/10 09:30"; "nunca" when it never happened.
String relativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return 'nunca';
  final reference = now ?? DateTime.now();
  final difference = reference.difference(time);
  if (difference.inMinutes < 1) return 'hace un momento';
  if (difference.inMinutes < 60) return 'hace ${difference.inMinutes} min';
  final sameDay = time.year == reference.year && time.month == reference.month && time.day == reference.day;
  return sameDay ? 'hoy ${DateFormat.Hm().format(time)}' : DateFormat('dd/MM HH:mm').format(time);
}
