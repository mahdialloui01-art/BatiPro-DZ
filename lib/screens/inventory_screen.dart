import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_theme.dart';

class _Product {
  final String id, name, category, unit;
  final double quantity, minimum, purchasePrice, salePrice;
  final double? steelWeightKg, pieceWeightKg, diameterMm, lengthM;
  const _Product({required this.id, required this.name, required this.category, required this.unit, required this.quantity, required this.minimum, required this.purchasePrice, required this.salePrice, this.steelWeightKg, this.pieceWeightKg, this.diameterMm, this.lengthM});
  factory _Product.fromJson(Map<String, dynamic> j) => _Product(
    id: j['id'] as String, name: j['name'] as String, category: j['category'] as String,
    unit: j['unit'] as String, quantity: (j['quantity'] as num).toDouble(),
    minimum: (j['minimum'] as num).toDouble(), purchasePrice: (j['purchasePrice'] as num).toDouble(),
    salePrice: (j['salePrice'] as num).toDouble(),
    steelWeightKg: (j['steelWeightKg'] as num?)?.toDouble(),
    pieceWeightKg: (j['pieceWeightKg'] as num?)?.toDouble(),
    diameterMm: (j['diameterMm'] as num?)?.toDouble(),
    lengthM: (j['lengthM'] as num?)?.toDouble(),
  );
  Map<String, dynamic> toJson() => {'id':id,'name':name,'category':category,'unit':unit,'quantity':quantity,'minimum':minimum,'purchasePrice':purchasePrice,'salePrice':salePrice,'steelWeightKg':steelWeightKg,'pieceWeightKg':pieceWeightKg,'diameterMm':diameterMm,'lengthM':lengthM};
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}


class _ProductEditorDialog extends StatefulWidget {
  final _Product? product;
  const _ProductEditorDialog({this.product});

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  static const _categories = <String>[
    'مواد البناء', 'الإسمنت', 'الآجر', 'الرمل والحصى', 'الحديد', 'الحديد تسليح',
    'سلك رباط', 'شبك ملحوم', 'حديد دائري مصمت', 'حديد مربع أو مستطيل مصمت',
    'أنبوب دائري', 'أنبوب مربع أو مستطيل', 'عوارض IPE', 'عوارض HEA',
    'عوارض IPN', 'زوايا حديد L', 'مقاطع UPN / UPE', 'صفائح وألواح حديد',
    'فلات بار (حديد مسطح)', 'قضبان ملولبة', 'مسامير وبراغي', 'حديد آخر',
  ];
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _minimum;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _salePrice;
  late final TextEditingController _weight;
  late final TextEditingController _diameter;
  late final TextEditingController _length;
  late final TextEditingController _pieceWeight;
  late String _category;
  late String _weightUnit;

