import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.isLocal,
    required this.header,
    required this.body,
    this.locked = false,
    this.timeLabel,
  });

  final bool isLocal;
  final String header;
  final String body;
  final bool locked;
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isLocal ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isLocal ? scheme.primaryContainer : scheme.secondaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isLocal ? 14 : 4),
            bottomRight: Radius.circular(isLocal ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locked) ...[
                  Icon(Icons.lock, size: 12, color: scheme.onSecondaryContainer.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    header,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: scheme.onSecondaryContainer.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(body, style: const TextStyle(height: 1.3)),
            if (timeLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                timeLabel!,
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSecondaryContainer.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String formatEpoch(int seconds) {
  if (seconds <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  final now = DateTime.now();
  final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${dt.month}/${dt.day} $hh:$mm';
}
