import 'package:flutter/material.dart';
import '../app/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;
  const StatCard({super.key, required this.label, required this.value, required this.note, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: color, size: 20)),
            const Spacer(),
            const Icon(Icons.more_horiz, color: BatiProTheme.muted, size: 20),
          ]),
          const SizedBox(height: 15),
          Text(label, style: const TextStyle(color: BatiProTheme.muted, fontSize: 11.5)),
          const SizedBox(height: 5),
          FittedBox(alignment: Alignment.centerRight, fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(color: BatiProTheme.ink, fontSize: 23, fontWeight: FontWeight.w800))),
          const SizedBox(height: 7),
          Text(note, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
