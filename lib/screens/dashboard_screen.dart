import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  double _todaySales = 0;
  double _purchasesTotal = 0;
  double _stockValue = 0;
  double _customerDebt = 0;
  int _todayInvoices = 0;
  int _purchaseCount = 0;
  List<Map<String, dynamic>> _lowStock = [];
  List<Map<String, dynamic>> _recentSales = [];
  List<Map<String, dynamic>> _sales = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _dateOf(Map<String, dynamic> row) {
    try {
      return DateTime.parse((row['date'] ?? '').toString());
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  double _number(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toDouble() ?? 0;

  List<Map<String, dynamic>> _readList(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final sales = _readList(prefs.getString('batipro_sales_v1'));
    final purchases = _readList(prefs.getString('batipro_purchases_v1'));
    final stock = _readList(prefs.getString('batipro_inventory_v1'));
    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final today = sales.where((row) => sameDay(_dateOf(row), now)).toList();
    final todaySales = today.fold<double>(0, (sum, row) => sum + _number(row, 'total'));
    final purchasesTotal = purchases.fold<double>(
        0, (sum, row) => sum + _number(row, 'total'));
    final stockValue = stock.fold<double>(
        0, (sum, row) => sum + _number(row, 'quantity') * _number(row, 'purchasePrice'));
    final debt = sales.fold<double>(
        0,
        (sum, row) => sum +
            (_number(row, 'total') - _number(row, 'paid'))
                .clamp(0, double.infinity).toDouble());

    final low = stock.where((row) =>
        _number(row, 'quantity') <= _number(row, 'minimum')).toList()
      ..sort((a, b) => _number(a, 'quantity').compareTo(_number(b, 'quantity')));
    sales.sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));

    const labels = ['اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد'];
    final weekly = <({String label, double amount})>[];
    for (var offset = 6; offset >= 0; offset--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: offset));
      final amount = sales.where((row) => sameDay(_dateOf(row), day))
          .fold<double>(0, (sum, row) => sum + _number(row, 'total'));
      weekly.add((label: labels[day.weekday - 1], amount: amount));
    }

    if (!mounted) return;
    setState(() {
      _todaySales = todaySales;
      _purchasesTotal = purchasesTotal;
      _stockValue = stockValue;
      _customerDebt = debt;
      _todayInvoices = today.length;
      _purchaseCount = purchases.length;
      _lowStock = low;
      _recentSales = sales.take(3).toList();
      _sales = sales;
      _loading = false;
    });
  }

  String _money(double value) =>
      '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} دج';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;
              return SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('مرحباً بك 👋', style: TextStyle(color: BatiProTheme.muted, fontSize: 12)),
                      SizedBox(height: 4),
                      Text('ملخص تجارتك اليوم', style: TextStyle(color: BatiProTheme.ink, fontSize: 23, fontWeight: FontWeight.w800)),
                    ])),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: BatiProTheme.line)),
                      child: const Icon(Icons.notifications_none_rounded, color: BatiProTheme.ink),
                    ),
                    const SizedBox(width: 9),
                    const CircleAvatar(backgroundColor: BatiProTheme.ink, child: Text('م', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 25),
                  const SectionHeader(title: 'لوحة القيادة', subtitle: 'نظرة عامة من عملياتك المسجلة'),
                  const SizedBox(height: 17),
                  GridView.count(
                    crossAxisCount: compact ? 2 : (constraints.maxWidth > 1150 ? 4 : 2),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: compact ? 1.22 : 1.45,
                    children: [
                      StatCard(label: 'مبيعات اليوم', value: _money(_todaySales), note: '$_todayInvoices فاتورة اليوم', icon: Icons.trending_up_rounded, color: BatiProTheme.green),
                      StatCard(label: 'المشتريات المسجلة', value: _money(_purchasesTotal), note: '$_purchaseCount عملية شراء', icon: Icons.shopping_bag_outlined, color: BatiProTheme.blue),
                      StatCard(label: 'قيمة المخزون', value: _money(_stockValue), note: 'حسب الكمية وسعر الشراء', icon: Icons.inventory_2_outlined, color: BatiProTheme.gold),
                      StatCard(label: 'ديون الزبائن', value: _money(_customerDebt), note: 'المتبقي من الفواتير', icon: Icons.account_balance_wallet_outlined, color: BatiProTheme.red),
                    ],
                  ),
                  const SizedBox(height: 23),
                  if (!compact)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: _SalesPanel(sales: _sales)),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: _AlertsPanel(items: _lowStock)),
                    ])
                  else ...[
                    _SalesPanel(values: _weeklySales),
                    const SizedBox(height: 14),
                    _AlertsPanel(items: _lowStock),
                  ],
                  const SizedBox(height: 22),
                  _RecentSales(items: _recentSales),
                  const SizedBox(height: 20),
                  const Text('BatiPro DZ • المؤشرات محسوبة من البيانات المحفوظة على الجهاز', style: TextStyle(color: BatiProTheme.muted, fontSize: 10)),
                ]),
              );
            }),
    );
  }
}

