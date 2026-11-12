import 'package:flutter/material.dart' hide Text;
import '../app/localized_text.dart';
import '../app/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, required this.subtitle, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: BatiProTheme.ink, letterSpacing: -.3)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: BatiProTheme.muted, height: 1.4)),
        ])),
        if (actionLabel != null)
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(actionLabel!),
          ),
      ],
    );
  }
}