  bool get _isSteel => _categories.skip(4).contains(_category);
  bool get _usesDiameter => _category == 'الحديد تسليح' || _category == 'حديد دائري مصمت';

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _category = _categories.contains(p?.category) ? p!.category : (p?.category ?? 'مواد البناء');
    _quantity = TextEditingController(text: p?.quantity.toString() ?? '0');
    _minimum = TextEditingController(text: p?.minimum.toString() ?? '5');
    _purchasePrice = TextEditingController(text: p?.purchasePrice.toString() ?? '0');
    _salePrice = TextEditingController(text: p?.salePrice.toString() ?? '0');
    _weight = TextEditingController(text: p?.steelWeightKg?.toString() ?? '0');
    _diameter = TextEditingController(text: p?.diameterMm?.toString() ?? '12');
    _length = TextEditingController(text: p?.lengthM?.toString() ?? '12');
    _pieceWeight = TextEditingController(text: p?.pieceWeightKg?.toString() ?? '');
    _weightUnit = 'kg';
  }

  @override
  void dispose() {
    for (final c in [_name, _quantity, _minimum, _purchasePrice, _salePrice, _weight, _diameter, _length, _pieceWeight]) {
      c.dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  Widget _field(TextEditingController controller, String label, {bool numeric = false, String? helper}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label, helperText: helper),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
          if (numeric) {
            final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
            if (parsed == null || !parsed.isFinite || parsed < 0) return 'أدخل رقماً صحيحاً';
          }
          return null;
        },
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final p = widget.product;
    var finalQuantity = _number(_quantity);
    var finalUnit = p?.unit ?? 'وحدة';
    var finalCategory = _category;
    if (_isSteel) {
      final enteredWeight = _number(_weight);
      final weightKg = enteredWeight * (_weightUnit == 'ton' ? 1000 : 1);
      final lengthM = _number(_length);
      final diameterMm = _number(_diameter);
      final manualPieceWeight = _number(_pieceWeight);
      double pieceWeightKg;
      if (_usesDiameter) {
        if (diameterMm <= 0 || lengthM <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل قطر الحديد وطول القضيب بشكل صحيح.')));
          return;
        }
        pieceWeightKg = (3.141592653589793 / 4) *
            (diameterMm / 1000) * (diameterMm / 1000) * lengthM * 7850;
      } else {
        pieceWeightKg = manualPieceWeight;
        if (pieceWeightKg <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل وزن القطعة الواحدة بالكيلوغرام لهذا النوع من الحديد.')));
          return;
        }
      }
      if (weightKg <= 0 || !weightKg.isFinite || !pieceWeightKg.isFinite) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل وزناً صحيحاً أكبر من صفر.')));
        return;
      }
      finalQuantity = weightKg / pieceWeightKg;
      finalUnit = _usesDiameter ? 'قضيب' : 'قطعة';
      if (!finalQuantity.isFinite || finalQuantity <= 0) return;
    } else {
      finalUnit = p?.unit ?? 'وحدة';
    }
    Navigator.of(context).pop(_Product(
      id: p?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      category: finalCategory,
      unit: finalUnit,
      quantity: finalQuantity,
      minimum: _isSteel ? _number(_minimum) : _number(_minimum),
      purchasePrice: _number(_purchasePrice),
      salePrice: _number(_salePrice),
      steelWeightKg: _isSteel ? _number(_weight) * (_weightUnit == 'ton' ? 1000 : 1) : null,
      pieceWeightKg: _isSteel ? (_usesDiameter
          ? (3.141592653589793 / 4) * (_number(_diameter) / 1000) * (_number(_diameter) / 1000) * _number(_length) * 7850
          : _number(_pieceWeight)) : null,
      diameterMm: _isSteel && _usesDiameter ? _number(_diameter) : null,
      lengthM: _isSteel ? _number(_length) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'إضافة منتج للمخزون' : 'تعديل المنتج'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(_name, 'اسم المنتج'),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<String>(
                  value: _categories.contains(_category) ? _category : 'مواد البناء',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الصنف / نوع الحديد'),
                  items: _categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setState(() => _category = v ?? 'مواد البناء'),
                ),
              ),
              if (_isSteel) ...[
                Row(children: [
                  Expanded(child: _field(_weight, 'الوزن المضاف', numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: DropdownButtonFormField<String>(
                    value: _weightUnit,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                    items: const [
                      DropdownMenuItem(value: 'kg', child: Text('كيلوغرام')),
                      DropdownMenuItem(value: 'ton', child: Text('طن')),
                    ],
                    onChanged: (v) => setState(() => _weightUnit = v ?? 'kg'),
                  )),
                ]),
                if (_usesDiameter) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<String>(
                      value: const ['8', '10', '12', '14', '16', '20', '25', '32'].contains(_diameter.text)
                          ? _diameter.text : '12',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'مقاس حديد التسليح',
                        helperText: 'اختر T8 أو T10 أو T12 أو T14 أو T16 أو T20 أو T25 أو T32',
                      ),
                      items: const [
                        DropdownMenuItem(value: '8', child: Text('T8 — قطر 8 ملم')),
                        DropdownMenuItem(value: '10', child: Text('T10 — قطر 10 ملم')),
                        DropdownMenuItem(value: '12', child: Text('T12 — قطر 12 ملم')),
                        DropdownMenuItem(value: '14', child: Text('T14 — قطر 14 ملم')),
                        DropdownMenuItem(value: '16', child: Text('T16 — قطر 16 ملم')),
                        DropdownMenuItem(value: '20', child: Text('T20 — قطر 20 ملم')),
                        DropdownMenuItem(value: '25', child: Text('T25 — قطر 25 ملم')),
                        DropdownMenuItem(value: '32', child: Text('T32 — قطر 32 ملم')),
                      ],
                      onChanged: (v) => setState(() => _diameter.text = v ?? '12'),
                    ),
                  ),
                  _field(_length, 'طول القضيب بالمتر', numeric: true, helper: 'الطول الافتراضي 12 متر ويمكن تغييره'),
                ] else
                  _field(_pieceWeight, 'وزن القطعة الواحدة بالكيلوغرام', numeric: true,
                    helper: 'أدخل الوزن الحقيقي حسب مقاس وسماكة الأنبوب أو المقطع أو الصفيحة'),
                const SizedBox(height: 2),
                const Text('سيحوّل البرنامج الوزن تلقائياً إلى عدد قضبان/قطع ويضيف الناتج إلى المخزون.',
                  style: TextStyle(fontSize: 11, color: BatiProTheme.green)),
              ] else ...[
                _field(_quantity, 'الكمية', numeric: true),
              ],
              Row(children: [
                Expanded(child: _field(_minimum, 'حد التنبيه', numeric: true)),
                const SizedBox(width: 8),
                Expanded(child: _field(_purchasePrice, 'سعر الشراء للقضيب/الوحدة', numeric: true)),
              ]),
              _field(_salePrice, 'سعر البيع للقضيب/الوحدة', numeric: true),
              if (_isSteel)
                const Text('وزن القضيب الدائري يُحسب بالقطر والطول وكثافة الحديد 7850 كغ/م³. الأنواع ذات المقاطع المختلفة تعتمد وزن القطعة الذي تدخله.',
                  style: TextStyle(fontSize: 10, color: BatiProTheme.muted, height: 1.4)),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: _save, child: const Text('حفظ المخزون')),
      ],
    );
  }
}