class _SalesPanel extends StatefulWidget {
  final List<Map<String, dynamic>> sales;
  const _SalesPanel({required this.sales});
  @override
  State<_SalesPanel> createState() => _SalesPanelState();
}
class _SalesPanelState extends State<_SalesPanel> {
  String _period = 'الأسبوع';
  DateTime _dateOf(Map<String, dynamic> row) {
    try { return DateTime.parse((row['date'] ?? '').toString()); }
    catch (_) { return DateTime.fromMillisecondsSinceEpoch(0); }
  }
  double _amount(Map<String, dynamic> row) => (row['total'] as num?)?.toDouble() ?? 0;
  List<({String label, double amount, int invoices, bool showLabel})> _buckets(DateTime now) {
    final result = <({String label, double amount, int invoices, bool showLabel})>[];
    void add(String label, DateTime start, DateTime end, {bool showLabel = true}) {
      final matching = widget.sales.where((row) {
        final date = _dateOf(row);
        return !date.isBefore(start) && date.isBefore(end);
      }).toList();
      result.add((label: label, amount: matching.fold<double>(0, (sum, row) => sum + _amount(row)), invoices: matching.length, showLabel: showLabel));
    }
    if (_period == 'اليوم') {
      for (var hour = 0; hour < 24; hour += 3) {
        add(hour.toString().padLeft(2, '0'), DateTime(now.year, now.month, now.day, hour), DateTime(now.year, now.month, now.day, hour + 3));
      }
    } else if (_period == 'الأسبوع') {
      const days = ['اثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      for (var i = 0; i < 7; i++) {
        final start = monday.add(Duration(days: i));
        add(days[i], start, start.add(const Duration(days: 1)));
      }
    } else if (_period == 'الشهر') {
      final days = DateTime(now.year, now.month + 1, 0).day;
      for (var i = 1; i <= days; i++) {
        final start = DateTime(now.year, now.month, i);
        add('$i', start, start.add(const Duration(days: 1)), showLabel: i == 1 || i % 5 == 0 || i == days);
      }
    } else {
      const months = ['جان', 'فيف', 'مار', 'أفر', 'ماي', 'جوان', 'جويل', 'أوت', 'سبت', 'أكت', 'نوف', 'ديس'];
      for (var month = 1; month <= 12; month++) {
        add(months[month - 1], DateTime(now.year, month, 1), DateTime(now.year, month + 1, 1));
      }
    }
    return result;
  }
  String _money(double value) => '\${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} دج';
  @override
  Widget build(BuildContext context) {
    final buckets = _buckets(DateTime.now());
    final total = buckets.fold<double>(0, (sum, item) => sum + item.amount);
    final invoiceCount = buckets.fold<int>(0, (sum, item) => sum + item.invoices);
    final maxAmount = buckets.fold<double>(0, (max, item) => item.amount > max ? item.amount : max);
    final compact = MediaQuery.sizeOf(context).width < 650;
    final slotWidth = _period == 'الشهر' ? 22.0 : 42.0;
    return Card(child: Padding(
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('حركة المبيعات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: BatiProTheme.ink)),
            SizedBox(height: 4),
            Text('تابع رقم معاملاتك حسب الفترة', style: TextStyle(fontSize: 10, color: BatiProTheme.muted)),
          ])),
          const Icon(Icons.bar_chart_rounded, color: BatiProTheme.gold, size: 23),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 6, runSpacing: 6, children: ['اليوم', 'الأسبوع', 'الشهر', 'العام'].map((period) {
          final selected = _period == period;
          return ChoiceChip(
            label: Text(period), selected: selected, showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _period = period),
            selectedColor: BatiProTheme.gold.withValues(alpha: .22),
            labelStyle: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: BatiProTheme.ink),
            side: BorderSide(color: selected ? BatiProTheme.gold : BatiProTheme.line),
          );
        }).toList()),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: BatiProTheme.canvas, borderRadius: BorderRadius.circular(13)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مجموع المبيعات • $_period', style: const TextStyle(fontSize: 10, color: BatiProTheme.muted)),
              const SizedBox(height: 5),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(_money(total), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: BatiProTheme.ink))),
            ])),
            Container(width: 1, height: 38, color: BatiProTheme.line),
            const SizedBox(width: 13),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الفواتير', style: TextStyle(fontSize: 10, color: BatiProTheme.muted)),
              const SizedBox(height: 5),
              Text('$invoiceCount', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
            ]),
          ]),
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(
          width: buckets.length * slotWidth < 280 ? 280 : buckets.length * slotWidth,
          height: 151,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [for (final item in buckets)
              SizedBox(width: slotWidth, child: _SalesBar(
                label: item.label, amount: item.amount, maxAmount: maxAmount,
                showLabel: item.showLabel, compactLabel: _period == 'الشهر',
              )),
            ],
          ),
        )),
        const SizedBox(height: 8),
        const Row(children: [
          Icon(Icons.info_outline, size: 13, color: BatiProTheme.muted),
          SizedBox(width: 5),
          Expanded(child: Text('القيم محسوبة من فواتير البيع المسجلة في الفترة المختارة.', style: TextStyle(fontSize: 9, color: BatiProTheme.muted))),
        ]),
      ]),
    ));
  }
}
class _SalesBar extends StatelessWidget {
  final String label;
  final double amount, maxAmount;
  final bool showLabel, compactLabel;
  const _SalesBar({required this.label, required this.amount, required this.maxAmount, required this.showLabel, required this.compactLabel});
  @override
  Widget build(BuildContext context) {
    final barHeight = maxAmount <= 0 ? 4.0 : (amount / maxAmount * 91).clamp(4.0, 91.0).toDouble();
    return Tooltip(
      message: '$label • \${amount.toStringAsFixed(0)} دج',
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        SizedBox(height: 99, child: Align(alignment: Alignment.bottomCenter, child: Container(
          width: compactLabel ? 10 : 19, height: barHeight,
          decoration: BoxDecoration(color: amount > 0 ? BatiProTheme.gold : const Color(0xFFDCE5EA), borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
        ))),
        const SizedBox(height: 7),
        SizedBox(height: 15, child: Text(showLabel ? label : '', maxLines: 1, style: const TextStyle(fontSize: 9, color: BatiProTheme.muted))),
      ]),
    );
  }
}
class _AlertsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _AlertsPanel({required this.items});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('تنبيهات المخزون', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: BatiProTheme.ink)),
      const SizedBox(height: 5),
      const Text('منتجات وصلت للحد الأدنى', style: TextStyle(fontSize: 10, color: BatiProTheme.muted)),
      const SizedBox(height: 15),
      if (items.isEmpty)
        const Text('لا توجد منتجات تحت حد التنبيه حالياً.', style: TextStyle(fontSize: 11, color: BatiProTheme.green))
      else
        for (var i = 0; i < items.length && i < 5; i++) ...[
          if (i > 0) const Divider(height: 20, color: BatiProTheme.line),
          _alert(
            (items[i]['name'] ?? 'منتج').toString(),
            '${items[i]['quantity'] ?? 0} ${items[i]['unit'] ?? ''} متبقية',
            BatiProTheme.red,
          ),
        ],
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
  final List<Map<String, dynamic>> items;
  const _RecentSales({required this.items});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('آخر عمليات البيع', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: BatiProTheme.ink)),
      const SizedBox(height: 15),
      if (items.isEmpty)
        const Text('لا توجد فواتير بيع مسجلة بعد.', style: TextStyle(fontSize: 11, color: BatiProTheme.muted))
      else
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 18, color: BatiProTheme.line),
          _SaleRow(
            code: (items[i]['id'] ?? '').toString(),
            client: (items[i]['client'] ?? 'زبون نقدي').toString(),
            amount: '${((items[i]['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} دج',
            status: (((items[i]['total'] as num?)?.toDouble() ?? 0) - ((items[i]['paid'] as num?)?.toDouble() ?? 0)) <= 0
                ? 'مدفوعة'
                : ((items[i]['paid'] as num?)?.toDouble() ?? 0) > 0 ? 'جزئية' : 'على الحساب',
            color: (((items[i]['total'] as num?)?.toDouble() ?? 0) - ((items[i]['paid'] as num?)?.toDouble() ?? 0)) <= 0
                ? BatiProTheme.green : BatiProTheme.gold,
          ),
        ],
    ])),
  );
}

class _SaleRow extends StatelessWidget {
  final String code, client, amount, status;
  final Color color;
  const _SaleRow({required this.code, required this.client, required this.amount, required this.status, required this.color});

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
    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(20)), child: Text(status, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700))),
  ]);
}
