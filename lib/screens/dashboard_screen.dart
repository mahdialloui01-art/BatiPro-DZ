import 'package:flutter/material.dart';
import '../app/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('مرحباً بك 👋', style: TextStyle(color: BatiProTheme.muted, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('ملخص تجارتك اليوم', style: TextStyle(color: BatiProTheme.ink, fontSize: 23, fontWeight: FontWeight.w800)),
              ])),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: BatiProTheme.line)),
                child: const Icon(Icons.notifications_none_rounded, color: BatiProTheme.ink),
              ),
              const SizedBox(width: 9),
              CircleAvatar(backgroundColor: BatiProTheme.ink, child: const Text('م', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 25),
            const SectionHeader(title: 'لوحة القيادة', subtitle: 'نظرة عامة على أداء المحل والمستودع'),
            const SizedBox(height: 17),
            GridView.count(
              crossAxisCount: compact ? 2 : (constraints.maxWidth > 1150 ? 4 : 2),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: compact ? 1.22 : 1.45,
              children: const [
                StatCard(label: 'مبيعات اليوم', value: '128,500 دج', note: '↑ 12% مقارنة بالأمس', icon: Icons.trending_up_rounded, color: BatiProTheme.green),
                StatCard(label: 'المشتريات', value: '74,000 دج', note: 'عمليات هذا اليوم', icon: Icons.shopping_bag_outlined, color: BatiProTheme.blue),
                StatCard(label: 'قيمة المخزون', value: '2.8 مليون دج', note: 'حسب أسعار التكلفة', icon: Icons.inventory_2_outlined, color: BatiProTheme.gold),
                StatCard(label: 'ديون الزبائن', value: '315,000 دج', note: 'تحتاج إلى متابعة', icon: Icons.account_balance_wallet_outlined, color: BatiProTheme.red),
              ],
            ),
            const SizedBox(height: 23),
            if (!compact) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: _SalesPanel()),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: _AlertsPanel()),
            ]) else ...[
              _SalesPanel(),
              const SizedBox(height: 14),
              _AlertsPanel(),
            ],
            const SizedBox(height: 22),
            _RecentSales(),
            const SizedBox(height: 20),
            const Text('BatiPro DZ • نسخة أولية لتصميم الواجهة', style: TextStyle(color: BatiProTheme.muted, fontSize: 10)),
          ]),
        );
      }),
    );
  }
}

class _SalesPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('حركة المبيعات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: BatiProTheme.ink)),
          SizedBox(height: 4),
          Text('آخر 7 أيام', style: TextStyle(fontSize: 10, color: BatiProTheme.muted)),
        ])),
        Text('هذا الأسبوع', style: TextStyle(color: BatiProTheme.muted, fontSize: 10)),
      ]),
      const SizedBox(height: 20),
      SizedBox(height: 145, child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: const [
        _Bar(day:'سبت',height:65), _Bar(day:'أحد',height:91), _Bar(day:'إثنين',height:73),
        _Bar(day:'ثلاثاء',height:116,active:true), _Bar(day:'أربعاء',height:83), _Bar(day:'خميس',height:102), _Bar(day:'جمعة',height:53),
      ])),
    ])),
  );
}

class _Bar extends StatelessWidget {
  final String day; final double height; final bool active;
  const _Bar({required this.day, required this.height, this.active = false});
  @override
  Widget build(BuildContext context) => Column(mainAxisAlignment: MainAxisAlignment.end, children: [
    Container(width: 19, height: height, decoration: BoxDecoration(color: active ? BatiProTheme.gold : const Color(0xFFDCE5EA), borderRadius: const BorderRadius.vertical(top: Radius.circular(6)))),
    const SizedBox(height: 8),
    Text(day, style: const TextStyle(fontSize: 9, color: BatiProTheme.muted)),
  ]);
}

class _AlertsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('تنبيهات المخزون', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: BatiProTheme.ink)),
      const SizedBox(height: 5),
      const Text('منتجات وصلت للحد الأدنى', style: TextStyle(fontSize: 10, color: BatiProTheme.muted)),
      const SizedBox(height: 15),
      _alert('إسمنت مقاوم', '8 أكياس متبقية', BatiProTheme.red),
      const Divider(height: 20, color: BatiProTheme.line),
      _alert('حديد 12 مم', '120 قضيب متبقي', BatiProTheme.gold),
      const Divider(height: 20, color: BatiProTheme.line),
      _alert('طلاء أبيض 15L', '4 علب متبقية', BatiProTheme.red),
    ])),
  );
  Widget _alert(String name, String qty, Color color) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 9),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BatiProTheme.ink)),
      const SizedBox(height: 3),
      Text(qty, style: const TextStyle(fontSize: 10, color: BatiProTheme.muted)),
    ])),
    const Icon(Icons.chevron_left, color: BatiProTheme.muted, size: 17),
  ]);
}

class _RecentSales extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('آخر عمليات البيع', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: BatiProTheme.ink)),
      const SizedBox(height: 15),
      const _SaleRow(code:'#INV-0248', client:'مؤسسة البناء الحديث', amount:'45,000 دج', status:'مدفوعة', color:BatiProTheme.green),
      const Divider(height: 18, color: BatiProTheme.line),
      const _SaleRow(code:'#INV-0247', client:'محمد بوعلام', amount:'18,500 دج', status:'جزئية', color:BatiProTheme.gold),
      const Divider(height: 18, color: BatiProTheme.line),
      const _SaleRow(code:'#INV-0246', client:'مقاولات النور', amount:'72,000 دج', status:'مدفوعة', color:BatiProTheme.green),
    ])),
  );
}

class _SaleRow extends StatelessWidget {
  final String code, client, amount, status; final Color color;
  const _SaleRow({required this.code,required this.client,required this.amount,required this.status,required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    const Icon(Icons.receipt_long_outlined, color: BatiProTheme.muted, size: 19),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(client, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BatiProTheme.ink)),
      Text(code, style: const TextStyle(fontSize: 9, color: BatiProTheme.muted)),
    ])),
    Text(amount, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BatiProTheme.ink)),
    const SizedBox(width: 9),
    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha:.10), borderRadius: BorderRadius.circular(20)), child: Text(status, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700))),
  ]);
}
