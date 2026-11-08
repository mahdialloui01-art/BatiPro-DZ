import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_theme.dart';

class _FieldSpec {
  final String key, label;
  final bool number;
  const _FieldSpec(this.key, this.label, {this.number = false});
}

class SectionScreen extends StatefulWidget {
  final String title;
  final IconData icon;
  const SectionScreen({super.key, required this.title, required this.icon});

  @override
  State<SectionScreen> createState() => _SectionScreenState();
}

class _SectionScreenState extends State<SectionScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _saving = false;
  String _kind = '';
  String _storageKey = '';

  List<_FieldSpec> get _fields {
    switch (_kind) {
      case 'purchases':
        return const [
          _FieldSpec('product', 'اسم المادة'),
          _FieldSpec('supplier', 'المورد'),
          _FieldSpec('quantity', 'الكمية', number: true),
          _FieldSpec('unitPrice', 'سعر الوحدة (دج)', number: true),
          _FieldSpec('paid', 'المبلغ المدفوع (دج)', number: true),
          _FieldSpec('reference', 'رقم وصل الشراء'),
        ];
      case 'customers':
        return const [
          _FieldSpec('name', 'اسم الزبون'),
          _FieldSpec('phone', 'رقم الهاتف'),
          _FieldSpec('address', 'العنوان'),
          _FieldSpec('note', 'ملاحظات'),
        ];
      case 'suppliers':
        return const [
          _FieldSpec('name', 'اسم المورد'),
          _FieldSpec('phone', 'رقم الهاتف'),
          _FieldSpec('address', 'العنوان'),
          _FieldSpec('note', 'ملاحظات'),
        ];
      case 'warehouses':
        return const [
          _FieldSpec('name', 'اسم المستودع'),
          _FieldSpec('location', 'الموقع'),
          _FieldSpec('manager', 'المسؤول'),
          _FieldSpec('note', 'ملاحظات'),
        ];
      case 'expenses':
        return const [
          _FieldSpec('label', 'بيان المصروف'),
          _FieldSpec('category', 'التصنيف'),
          _FieldSpec('amount', 'المبلغ (دج)', number: true),
          _FieldSpec('note', 'ملاحظات'),
        ];
      default:
        return const [];
    }
  }

  String get _emptyText {
    switch (_kind) {
      case 'purchases': return 'سجّل أول عملية شراء لتحديث رصيد المخزون';
      case 'customers': return 'أضف زبائنك واحتفظ بأرقامهم ومعلوماتهم';
      case 'suppliers': return 'أضف الموردين لتسهيل متابعة التعاملات';
      case 'warehouses': return 'أنشئ قائمة مستودعاتك ومواقع التخزين';
      case 'expenses': return 'سجّل مصاريف المحل لمراقبة التكاليف';
      default: return 'لا توجد بيانات مسجلة بعد';
    }
  }

  @override
  void initState() {
    super.initState();
    _kind = _resolveKind(widget.title);
    _storageKey = 'batipro_${_kind}_v1';
    _load();
  }

  String _resolveKind(String title) {
    if (title.contains('المشتريات')) return 'purchases';
    if (title.contains('الزبائن')) return 'customers';
    if (title.contains('الموردون')) return 'suppliers';
    if (title.contains('المستودعات')) return 'warehouses';
    if (title.contains('المصاريف')) return 'expenses';
    if (title.contains('التقارير')) return 'reports';
    if (title.contains('الإعدادات')) return 'settings';
    return 'general';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        _items = (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        _items = [];
      }
    }
    if (_kind == 'customers' || _kind == 'suppliers') {
      final ledgerKey = _kind == 'customers' ? 'batipro_sales_v1' : 'batipro_purchases_v1';
      final ledgerRaw = prefs.getString(ledgerKey);
      final balances = <String, double>{};
      if (ledgerRaw != null) {
        try {
          for (final entry in jsonDecode(ledgerRaw) as List) {
            final row = Map<String, dynamic>.from(entry as Map);
            final name = (_kind == 'customers' ? row['client'] : row['supplier'])
                ?.toString().trim();
            if (name == null || name.isEmpty || name == 'زبون نقدي') continue;
            final total = (row['total'] as num?)?.toDouble() ?? 0;
            final paid = (row['paid'] as num?)?.toDouble() ?? 0;
            balances[name.toLowerCase()] = (balances[name.toLowerCase()] ?? 0) +
                (total - paid).clamp(0, double.infinity).toDouble();
          }
        } catch (_) {}
      }
      for (final contact in _items) {
        final name = (contact['name'] ?? '').toString().trim().toLowerCase();
        contact['balance'] = balances[name] ?? 0;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_items));
  }

  String _money(double value) =>
      '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} دج';

  double _sum(String key) => _items.fold<double>(
      0, (sum, item) => sum + ((item[key] as num?)?.toDouble() ?? 0));

  List<Map<String, dynamic>> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) => item.values.any(
        (value) => value.toString().toLowerCase().contains(q))).toList();
  }

  Future<void> _openEditor([Map<String, dynamic>? old]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EntryEditor(
        title: widget.title,
        fields: _fields,
        initial: old,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      if (_kind == 'purchases') await _applyPurchaseToStock(result, old: old);
      setState(() {
        if (old == null) {
          result['id'] = DateTime.now().microsecondsSinceEpoch.toString();
          result['date'] = DateTime.now().toIso8601String();
          _items.insert(0, result);
        } else {
          final index = _items.indexWhere((e) => e['id'] == old['id']);
          if (index >= 0) _items[index] = {...result, 'id': old['id'], 'date': old['date']};
        }
      });
      await _persist();
      if (_kind == 'purchases') await _ensureSupplier(result['supplier']?.toString() ?? '');
      _toast(old == null ? 'تمت إضافة السجل بنجاح.' : 'تم تحديث السجل.');
    } catch (_) {
      _toast('تعذر حفظ البيانات. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _ensureSupplier(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('batipro_suppliers_v1');
    final suppliers = raw == null ? <Map<String, dynamic>>[] :
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final exists = suppliers.any((e) =>
        (e['name'] ?? '').toString().trim().toLowerCase() == clean.toLowerCase());
    if (!exists) {
      suppliers.insert(0, {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'name': clean,
        'phone': '',
        'address': '',
        'note': 'أضيف تلقائياً من سجل المشتريات',
      });
      await prefs.setString('batipro_suppliers_v1', jsonEncode(suppliers));
    }
  }

  Future<void> _applyPurchaseToStock(
      Map<String, dynamic> purchase, {Map<String, dynamic>? old}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('batipro_inventory_v1');
    if (raw == null) return;
    final stock = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();

    void adjust(String productName, double quantityDelta, double unitPrice,
        {bool addCost = true}) {
      final name = productName.trim().toLowerCase();
      if (name.isEmpty || quantityDelta == 0) return;
      final index = stock.indexWhere((p) =>
          (p['name'] ?? '').toString().trim().toLowerCase() == name);
      if (index < 0) return;
      final product = stock[index];
      final currentQuantity = (product['quantity'] as num).toDouble();
      final currentPrice = (product['purchasePrice'] as num).toDouble();
      if (quantityDelta > 0) {
        final nextQuantity = currentQuantity + quantityDelta;
        if (addCost && nextQuantity > 0) {
          product['purchasePrice'] =
              ((currentQuantity * currentPrice) + (quantityDelta * unitPrice)) / nextQuantity;
        }
        product['quantity'] = nextQuantity;
      } else {
        final nextQuantity = (currentQuantity + quantityDelta).clamp(0, double.infinity).toDouble();
        product['quantity'] = nextQuantity;
      }
    }

    if (old != null) {
      adjust((old['product'] ?? '').toString(),
          -((old['quantity'] as num?)?.toDouble() ?? 0),
          (old['unitPrice'] as num?)?.toDouble() ?? 0,
          addCost: false);
    }
    adjust((purchase['product'] ?? '').toString(),
        (purchase['quantity'] as num?)?.toDouble() ?? 0,
        (purchase['unitPrice'] as num?)?.toDouble() ?? 0);
    await prefs.setString('batipro_inventory_v1', jsonEncode(stock));
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف السجل؟'),
        content: const Text('هل تريد حذف هذا السجل نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (yes != true) return;
    if (_kind == 'purchases') {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('batipro_inventory_v1');
      if (raw != null) {
        final stock = (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final name = (item['product'] ?? '').toString().trim().toLowerCase();
        final index = stock.indexWhere((p) =>
            (p['name'] ?? '').toString().trim().toLowerCase() == name);
        if (index >= 0) {
          final product = stock[index];
          final current = (product['quantity'] as num).toDouble();
          final purchased = (item['quantity'] as num?)?.toDouble() ?? 0;
          product['quantity'] = (current - purchased).clamp(0, double.infinity);
          await prefs.setString('batipro_inventory_v1', jsonEncode(stock));
        }
      }
    }
    setState(() => _items.removeWhere((e) => e['id'] == item['id']));
    await _persist();
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;
              return SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BatiPro DZ', style: TextStyle(fontSize: 11, color: BatiProTheme.muted)),
                          const SizedBox(height: 4),
                          Text(widget.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: BatiProTheme.ink)),
                        ],
                      )),
                      if (_kind != 'reports' && _kind != 'settings')
                        FilledButton.icon(
                          onPressed: _saving ? null : () => _openEditor(),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(compact ? 'إضافة' : 'إضافة جديد'),
                        ),
                    ]),
                    const SizedBox(height: 20),
                    if (_kind == 'purchases') _buildPurchases(compact),
                    if (_kind == 'customers') _buildContacts(compact, customers: true),
                    if (_kind == 'suppliers') _buildContacts(compact, customers: false),
                    if (_kind == 'warehouses') _buildWarehouses(compact),
                    if (_kind == 'expenses') _buildExpenses(compact),
                    if (_kind == 'reports') _buildReports(compact),
                    if (_kind == 'settings') _buildSettings(),
                    if (_kind == 'general') _buildGeneral(),
                  ],
                ),
              );
            }),
    );
  }

  Widget _metric(String label, String value, IconData icon, {bool warning = false}) =>
      Card(child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: warning ? BatiProTheme.red : BatiProTheme.gold, size: 20),
          const Spacer(),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: BatiProTheme.ink))),
          Text(label, style: const TextStyle(fontSize: 10, color: BatiProTheme.muted)),
        ]),
      ));

  Widget _metrics(List<Widget> children, bool compact) => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: compact ? 2 : children.length.clamp(2, 4).toInt(),
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    childAspectRatio: compact ? 1.85 : 2.15,
    children: children,
  );

  Widget _searchBox(String hint) => TextField(
    controller: _search,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded)),
  );

  Widget _empty() => Card(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
    child: Center(child: Column(children: [
      Icon(widget.icon, size: 39, color: BatiProTheme.gold),
      const SizedBox(height: 10),
      Text(_emptyText, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: BatiProTheme.muted, height: 1.6)),
    ])),
  ));

  Widget _recordCard(Map<String, dynamic> item, String headline, String subtitle,
      String trailing, {String? status, Color? statusColor, Widget? action}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Row(children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(color: BatiProTheme.gold.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
            child: Icon(widget.icon, color: BatiProTheme.ink, size: 20)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(headline, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: BatiProTheme.ink)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: BatiProTheme.muted)),
            if (status != null) Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor ?? BatiProTheme.green)),
            ),
          ])),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(trailing, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
            if (action != null) action,
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              onSelected: (value) {
                if (value == 'edit') _openEditor(item);
                if (value == 'delete') _delete(item);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('تعديل')),
                PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _collectSupplierPayment(Map<String, dynamic> purchase) async {
    final total = (purchase['total'] as num?)?.toDouble() ?? 0;
    final paid = (purchase['paid'] as num?)?.toDouble() ?? 0;
    final due = (total - paid).clamp(0, double.infinity).toDouble();
    if (due <= 0) {
      _toast('هذا الوصل مدفوع بالكامل.');
      return;
    }
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل دفعة للمورد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'المبلغ (دج)', helperText: 'المتبقي: ${_money(due)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
            if (value == null || !value.isFinite || value <= 0 || value > due) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً لا يتجاوز المتبقي.')));
              return;
            }
            Navigator.pop(ctx, value);
          }, child: const Text('تأكيد الدفع')),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    final index = _items.indexWhere((e) => e['id'] == purchase['id']);
    if (index < 0) return;
    setState(() {
      _items[index] = {..._items[index], 'paid': paid + amount};
    });
    await _persist();
    _toast('تم تسجيل دفعة المورد وتحديث الرصيد.');
  }

  Widget _buildPurchases(bool compact) {
    final total = _sum('total');
    final paid = _sum('paid');
    final due = (total - paid).clamp(0, double.infinity).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _metrics([
        _metric('عمليات الشراء', _items.length.toString(), Icons.shopping_bag_outlined),
        _metric('إجمالي المشتريات', _money(total), Icons.receipt_long_outlined),
        _metric('المبلغ المدفوع', _money(paid), Icons.payments_outlined),
        _metric('المتبقي للموردين', _money(due), Icons.account_balance_wallet_outlined, warning: due > 0),
      ], compact),
      const SizedBox(height: 17),
      _searchBox('ابحث عن مادة أو مورد أو رقم وصل...'),
      const SizedBox(height: 13),
      const Text('سجل المشتريات', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
      const SizedBox(height: 10),
      if (_visible.isEmpty) _empty() else ..._visible.map((e) => _recordCard(
        e, (e['product'] ?? '').toString(),
        '${e['supplier'] ?? 'مورد غير محدد'} • كمية: ${e['quantity'] ?? 0} • ${e['reference'] ?? 'بدون رقم وصل'}',
        _money((e['total'] as num?)?.toDouble() ?? 0),
        status: 'المدفوع: ${_money((e['paid'] as num?)?.toDouble() ?? 0)} • المتبقي: ${_money((((e['total'] as num?)?.toDouble() ?? 0) - ((e['paid'] as num?)?.toDouble() ?? 0)).clamp(0, double.infinity).toDouble())}',
        action: IconButton(
          tooltip: 'تسجيل دفعة للمورد',
          onPressed: () => _collectSupplierPayment(e),
          icon: const Icon(Icons.payments_outlined, size: 19, color: BatiProTheme.green),
        ),
      )),
      const SizedBox(height: 8),
      const Text('عند مطابقة اسم المادة مع منتج موجود في المخزون، تتم إضافة الكمية تلقائياً ويُحدّث متوسط سعر الشراء.',
        style: TextStyle(fontSize: 10, color: BatiProTheme.muted, height: 1.5)),
    ]);
  }

  Widget _buildContacts(bool compact, {required bool customers}) {
    final due = _items.fold<double>(0, (s, e) => s + ((e['balance'] as num?)?.toDouble() ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _metrics([
        _metric(customers ? 'عدد الزبائن' : 'عدد الموردين', _items.length.toString(), customers ? Icons.groups_2_outlined : Icons.local_shipping_outlined),
        _metric('أرصدة مسجلة', _money(due), Icons.account_balance_wallet_outlined, warning: due > 0),
      ], compact),
      const SizedBox(height: 17),
      _searchBox(customers ? 'ابحث باسم الزبون أو الهاتف...' : 'ابحث باسم المورد أو الهاتف...'),
      const SizedBox(height: 13),
      Text(customers ? 'قائمة الزبائن' : 'قائمة الموردين',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
      const SizedBox(height: 10),
      if (_visible.isEmpty) _empty() else ..._visible.map((e) => _recordCard(
        e, (e['name'] ?? '').toString(),
        '${e['phone'] ?? 'بدون هاتف'} • ${e['address'] ?? 'بدون عنوان'}',
        (e['balance'] as num?) == null ? '—' : _money((e['balance'] as num).toDouble()),
        status: (e['note'] ?? '').toString().isEmpty ? null : e['note'].toString(),
      )),
      const SizedBox(height: 8),
      const Text('ملاحظة: تسجيل بيانات الاتصال متاح الآن؛ ربط أرصدة الزبائن والموردين بالفواتير والتحصيل سيكون في مرحلة الربط المحاسبي.',
        style: TextStyle(fontSize: 10, color: BatiProTheme.muted, height: 1.5)),
    ]);
  }

  Widget _buildWarehouses(bool compact) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _metrics([
      _metric('عدد المستودعات', _items.length.toString(), Icons.warehouse_outlined),
      _metric('المواقع المسجلة', _items.where((e) => (e['location'] ?? '').toString().isNotEmpty).length.toString(), Icons.location_on_outlined),
    ], compact),
    const SizedBox(height: 17),
    _searchBox('ابحث باسم المستودع أو الموقع...'),
    const SizedBox(height: 12),
    if (_visible.isEmpty) _empty() else ..._visible.map((e) => _recordCard(
      e, (e['name'] ?? '').toString(),
      '${e['location'] ?? 'الموقع غير محدد'} • المسؤول: ${e['manager'] ?? 'غير محدد'}',
      'مستودع',
      status: (e['note'] ?? '').toString().isEmpty ? null : e['note'].toString(),
    )),
    const Text('هذه المرحلة تحفظ بيانات المستودعات. توزيع كميات المنتجات بين المستودعات سيُضاف مع نظام التحويلات المخزنية.',
      style: TextStyle(fontSize: 10, color: BatiProTheme.muted, height: 1.5)),
  ]);

  Widget _buildExpenses(bool compact) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _metrics([
      _metric('عدد المصاريف', _items.length.toString(), Icons.receipt_long_outlined),
      _metric('إجمالي المصاريف', _money(_sum('amount')), Icons.payments_outlined),
    ], compact),
    const SizedBox(height: 17),
    _searchBox('ابحث في بيان المصروف أو التصنيف...'),
    const SizedBox(height: 12),
    if (_visible.isEmpty) _empty() else ..._visible.map((e) => _recordCard(
      e, (e['label'] ?? '').toString(),
      '${e['category'] ?? 'عام'} • ${(e['date'] ?? '').toString().split('T').first}',
      _money((e['amount'] as num?)?.toDouble() ?? 0),
      status: (e['note'] ?? '').toString().isEmpty ? null : e['note'].toString(),
    )),
  ]);

  Widget _buildReports(bool compact) {
    return FutureBuilder<Map<String, double>>(
      future: _readReportTotals(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, double>{};
        final sales = data['sales'] ?? 0;
        final purchases = data['purchases'] ?? 0;
        final expenses = data['expenses'] ?? 0;
        final paidSales = data['paidSales'] ?? 0;
        final net = sales - purchases - expenses;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('نظرة عامة على النشاط', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
          const SizedBox(height: 5),
          const Text('ملخص الأرقام المسجلة محلياً على هذا الجهاز', style: TextStyle(fontSize: 10, color: BatiProTheme.muted)),
          const SizedBox(height: 16),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            _metrics([
              _metric('المبيعات', _money(sales), Icons.point_of_sale_outlined),
              _metric('المشتريات', _money(purchases), Icons.shopping_bag_outlined),
              _metric('المصاريف', _money(expenses), Icons.receipt_long_outlined),
              _metric('المبالغ المحصلة', _money(paidSales), Icons.payments_outlined),
            ], compact),
            const SizedBox(height: 14),
            Card(child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('النتيجة التقديرية', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: BatiProTheme.ink)),
                const SizedBox(height: 8),
                Text(_money(net), style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: net >= 0 ? BatiProTheme.green : BatiProTheme.red)),
                const SizedBox(height: 5),
                const Text('المبيعات ناقص المشتريات والمصاريف المسجلة. هذا مؤشر مبسط وليس ربحاً محاسبياً نهائياً.',
                    style: TextStyle(fontSize: 10, color: BatiProTheme.muted, height: 1.5)),
              ]),
            )),
          ],
        ]);
      },
    );
  }

  Future<Map<String, double>> _readReportTotals() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> read(String key) {
      final raw = prefs.getString(key);
      if (raw == null) return [];
      try { return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(); }
      catch (_) { return []; }
    }
    final sales = read('batipro_sales_v1');
    final purchases = read('batipro_purchases_v1');
    final expenses = read('batipro_expenses_v1');
    double sum(List<Map<String, dynamic>> list, String key) =>
        list.fold<double>(0, (s, e) => s + ((e[key] as num?)?.toDouble() ?? 0));
    return {
      'sales': sum(sales, 'total'),
      'paidSales': sum(sales, 'paid'),
      'purchases': sum(purchases, 'total'),
      'expenses': sum(expenses, 'amount'),
    };
  }

  Widget _buildSettings() => _SettingsPanel();

  Widget _buildGeneral() => Card(child: Padding(
    padding: const EdgeInsets.all(22),
    child: Column(children: [
      Icon(widget.icon, size: 40, color: BatiProTheme.gold),
      const SizedBox(height: 12),
      Text('قسم ${widget.title}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
      const SizedBox(height: 7),
      const Text('سيتم توسيع هذا القسم ضمن مراحل تطوير BatiPro DZ القادمة.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: BatiProTheme.muted)),
    ]),
  ));
}

class _EntryEditor extends StatefulWidget {
  final String title;
  final List<_FieldSpec> fields;
  final Map<String, dynamic>? initial;
  const _EntryEditor({required this.title, required this.fields, this.initial});

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.fields)
        field.key: TextEditingController(text: widget.initial?[field.key]?.toString() ?? (field.key == 'paid' ? '0' : '')),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final result = <String, dynamic>{};
    for (final field in widget.fields) {
      final value = _controllers[field.key]!.text.trim();
      result[field.key] = field.number ? (double.tryParse(value.replaceAll(',', '.')) ?? 0) : value;
    }
    if (widget.title.contains('المشتريات')) {
      final quantity = (result['quantity'] as num).toDouble();
      final price = (result['unitPrice'] as num).toDouble();
      final paid = (result['paid'] as num).toDouble();
      result['total'] = quantity * price;
      if (paid > (result['total'] as num).toDouble()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المبلغ المدفوع أكبر من الإجمالي.')));
        return;
      }
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'إضافة إلى ${widget.title}' : 'تعديل السجل'),
    content: SizedBox(
      width: 430,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final field in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  controller: _controllers[field.key],
                  keyboardType: field.number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  decoration: InputDecoration(labelText: field.label),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
                    if (field.number) {
                      final n = double.tryParse(value.trim().replaceAll(',', '.'));
                      if (n == null || !n.isFinite || n < 0) return 'أدخل رقماً صحيحاً';
                    }
                    return null;
                  },
                ),
              ),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
    ],
  );
}

