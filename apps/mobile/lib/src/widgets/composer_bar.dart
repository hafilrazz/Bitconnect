import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared message composer with optional leading actions.
class ComposerBar extends StatelessWidget {
  const ComposerBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttach,
    this.onPrimaryAction,
    this.primaryIcon,
    this.primaryTooltip,
    this.hint = 'Message',
    this.enabled = true,
    this.primaryBusy = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onPrimaryAction;
  final IconData? primaryIcon;
  final String? primaryTooltip;
  final String hint;
  final bool enabled;
  final bool primaryBusy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (onPrimaryAction != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  child: IconButton.filledTonal(
                    tooltip: primaryTooltip,
                    onPressed: primaryBusy ? null : onPrimaryAction,
                    icon: primaryBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(primaryIcon ?? Icons.power_settings_new),
                  ),
                ),
              if (onAttach != null)
                Padding(
                  padding: const EdgeInsets.only(right: 2, bottom: 2),
                  child: IconButton(
                    tooltip: 'Photo',
                    onPressed: enabled ? onAttach : null,
                    icon: const Icon(Icons.image_outlined),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: hint,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: IconButton.filled(
                  onPressed: enabled ? onSend : null,
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
