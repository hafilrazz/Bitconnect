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
        : Colors.white.withValues(alpha: 0.42);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: active ? 0.48 : 0.22)),
        color: active
            ? color.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.035),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? (active ? Icons.circle : Icons.circle_outlined),
            size: icon == null ? 8 : 13,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? color : Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}
