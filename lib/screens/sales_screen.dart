import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/app_theme.dart';

class _SaleProduct {
  final Map<String,dynamic> raw;
  final double quantity;
  const _SaleProduct(this.raw,this.quantity);
  String get id=>raw['id'] as String;
  String get name=>raw['name'] as String;
  String get unit=>raw['unit'] as String;
  double get price=>(raw['salePrice'] as num).toDouble();
  factory _SaleProduct.fromJson(Map<String,dynamic> j) {
    final data=Map<String,dynamic>.from(j);
    return _SaleProduct(data,(data['quantity'] as num).toDouble());
  }
  Map<String,dynamic> toJson()=>{...raw,'quantity':quantity};
}
class _SaleLine {
  final _SaleProduct product;
  final double quantity,price;
  const _SaleLine(this.product,this.quantity,this.price);
  double get total=>quantity*price;
  Map<String,dynamic> toJson()=>{'productId':product.id,'name':product.name,'unit':product.unit,'quantity':quantity,'price':price,'total':total};
}
class _SaleInvoice {
  final String id,client,method;
  final DateTime date;
  final double total,paid;
  final List<Map<String,dynamic>> items;
  const _SaleInvoice(this.id,this.client,this.method,this.date,this.total,this.paid,this.items);
  double get due=>total-paid;
  String get status=>due<=0?'مدفوعة':paid>0?'دفع جزئي':'على الحساب';
  factory _SaleInvoice.fromJson(Map<String,dynamic> j)=>_SaleInvoice(j['id'],j['client'],j['method'],DateTime.parse(j['date']),(j['total'] as num).toDouble(),(j['paid'] as num).toDouble(),(j['items'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList());
  Map<String,dynamic> toJson()=>{'id':id,'client':client,'method':method,'date':date.toIso8601String(),'total':total,'paid':paid,'items':items};
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override State<SalesScreen> createState()=>_SalesScreenState();
}
class _SalesScreenState extends State<SalesScreen> {
  static const stockKey='batipro_inventory_v1',salesKey='batipro_sales_v1';
  final search=TextEditingController();
  List<_SaleProduct> products=[];
  List<_SaleInvoice> invoices=[];
  bool loading=true;
  @override void initState(){super.initState();_load();}
  @override void dispose(){search.dispose();super.dispose();}
  Future<void> _load() async {
    final prefs=await SharedPreferences.getInstance();
    try{
      final s=prefs.getString(stockKey),v=prefs.getString(salesKey);
      if(s!=null)products=(jsonDecode(s) as List).map((e)=>_SaleProduct.fromJson(Map<String,dynamic>.from(e as Map))).toList();
      if(v!=null)invoices=(jsonDecode(v) as List).map((e)=>_SaleInvoice.fromJson(Map<String,dynamic>.from(e as Map))).toList();
    }catch(_){if(mounted)_toast('تعذر قراءة البيانات المحفوظة.');}
    invoices.sort((a,b)=>b.date.compareTo(a.date));
    if(mounted)setState(()=>loading=false);
  }
  Future<void> _persist() async {
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString(stockKey,jsonEncode(products.map((e)=>e.toJson()).toList()));
    await prefs.setString(salesKey,jsonEncode(invoices.map((e)=>e.toJson()).toList()));
  }
  void _toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  String _money(double n)=>n.toStringAsFixed(n==n.roundToDouble()?0:2)+' دج';
  String _date(DateTime d)=>d.year.toString()+'/'+d.month.toString().padLeft(2,'0')+'/'+d.day.toString().padLeft(2,'0');
  List<_SaleInvoice> get _visible {final q=search.text.trim().toLowerCase();return invoices.where((e)=>e.client.toLowerCase().contains(q)||e.id.toLowerCase().contains(q)).toList();}

  Future<void> _newSale() async {
    if(products.isEmpty){_toast('أضف منتجات إلى المخزون أولاً.');return;}
    final invoice=await showDialog<_SaleInvoice>(context:context,barrierDismissible:false,builder:(_)=>_SaleEditor(products:List.of(products)));
    if(invoice==null||!mounted)return;
    final updated=< _SaleProduct >[];
    for(final p in products){
      final sold=invoice.items.where((e)=>e['productId']==p.id).fold<double>(0,(s,e)=>s+(e['quantity'] as num).toDouble());
      updated.add(_SaleProduct(p.raw,p.quantity-sold));
    }
    setState(()=>products=updated);
    setState(()=>invoices.insert(0,invoice));
    await _registerCustomer(invoice.client);
    await _persist();
    _toast('تم حفظ الفاتورة وخصم الكميات من المخزون.');
  }

  Future<void> _registerCustomer(String name) async {
    if (name.trim().isEmpty || name == 'زبون نقدي') return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('batipro_customers_v1');
    final customers = raw == null ? <Map<String,dynamic>>[] :
      (jsonDecode(raw) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    final exists = customers.any((e)=>(e['name']??'').toString().trim().toLowerCase()==name.trim().toLowerCase());
    if (!exists) {
      customers.insert(0, {'id': DateTime.now().microsecondsSinceEpoch.toString(), 'name': name.trim(), 'phone': '', 'address': '', 'note': 'أضيف تلقائياً من فاتورة بيع'});
      await prefs.setString('batipro_customers_v1', jsonEncode(customers));
    }
  }

  Future<void> _collectPayment(_SaleInvoice invoice) async {
    if (invoice.due <= 0) return;
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل تحصيل دفعة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'المبلغ (دج)', helperText: 'المتبقي: ${_money(invoice.due)}'),
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: (){
            final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
            if (value == null || !value.isFinite || value <= 0 || value > invoice.due) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً أكبر من صفر ولا يتجاوز المتبقي.')));
              return;
            }
            Navigator.pop(ctx, value);
          }, child: const Text('تأكيد التحصيل')),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    final index = invoices.indexWhere((e)=>e.id==invoice.id);
    if (index < 0) return;
    final current = invoices[index];
    final updated = _SaleInvoice(current.id,current.client,current.method,current.date,current.total,(current.paid+amount).clamp(0,current.total).toDouble(),current.items);
    setState(()=>invoices[index]=updated);
    await _persist();
    _toast('تم تسجيل التحصيل وتحديث دين الزبون.');
  }