class _InventoryScreenState extends State<InventoryScreen> {
  static const _storageKey = 'batipro_inventory_v1';
  final _search = TextEditingController();
  List<_Product> _products = [];
  bool _loading = true;
  String _filter = 'الكل';

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try { _products = (jsonDecode(raw) as List).map((e) => _Product.fromJson(Map<String,dynamic>.from(e as Map))).toList(); }
      catch (_) { _products = []; }
    }
    if (_products.isEmpty && raw == null) {
      _products = [
        const _Product(id:'seed-1',name:'إسمنت عادي',category:'الإسمنت',unit:'كيس',quantity:240,minimum:30,purchasePrice:550,salePrice:650),
        const _Product(id:'seed-2',name:'حديد تسليح 12 مم',category:'الحديد',unit:'قضيب',quantity:580,minimum:80,purchasePrice:850,salePrice:980),
        const _Product(id:'seed-3',name:'آجر أحمر',category:'الآجر',unit:'حبة',quantity:3500,minimum:500,purchasePrice:18,salePrice:23),
      ];
      await _save();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_products.map((p) => p.toJson()).toList()));
  }

  List<_Product> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _products.where((p) {
      final matches = p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q);
      final low = _filter == 'نقص المخزون';
      final categoryMatch = _filter == 'الكل' || low || p.category == _filter;
      return matches && categoryMatch && (!low || p.quantity <= p.minimum);
    }).toList();
  }

  String _money(double n) => '${n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2)} دج';
  Future<void> _edit([_Product? old]) async {
    final result = await showDialog<_Product>(
      context: context,
      builder: (_) => _ProductEditorDialog(product: old),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _products.indexWhere((e) => e.id == result.id);
      if (index < 0) {
        _products.insert(0, result);
      } else {
        _products[index] = result;
      }
    });
    await _save();
  }


  Future<void> _delete(_Product p) async {
    final yes = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('حذف المنتج؟'),content:Text('سيتم حذف ${p.name} من القائمة.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف'))]));
    if(yes==true){setState(()=>_products.removeWhere((e)=>e.id==p.id));await _save();}
  }

  @override
  Widget build(BuildContext context) {
    final low = _products.where((p)=>p.quantity<=p.minimum).length;
    final total = _products.fold<double>(0,(s,p)=>s+p.quantity*p.purchasePrice);
    return SafeArea(child:_loading?const Center(child:CircularProgressIndicator()):LayoutBuilder(builder:(context,c)=>SingleChildScrollView(
      padding:EdgeInsets.all(c.maxWidth<650?16:28),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('BatiPro DZ',style:TextStyle(color:BatiProTheme.muted,fontSize:11)),
          SizedBox(height:4),Text('المنتجات والمخزون',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800,color:BatiProTheme.ink)),
        ])),FilledButton.icon(onPressed:()=>_edit(),icon:const Icon(Icons.add),label:const Text('إضافة'))]),
        const SizedBox(height:20),
        GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:c.maxWidth<600?2:3,childAspectRatio:c.maxWidth<600?1.8:2.2,crossAxisSpacing:10,mainAxisSpacing:10,children:[
          _metric('عدد المنتجات','${_products.length}',Icons.inventory_2_outlined),
          _metric('نقص المخزون','$low',Icons.warning_amber_rounded),
          _metric('قيمة المخزون',_money(total),Icons.account_balance_wallet_outlined),
        ]),
        const SizedBox(height:18),
        TextField(controller:_search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(hintText:'ابحث عن منتج أو صنف...',prefixIcon:Icon(Icons.search))),
        const SizedBox(height:10),
        Wrap(spacing:8,runSpacing:6,children:['الكل','نقص المخزون',..._products.map((p)=>p.category).toSet().toList()].map((v)=>ChoiceChip(label:Text(v),selected:_filter==v,onSelected:(_)=>setState(()=>_filter=v))).toList()),
        const SizedBox(height:12),
        if(_visible.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(30),child:Center(child:Text('لا توجد منتجات مطابقة'))))
        else ..._visible.map((p)=>Card(margin:const EdgeInsets.only(bottom:9),child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
          Container(width:42,height:42,decoration:BoxDecoration(color:BatiProTheme.gold.withValues(alpha:.14),borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.inventory_2_outlined,color:BatiProTheme.ink)),
          const SizedBox(width:11),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(p.name,style:const TextStyle(fontWeight:FontWeight.w800,color:BatiProTheme.ink)),
            Text('${p.category} • ${p.unit} | شراء: ${_money(p.purchasePrice)} | بيع: ${_money(p.salePrice)}',style:const TextStyle(fontSize:10,color:BatiProTheme.muted)),
            const SizedBox(height:5),Text('المتوفر: ${p.quantity} ${p.unit} • حد التنبيه: ${p.minimum}',style:TextStyle(fontSize:11,color:p.quantity<=p.minimum?BatiProTheme.red:BatiProTheme.green,fontWeight:FontWeight.w700)),
          ])),
          PopupMenuButton<String>(onSelected:(v){if(v=='edit')_edit(p);if(v=='delete')_delete(p);},itemBuilder:(_)=>const [
            PopupMenuItem(value:'edit',child:Text('تعديل')),PopupMenuItem(value:'delete',child:Text('حذف')),
          ]),
        ])))),
        const SizedBox(height:20),
        const Text('البيانات محفوظة محلياً على هذا الجهاز، ويمكن استعمال القسم دون إنترنت.',style:TextStyle(color:BatiProTheme.muted,fontSize:11)),
      ]),
    )));
  }

  Widget _metric(String label,String value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Icon(icon,color:BatiProTheme.gold,size:19),const Spacer(),Text(value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800,color:BatiProTheme.ink)),Text(label,style:const TextStyle(fontSize:10,color:BatiProTheme.muted)),
  ])));
}
