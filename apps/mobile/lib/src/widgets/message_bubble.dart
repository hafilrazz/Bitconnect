import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.isLocal,
    required this.header,
    required this.body,
    this.locked = false,
    this.timeLabel,
    this.status,
    this.imageBytes,
    this.onImageTap,
  });

  final bool isLocal;
  final String header;
  final String body;
  final bool locked;
  final String? timeLabel;
  final DeliveryStatus? status;
  final Uint8List? imageBytes;
  final VoidCallback? onImageTap;

  @override
  Widget build(BuildContext context) {
    final bg = isLocal
        ? AppTheme.brandDeep.withValues(alpha: 0.72)
        : AppTheme.elevated;
    final border = isLocal
        ? AppTheme.brandGreen.withValues(alpha: 0.36)
        : Colors.white.withValues(alpha: 0.08);

    return Align(
      alignment: isLocal ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
          minWidth: 76,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isLocal ? 14 : 4),
            bottomRight: Radius.circular(isLocal ? 4 : 14),
          ),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locked) ...[
                  Icon(
                    Icons.lock_rounded,
                    size: 12,
                    color: AppTheme.brandGreen.withValues(alpha: 0.95),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    header,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (imageBytes != null && imageBytes!.isNotEmpty) ...[
              GestureDetector(
                onTap: onImageTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Image.memory(
                        imageBytes!,
                        width: 230,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(body),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_full, size: 11, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Open',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  body,
                  style: TextStyle(
                    height: 1.32,
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ] else
              Text(
                body,
                style: const TextStyle(height: 1.34, fontSize: 15),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (timeLabel != null)
                  Text(
                    timeLabel!,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.44),
                    ),
                  ),
                if (isLocal && status != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    _statusIcon(status!),
                    size: 14,
                    color: status == DeliveryStatus.read
                        ? AppTheme.accentBlue
                        : Colors.white.withValues(alpha: 0.48),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(DeliveryStatus s) {
    switch (s) {
      case DeliveryStatus.sending:
        return Icons.schedule;
      case DeliveryStatus.sent:
        return Icons.check;
      case DeliveryStatus.delivered:
        return Icons.done_all;
      case DeliveryStatus.read:
        return Icons.done_all;
      case DeliveryStatus.failed:
        return Icons.error_outline;
    }
  }
}

String formatEpoch(int seconds) {
  if (seconds <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  final now = DateTime.now();
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${dt.month}/${dt.day} $hh:$mm';
}