  Future<void> _showInvoice(_SaleInvoice i) async {
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('فاتورة '+i.id),
      content:SizedBox(width:440,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
        Text('الزبون: '+i.client),Text('التاريخ: '+_date(i.date)),const Divider(height:22),
        for(final e in i.items)Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[Expanded(child:Text(e['name'].toString()+' • '+e['quantity'].toString()+' '+e['unit'].toString(),style:const TextStyle(fontSize:12))),Text(_money((e['total'] as num).toDouble()))])),
        const Divider(height:22),_detail('الإجمالي',_money(i.total)),_detail('المدفوع',_money(i.paid)),_detail('المتبقي',_money(i.due),i.due>0?BatiProTheme.red:BatiProTheme.green),_detail('طريقة الدفع',i.method),_detail('الحالة',i.status),
      ]))),
      actions:[
        if(i.due>0) FilledButton.icon(onPressed:()=>_collectPayment(i),icon:const Icon(Icons.payments_outlined),label:const Text('تحصيل دفعة')),
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق')),
      ],
    ));
  }
  Widget _detail(String a,String b,[Color? color])=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(child:Text(a,style:const TextStyle(color:BatiProTheme.muted,fontSize:12))),Text(b,style:TextStyle(fontWeight:FontWeight.bold,color:color??BatiProTheme.ink))]));
  @override Widget build(BuildContext context){
    final total=invoices.fold<double>(0,(s,e)=>s+e.total),paid=invoices.fold<double>(0,(s,e)=>s+e.paid),debt=invoices.fold<double>(0,(s,e)=>s+e.due);
    return SafeArea(child:loading?const Center(child:CircularProgressIndicator()):LayoutBuilder(builder:(context,c){
      final compact=c.maxWidth<650;
      return SingleChildScrollView(padding:EdgeInsets.all(compact?16:28),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('BatiPro DZ',style:TextStyle(fontSize:11,color:BatiProTheme.muted)),SizedBox(height:4),Text('المبيعات والفواتير',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800,color:BatiProTheme.ink))])),FilledButton.icon(onPressed:_newSale,icon:const Icon(Icons.add_shopping_cart),label:Text(compact?'بيع جديد':'فاتورة جديدة'))]),
        const SizedBox(height:20),
        GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:compact?2:4,crossAxisSpacing:10,mainAxisSpacing:10,childAspectRatio:compact?1.7:1.8,children:[
          _metric('عدد الفواتير',invoices.length.toString(),Icons.receipt_long),
          _metric('قيمة المبيعات',_money(total),Icons.point_of_sale),
          _metric('المبالغ المحصلة',_money(paid),Icons.payments),
          _metric('الديون',_money(debt),Icons.account_balance_wallet,warning:debt>0),
        ]),
        const SizedBox(height:18),
        TextField(controller:search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(hintText:'ابحث برقم الفاتورة أو اسم الزبون',prefixIcon:Icon(Icons.search))),
        const SizedBox(height:18),
        Row(children:[const Expanded(child:Text('سجل الفواتير',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800,color:BatiProTheme.ink))),Text(_visible.length.toString()+' فاتورة',style:const TextStyle(fontSize:11,color:BatiProTheme.muted))]),
        const SizedBox(height:10),
        if(_visible.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(28),child:Center(child:Column(children:[const Icon(Icons.receipt_long_outlined,size:42,color:BatiProTheme.muted),const SizedBox(height:10),const Text('لا توجد فواتير بعد',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:5),const Text('أنشئ أول فاتورة بيع وستظهر هنا.',style:TextStyle(fontSize:11,color:BatiProTheme.muted)),const SizedBox(height:10),OutlinedButton.icon(onPressed:_newSale,icon:const Icon(Icons.add),label:const Text('إنشاء فاتورة'))]))))
        else ..._visible.map((i)=>Card(margin:const EdgeInsets.only(bottom:9),child:InkWell(borderRadius:BorderRadius.circular(18),onTap:()=>_showInvoice(i),child:Padding(padding:const EdgeInsets.all(13),child:Row(children:[
          Container(width:42,height:42,decoration:BoxDecoration(color:BatiProTheme.gold.withValues(alpha:.14),borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.receipt_long,color:BatiProTheme.ink)),
          const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(i.client,style:const TextStyle(fontWeight:FontWeight.w800,color:BatiProTheme.ink)),Text(i.id+' • '+_date(i.date),style:const TextStyle(fontSize:10,color:BatiProTheme.muted))])),
          Column(crossAxisAlignment:CrossAxisAlignment.end,children:[Text(_money(i.total),style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:4),Text(i.status,style:TextStyle(fontSize:10,fontWeight:FontWeight.bold,color:i.due>0?BatiProTheme.red:BatiProTheme.green))]),const Icon(Icons.chevron_left,color:BatiProTheme.muted),
        ]))))),
        const SizedBox(height:12),const Text('الفواتير محفوظة محلياً دون إنترنت، والبيع يخصم الكمية من المخزون تلقائياً.',style:TextStyle(fontSize:11,color:BatiProTheme.muted)),
      ]));
    }));
  }
  Widget _metric(String label,String value,IconData icon,{bool warning=false})=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:warning?BatiProTheme.red:BatiProTheme.gold,size:19),const Spacer(),FittedBox(fit:BoxFit.scaleDown,child:Text(value,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800,color:BatiProTheme.ink))),Text(label,style:const TextStyle(fontSize:10,color:BatiProTheme.muted))])));
}

