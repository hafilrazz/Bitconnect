import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact pill-style status indicator.
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
    return Semantics(
      label: '$label status',
      value: active ? 'active' : 'inactive',
      readOnly: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: color.withValues(alpha: active ? 0.50 : 0.20),
          ),
          color: active
              ? color.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.04),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
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
      ),
    );
  }
}