class _SettingsPanel extends StatefulWidget {
  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _currency = TextEditingController(text: 'DZD - الدينار الجزائري');
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _name.text = prefs.getString('batipro_shop_name') ?? 'محل مواد البناء';
    _phone.text = prefs.getString('batipro_shop_phone') ?? '';
    _address.text = prefs.getString('batipro_shop_address') ?? '';
    _currency.text = prefs.getString('batipro_currency') ?? 'DZD - الدينار الجزائري';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('batipro_shop_name', _name.text.trim());
    await prefs.setString('batipro_shop_phone', _phone.text.trim());
    await prefs.setString('batipro_shop_address', _address.text.trim());
    await prefs.setString('batipro_currency', _currency.text.trim());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات المحل.')));
  }

  Widget _field(TextEditingController controller, String label, {IconData? icon}) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)),
      ));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Card(child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('معلومات المحل', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
        const SizedBox(height: 14),
        _field(_name, 'اسم المحل', icon: Icons.storefront_outlined),
        _field(_phone, 'رقم الهاتف', icon: Icons.phone_outlined),
        _field(_address, 'العنوان', icon: Icons.location_on_outlined),
        _field(_currency, 'العملة', icon: Icons.payments_outlined),
        const SizedBox(height: 5),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ الإعدادات'),
        )),
        const SizedBox(height: 12),
        const Text('الإعدادات تُحفظ محلياً على الجهاز. النسخ الاحتياطي والمستخدمون والصلاحيات ستُضاف لاحقاً.',
            style: TextStyle(fontSize: 10, color: BatiProTheme.muted, height: 1.5)),
      ]),
    ));
  }
}