class _SaleEditor extends StatefulWidget {
  final List<_SaleProduct> products;
  const _SaleEditor({required this.products});
  @override State<_SaleEditor> createState()=>_SaleEditorState();
}
class _SaleEditorState extends State<_SaleEditor>{
  final form=GlobalKey<FormState>();
  final client=TextEditingController(),paid=TextEditingController(text:'0');
  final cart=<_SaleLine>[];
  String? selected;
  String method='نقداً';
  double quantity=1,price=0;
  @override void initState(){super.initState();if(widget.products.isNotEmpty){selected=widget.products.first.id;price=widget.products.first.price;}}
  @override void dispose(){client.dispose();paid.dispose();super.dispose();}
  _SaleProduct? get _product {for(final p in widget.products){if(p.id==selected)return p;}return null;}
  double get _total=>cart.fold<double>(0,(s,e)=>s+e.total);
  double get _paid=>double.tryParse(paid.text.trim().replaceAll(',','.'))??0;
  String _money(double n)=>n.toStringAsFixed(n==n.roundToDouble()?0:2)+' دج';
  void _add(){
    final p=_product;if(p==null||quantity<=0||price<0)return;
    final old=cart.where((e)=>e.product.id==p.id).fold<double>(0,(s,e)=>s+e.quantity);
    if(old+quantity>p.quantity){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('المتوفر من '+p.name+': '+p.quantity.toString()+' '+p.unit+' فقط.')));return;}
    setState((){cart.add(_SaleLine(p,quantity,price));if(method=='نقداً')paid.text=_total.toStringAsFixed(2);});
  }
  void _save(){
    if(!form.currentState!.validate())return;
    if(cart.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أضف منتجاً إلى الفاتورة.')));return;}
    if(_paid>_total){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('المدفوع أكبر من إجمالي الفاتورة.')));return;}
    if(method=='نقداً'&&_paid<_total){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('الدفع نقداً يتطلب دفع كامل المبلغ.')));return;}
    Navigator.pop(context,_SaleInvoice('INV-'+DateTime.now().millisecondsSinceEpoch.toString(),client.text.trim().isEmpty?'زبون نقدي':client.text.trim(),method,DateTime.now(),_total,_paid,cart.map((e)=>e.toJson()).toList()));
  }
  @override Widget build(BuildContext context){
    final p=_product;
    return AlertDialog(title:const Text('إنشاء فاتورة بيع'),content:SizedBox(width:520,child:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      TextFormField(controller:client,decoration:const InputDecoration(labelText:'اسم الزبون (اختياري)',prefixIcon:Icon(Icons.person_outline))),
      const SizedBox(height:12),const Text('المنتجات',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:selected,isExpanded:true,decoration:const InputDecoration(labelText:'اختر المنتج'),items:widget.products.map((p)=>DropdownMenuItem(value:p.id,child:Text(p.name+' — '+p.quantity.toString()+' '+p.unit,overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>selected=v)),
      const SizedBox(height:8),Row(children:[
        Expanded(child:TextFormField(initialValue:'1',keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الكمية'),onChanged:(v)=>quantity=double.tryParse(v.replaceAll(',','.'))??0)),
        const SizedBox(width:8),Expanded(child:TextFormField(key:ValueKey(selected),initialValue:price.toString(),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'سعر الوحدة دج'),onChanged:(v)=>price=double.tryParse(v.replaceAll(',','.'))??-1)),
        const SizedBox(width:6),IconButton.filled(onPressed:_add,icon:const Icon(Icons.add),tooltip:'إضافة'),
      ]),
      if(p!=null)Text('المتوفر: '+p.quantity.toString()+' '+p.unit,style:const TextStyle(fontSize:10,color:BatiProTheme.muted)),
      if(cart.isNotEmpty)Container(margin:const EdgeInsets.only(top:10),padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:BatiProTheme.canvas,borderRadius:BorderRadius.circular(12)),child:Column(children:[for(var i=0;i<cart.length;i++)Row(children:[Expanded(child:Text(cart[i].product.name+' • '+cart[i].quantity.toString()+' '+cart[i].product.unit,style:const TextStyle(fontSize:11))),Text(_money(cart[i].total),style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold)),IconButton(visualDensity:VisualDensity.compact,onPressed:()=>setState(()=>cart.removeAt(i)),icon:const Icon(Icons.close,size:17))])])),
      const SizedBox(height:10),Align(alignment:Alignment.centerLeft,child:Text('الإجمالي: '+_money(_total),style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:BatiProTheme.ink))),
      const SizedBox(height:10),DropdownButtonFormField<String>(value:method,decoration:const InputDecoration(labelText:'طريقة الدفع'),items:const [DropdownMenuItem(value:'نقداً',child:Text('نقداً — كامل')),DropdownMenuItem(value:'دفع جزئي',child:Text('دفع جزئي')),DropdownMenuItem(value:'على الحساب',child:Text('على الحساب'))],onChanged:(v)=>setState((){method=v??'نقداً';if(method=='نقداً')paid.text=_total.toStringAsFixed(2);if(method=='على الحساب')paid.text='0';})),
      const SizedBox(height:8),TextFormField(controller:paid,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'المبلغ المدفوع دج'),onChanged:(_)=>setState((){}),validator:(v){final n=double.tryParse((v??'').trim().replaceAll(',','.'));if(n==null||!n.isFinite||n<0)return'أدخل مبلغاً صحيحاً';if(n>_total)return'المبلغ أكبر من الإجمالي';return null;}),
      const SizedBox(height:5),Text('المتبقي: '+_money((_total-_paid).clamp(0,double.infinity).toDouble()),style:const TextStyle(fontSize:12,color:BatiProTheme.red,fontWeight:FontWeight.bold)),
    ])))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إلغاء')),FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save_outlined),label:const Text('حفظ الفاتورة'))]);
  }
}
