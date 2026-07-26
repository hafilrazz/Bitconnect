import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.active,
    this.activeColor,
    this.icon,
  });

  final String label;
  final bool active;
  final Color? activeColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? (activeColor ?? AppTheme.brandGreen)
        : Colors.white.withValues(alpha: 0.45);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        color: active
            ? color.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ] else ...[
            Icon(
              active ? Icons.circle : Icons.circle_outlined,
              size: 8,
              color: color,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? color : Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}
