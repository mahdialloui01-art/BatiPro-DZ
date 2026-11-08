import 'package:flutter/material.dart';
import '../app/app_theme.dart';
import '../widgets/section_header.dart';

class SectionScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  const SectionScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('BatiPro DZ', style: TextStyle(fontSize: 11, color: BatiProTheme.muted)),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: BatiProTheme.ink)),
              ])),
              CircleAvatar(backgroundColor: BatiProTheme.ink, child: const Text('م', style: TextStyle(color: Colors.white))),
            ]),
            const SizedBox(height: 24),
            SectionHeader(
              title: title,
              subtitle: 'إدارة ومتابعة $title بكل سهولة',
              actionLabel: 'إضافة جديد',
              onAction: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سيتم تفعيل نموذج الإضافة في المرحلة القادمة'))),
            ),
            const SizedBox(height: 18),
            TextField(
              decoration: InputDecoration(
                hintText: 'ابحث في $title...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(onPressed: () {}, icon: const Icon(Icons.tune_rounded)),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 38),
                child: Center(child: Column(children: [
                  Container(width: 68, height: 68, decoration: BoxDecoration(color: BatiProTheme.gold.withValues(alpha:.13), borderRadius: BorderRadius.circular(20)), child: Icon(icon, size: 32, color: BatiProTheme.ink)),
                  const SizedBox(height: 15),
                  Text('قسم $title جاهز للتطوير', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: BatiProTheme.ink)),
                  const SizedBox(height: 7),
                  const Text('تم تجهيز الواجهة الأساسية. سنضيف قاعدة البيانات والعمليات الفعلية ونماذج الإدخال في الخطوات القادمة.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: BatiProTheme.muted, height: 1.7)),
                  const SizedBox(height: 17),
                  OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.construction_outlined, size: 17), label: const Text('قيد التطوير')),
                ])),
              ),
            ),
            const SizedBox(height: 20),
            if (title.contains('المنتجات') || title.contains('المخزون')) const _ProductPreview(),
          ]),
        );
      }),
    );
  }
}

class _ProductPreview extends StatelessWidget {
  const _ProductPreview();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(17), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('أصناف نموذجية', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: BatiProTheme.ink)),
      const SizedBox(height: 14),
      const _ProductLine(name:'إسمنت عادي', unit:'كيس 50 كغ', quantity:'240 كيس'),
      const Divider(height: 20, color: BatiProTheme.line),
      const _ProductLine(name:'حديد تسليح 12 مم', unit:'قضيب 12 متر', quantity:'580 قضيب'),
      const Divider(height: 20, color: BatiProTheme.line),
      const _ProductLine(name:'آجر أحمر', unit:'حبة', quantity:'3,500 حبة'),
    ])),
  );
}

class _ProductLine extends StatelessWidget {
  final String name, unit, quantity;
  const _ProductLine({required this.name,required this.unit,required this.quantity});
  @override
  Widget build(BuildContext context) => Row(children: [
    const Icon(Icons.inventory_2_outlined, color: BatiProTheme.gold, size: 19),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BatiProTheme.ink)),
      Text(unit, style: const TextStyle(fontSize: 9, color: BatiProTheme.muted)),
    ])),
    Text(quantity, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: BatiProTheme.ink)),
  ]);
}
