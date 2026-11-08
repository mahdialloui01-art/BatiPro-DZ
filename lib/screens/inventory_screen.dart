import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_theme.dart';

class _Product {
  final String id, name, category, unit;
  final double quantity, minimum, purchasePrice, salePrice;
  const _Product({required this.id, required this.name, required this.category, required this.unit, required this.quantity, required this.minimum, required this.purchasePrice, required this.salePrice});
  factory _Product.fromJson(Map<String, dynamic> j) => _Product(
    id: j['id'] as String, name: j['name'] as String, category: j['category'] as String,
    unit: j['unit'] as String, quantity: (j['quantity'] as num).toDouble(),
    minimum: (j['minimum'] as num).toDouble(), purchasePrice: (j['purchasePrice'] as num).toDouble(),
    salePrice: (j['salePrice'] as num).toDouble(),
  );
  Map<String, dynamic> toJson() => {'id':id,'name':name,'category':category,'unit':unit,'quantity':quantity,'minimum':minimum,'purchasePrice':purchasePrice,'salePrice':salePrice};
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _unit;
  late final TextEditingController _quantity;
  late final TextEditingController _minimum;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _salePrice;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? 'مواد البناء');
    _unit = TextEditingController(text: p?.unit ?? 'وحدة');
    _quantity = TextEditingController(text: p?.quantity.toString() ?? '0');
    _minimum = TextEditingController(text: p?.minimum.toString() ?? '5');
    _purchasePrice = TextEditingController(text: p?.purchasePrice.toString() ?? '0');
    _salePrice = TextEditingController(text: p?.salePrice.toString() ?? '0');
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    _quantity.dispose();
    _minimum.dispose();
    _purchasePrice.dispose();
    _salePrice.dispose();
    super.dispose();
  }

  double _number(TextEditingController c) =>
      double.parse(c.text.trim().replaceAll(',', '.'));

  Widget _field(TextEditingController controller, String label, {bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
          if (numeric) {
            final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
            if (parsed == null || !parsed.isFinite || parsed < 0) {
              return 'أدخل رقماً صحيحاً';
            }
          }
          return null;
        },
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final p = widget.product;
    Navigator.of(context).pop(_Product(
      id: p?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      category: _category.text.trim(),
      unit: _unit.text.trim(),
      quantity: _number(_quantity),
      minimum: _number(_minimum),
      purchasePrice: _number(_purchasePrice),
      salePrice: _number(_salePrice),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'إضافة منتج' : 'تعديل المنتج'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_name, 'اسم المنتج'),
                _field(_category, 'الصنف'),
                _field(_unit, 'وحدة القياس'),
                Row(children: [
                  Expanded(child: _field(_quantity, 'الكمية', numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_minimum, 'حد التنبيه', numeric: true)),
                ]),
                Row(children: [
                  Expanded(child: _field(_purchasePrice, 'سعر الشراء', numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_salePrice, 'سعر البيع', numeric: true)),
                ]),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
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
      return matches && (!low || p.quantity <= p.minimum);
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
        Wrap(spacing:8,children:['الكل','نقص المخزون'].map((v)=>ChoiceChip(label:Text(v),selected:_filter==v,onSelected:(_)=>setState(()=>_filter=v))).toList()),
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
