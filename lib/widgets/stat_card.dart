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
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned(
          left: -18, bottom: -24,
          child: Icon(icon, size: 100, color: color.withValues(alpha: .045)),
        ),
        Padding(
          padding: const EdgeInsets.all(17),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: color, size: 21),
              ),
              const Spacer(),
              Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 15),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BatiProTheme.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            FittedBox(alignment: Alignment.centerRight, fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(color: BatiProTheme.ink, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.4))),
            const SizedBox(height: 7),
            Text(note, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}
