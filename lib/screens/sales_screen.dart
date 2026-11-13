import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import '../app/localized_text.dart';
import '../app/app_language.dart';
import '../data/app_storage.dart';
import '../data/pos_drawer_service.dart';
import '../app/app_theme.dart';
import '../data/api_client.dart';

String _formatDzd(double centimes) {
  final fixed = (centimes / 100).toStringAsFixed(2).split('.');
  final digits = fixed[0];
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(digits[i]);
  }
  return '${grouped.toString()},${fixed[1]} دج';
}

double _parseDzd(String value) =>
    ((double.tryParse(value.trim().replaceAll(' ', '').replaceAll(',', '.')) ?? double.nan) * 100).roundToDouble();

class _SaleProduct {
  final Map<String,dynamic> raw;
  final double quantity;
  const _SaleProduct(this.raw,this.quantity);
  String get id=>raw['id'] as String;
  String get name=>raw['name'] as String;
  String get unit=>raw['unit'] as String;
  double get price=>(raw['salePrice'] as num).toDouble().roundToDouble();
  int get palletCount=>(raw['palletCount'] as num?)?.toInt() ?? 0;
  factory _SaleProduct.fromJson(Map<String,dynamic> j) {
    final data=Map<String,dynamic>.from(j);
    return _SaleProduct(data,(data['quantity'] as num).toDouble());
  }
  Map<String,dynamic> toJson()=>{...raw,'quantity':quantity};
}
class _SaleLine {
  final _SaleProduct product;
  /// Quantity selected by the seller (piece or pallet).
  final double quantity,price,baseQuantity;
  final String saleUnit;
  const _SaleLine(this.product,this.quantity,this.price,this.baseQuantity,this.saleUnit);
  double get total=>(quantity*price).roundToDouble();
  Map<String,dynamic> toJson()=>{'productId':product.id,'name':product.name,'unit':product.unit,'quantity':baseQuantity,'displayQuantity':quantity,'displayUnit':saleUnit,'price':price,'total':total};
}
class _SaleInvoice {
  final String id,client,method,seller;
  final DateTime date;
  final double total,paid;
  final List<Map<String,dynamic>> items;
  const _SaleInvoice(this.id,this.client,this.method,this.date,this.total,this.paid,this.items,{this.seller=''});
  double get due=>total-paid;
  String get status=>due<=0?'مدفوعة':paid>0?'دفع جزئي':'على الحساب';
  factory _SaleInvoice.fromJson(Map<String,dynamic> j)=>_SaleInvoice(j['id'],j['client'],j['method'],DateTime.parse(j['date']),(j['total'] as num).toDouble(),(j['paid'] as num).toDouble(),(j['items'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList(),seller:j['seller']?.toString() ?? '');
  Map<String,dynamic> toJson()=>{'id':id,'client':client,'method':method,'seller':seller,'date':date.toIso8601String(),'total':total,'paid':paid,'items':items};
}

class SalesScreen extends StatefulWidget {
  final String? sellerName;
  final bool sharedMode;
  const SalesScreen({super.key, this.sellerName, this.sharedMode = false});
  @override State<SalesScreen> createState()=>_SalesScreenState();
}
class _SalesScreenState extends State<SalesScreen> {
  static const stockKey='batipro_inventory_v1',salesKey='batipro_sales_v1';
  final search=TextEditingController();
  List<_SaleProduct> products=[];
  List<_SaleInvoice> invoices=[];
  bool loading=true;
  final _posSearch = TextEditingController();
  final _posClient = TextEditingController();
  final _posPaid = TextEditingController(text: '0');
  final List<_SaleLine> _posCart = [];
  String _posPayment = 'نقداً';
  String? _sharedWarehouseId;
  @override void initState(){super.initState();_load();}
  @override void dispose(){search.dispose();_posSearch.dispose();_posClient.dispose();_posPaid.dispose();super.dispose();}
  Future<void> _load() async {
    if (widget.sharedMode) {
      try {
        await _loadSharedData();
      } catch (error) {
        if (mounted) _toast('تعذر تحميل بيانات الخادم: $error');
      }
      if (mounted) setState(() => loading = false);
      return;
    }
    final prefs=await AppStorage.getInstance();
    try{
      final s=prefs.getString(stockKey),v=prefs.getString(salesKey);
      if(s!=null)products=(jsonDecode(s) as List).map((e)=>_SaleProduct.fromJson(Map<String,dynamic>.from(e as Map))).toList();
      if(v!=null)invoices=(jsonDecode(v) as List).map((e)=>_SaleInvoice.fromJson(Map<String,dynamic>.from(e as Map))).toList();
    }catch(_){if(mounted)_toast('تعذر قراءة البيانات المحفوظة.');}
    invoices.sort((a,b)=>b.date.compareTo(a.date));
    if(mounted)setState(()=>loading=false);
  }

  Future<void> _loadSharedData() async {
    final api = ApiClient.instance;
    final warehouses = await api.warehouses();
    if (warehouses.isEmpty) throw StateError('لا يوجد مستودع نشط في قاعدة البيانات.');
    final warehouseId = warehouses.first['id'].toString();
    final remoteProducts = await api.products();
    final remoteStock = await api.stock();
    final quantities = <String, double>{};
    for (final row in remoteStock) {
      if (row['warehouse_id']?.toString() == warehouseId) {
        quantities[row['product_id'].toString()] =
            double.tryParse(row['quantity'].toString()) ?? 0;
      }
    }
    final converted = <_SaleProduct>[];
    for (final row in remoteProducts) {
      final id = row['id'].toString();
      final price = (double.tryParse(row['sale_price'].toString()) ?? 0) * 100;
      final raw = <String, dynamic>{
        'id': id,
        'name': row['name']?.toString() ?? '',
        'category': row['category']?.toString() ?? '',
        'unit': row['base_unit']?.toString() ?? 'وحدة',
        'salePrice': price.round(),
        'quantity': quantities[id] ?? 0,
        'palletCount': 0,
      };
      converted.add(_SaleProduct(raw, quantities[id] ?? 0));
    }
    if (!mounted) return;
    setState(() {
      _sharedWarehouseId = warehouseId;
      products = converted;
    });
  }
  Future<void> _persist({List<Map<String, dynamic>>? movements}) async {
    final values = <String, String>{
      stockKey: jsonEncode(products.map((e)=>e.toJson()).toList()),
      salesKey: jsonEncode(invoices.map((e)=>e.toJson()).toList()),
    };
    if (movements != null) {
      values['batipro_stock_movements_v1'] = jsonEncode(movements);
    }
    await AppStorage.setStrings(values);
  }
  void _toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  String _money(double n)=>_formatDzd(n);
  String _date(DateTime d)=>d.year.toString()+'/'+d.month.toString().padLeft(2,'0')+'/'+d.day.toString().padLeft(2,'0');
  List<_SaleInvoice> get _visible {final q=search.text.trim().toLowerCase();return invoices.where((e)=>e.client.toLowerCase().contains(q)||e.id.toLowerCase().contains(q)).toList();}

  void _posAdd(_SaleProduct product, {bool pallet = false}) {
    final factor = pallet ? product.palletCount.toDouble() : 1.0;
    if (pallet && product.palletCount <= 0) return;
    if (product.quantity <= 0) { _toast('هذه المادة غير متوفرة في المخزون.'); return; }
    final saleUnit = pallet ? 'باليطة' : product.unit;
    final unitPrice = product.price * factor;
    final index = _posCart.indexWhere((line) => line.product.id == product.id && line.saleUnit == saleUnit);
    final current = _posCart.where((line) => line.product.id == product.id).fold<double>(0, (sum, line) => sum + line.baseQuantity);
    if (current + factor > product.quantity + 0.0000001) { _toast('الكمية المتوفرة غير كافية.'); return; }
    setState(() {
      if (index >= 0) {
        final old = _posCart[index];
        _posCart[index] = _SaleLine(old.product, old.quantity + 1, old.price, old.baseQuantity + factor, old.saleUnit);
      } else {
        _posCart.add(_SaleLine(product, 1, unitPrice, factor, saleUnit));
      }
      if (_posPayment == 'نقداً') _posPaid.text = (_posTotal / 100).toStringAsFixed(2);
    });
  }

  void _posRemoveLine(int index) {
    setState(() => _posCart.removeAt(index));
    if (_posPayment == 'نقداً') _posPaid.text = (_posTotal / 100).toStringAsFixed(2);
  }

  double get _posTotal => _posCart.fold<double>(0, (sum, line) => sum + line.total).roundToDouble();
  double get _posPaidAmount => _parseDzd(_posPaid.text);

  void _posChangeQty(int index, int delta) {
    final line = _posCart[index];
    final next = line.quantity + delta;
    if (next <= 0) {
      setState(() => _posCart.removeAt(index));
    } else {
      final factor = line.saleUnit == 'باليطة' ? line.product.palletCount.toDouble() : 1.0;
      final nextBaseQuantity = next * factor;
      final other = _posCart.where((e) => e.product.id == line.product.id && !identical(e, line)).fold<double>(0, (s,e)=>s+e.baseQuantity);
      if (other + nextBaseQuantity > line.product.quantity) { _toast('الكمية تتجاوز المخزون المتوفر.'); return; }
      setState(() => _posCart[index] = _SaleLine(line.product,next,line.price,nextBaseQuantity,line.saleUnit));
    }
    if (_posPayment == 'نقداً') _posPaid.text = (_posTotal / 100).toStringAsFixed(2);
  }

  Future<void> _posSave() async {
    if (_posCart.isEmpty) { _toast('اختر مادة واحدة على الأقل.'); return; }
    final paidAmount = _posPaidAmount;
    if (!paidAmount.isFinite || paidAmount < 0 || paidAmount > _posTotal) { _toast('تحقق من المبلغ المدفوع.'); return; }
    if (_posPayment == 'نقداً' && paidAmount < _posTotal) { _toast('الدفع نقداً يتطلب دفع كامل المبلغ.'); return; }
    final invoice = _SaleInvoice(
      'INV-${DateTime.now().millisecondsSinceEpoch}',
      _posClient.text.trim().isEmpty ? 'زبون نقدي' : _posClient.text.trim(),
      _posPayment, DateTime.now(), _posTotal, paidAmount,
      _posCart.map((e)=>e.toJson()).toList(), seller: widget.sellerName ?? '',
    );
    if (widget.sharedMode) {
      await _saveSharedSale(invoice);
      return;
    }
    final prefs = await AppStorage.getInstance();
    final movementRaw = prefs.getString('batipro_stock_movements_v1');
    final movements = <Map<String,dynamic>>[];
    if (movementRaw != null) {
      try { movements.addAll((jsonDecode(movementRaw) as List).map((e)=>Map<String,dynamic>.from(e as Map))); }
      catch (_) { _toast('تعذر قراءة سجل المخزون؛ لم يتم اعتماد البيع.'); return; }
    }
    final updated = <_SaleProduct>[];
    for (final product in products) {
      final sold = invoice.items.where((e)=>e['productId']==product.id).fold<double>(0,(s,e)=>s+(e['quantity'] as num).toDouble());
      if (sold > product.quantity + 0.0000001) { _toast('المخزون تغير. حدّث الشاشة ثم أعد البيع.'); return; }
      updated.add(_SaleProduct(product.raw, product.quantity - sold));
    }
    for (var i=0;i<invoice.items.length;i++) {
      final item=invoice.items[i];
      movements.insert(0, {
        'id':'${invoice.id}-sale-${item['productId']}-$i','date':invoice.date.toIso8601String(),
        'type':'sale','referenceId':invoice.id,'productId':item['productId'],'productName':item['name'],
        'quantityDelta':-((item['quantity'] as num).toDouble()),'unit':item['unit'],
        'displayQuantity':item['displayQuantity'],'displayUnit':item['displayUnit'],
        'reason':'بيع ضمن فاتورة ${invoice.id}',
      });
    }
    if (movements.length > 500) movements.removeRange(500,movements.length);
    setState(() { products=updated; invoices.insert(0,invoice); _posCart.clear(); _posClient.clear(); _posPaid.text='0'; });
    await _registerCustomer(invoice.client);
    await _persist(movements:movements);
    if (invoice.paid > 0) { try { await PosDrawerService.openAfterSale(); } catch (_) {} }
    _toast('تم حفظ الفاتورة وخصم الكمية من المخزون.');
  }

  Future<void> _saveSharedSale(_SaleInvoice invoice) async {
    final warehouseId = _sharedWarehouseId;
    if (warehouseId == null) {
      _toast('المستودع غير محدد. حدّث بيانات البيع.');
      return;
    }
    try {
      final result = await ApiClient.instance.createSale({
        'warehouse_id': warehouseId,
        'invoice_number': invoice.id,
        'lines': _posCart.map((line) {
          final quantity = line.baseQuantity;
          final basePrice = line.product.price / 100;
          return {
            'product_id': line.product.id,
            'quantity': quantity,
            'unit': line.product.unit,
            'unit_price': basePrice.toStringAsFixed(2),
            'line_total': (quantity * basePrice).toStringAsFixed(2),
          };
        }).toList(),
        'discount': '0.00',
        'paid': (invoice.paid / 100).toStringAsFixed(2),
        'notes': 'الزبون: ${invoice.client} | طريقة الدفع: ${invoice.method}',
      });
      final savedInvoice = _SaleInvoice(
        result['id']?.toString() ?? invoice.id,
        invoice.client, invoice.method, invoice.date, invoice.total,
        invoice.paid, invoice.items, seller: widget.sellerName ?? '',
      );
      if (!mounted) return;
      setState(() {
        invoices.insert(0, savedInvoice);
        _posCart.clear();
        _posClient.clear();
        _posPaid.text = '0';
      });
      await _loadSharedData();
      if (invoice.paid > 0) {
        try { await PosDrawerService.openAfterSale(); } catch (_) {}
      }
      _toast('تم تسجيل الفاتورة في قاعدة البيانات المشتركة وخصم المخزون.');
    } catch (error) {
      _toast('لم يتم تسجيل البيع. لم تتغير الكمية: $error');
    }
  }

  Widget _sellerPosLayout() {
    final query = _posSearch.text.trim().toLowerCase();
    final visible = products.where((p)=>p.name.toLowerCase().contains(query) || (p.raw['category']??'').toString().toLowerCase().contains(query)).toList();
    final compact = MediaQuery.of(context).size.width < 720;
    final catalog = Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,10,12,7),child:TextField(controller:_posSearch,onChanged:(_)=>setState((){}),decoration:const InputDecoration(isDense:true,prefixIcon:Icon(Icons.search),hintText:'ابحث عن مادة أو صنف...'))),
      Expanded(child:visible.isEmpty?const Center(child:Text('لا توجد مواد في المخزون أو لا توجد نتائج.')):GridView.builder(
        padding:const EdgeInsets.all(10),
        gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:compact?2:3,mainAxisSpacing:8,crossAxisSpacing:8,childAspectRatio:compact?1.55:1.65),
        itemCount:visible.length,
        itemBuilder:(context,i){final p=visible[i];return Material(color:Colors.white,borderRadius:BorderRadius.circular(12),child:InkWell(onTap:()=>_posAdd(p),borderRadius:BorderRadius.circular(12),child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),border:Border.all(color:const Color(0xFFDCE4EC))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Text(p.name,translate:false,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800,color:BatiProTheme.ink)),
          Text(_money(p.price),style:const TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF176B4A))),
          Row(children:[
            Expanded(child:Text('${p.quantity} ${p.unit}',style:const TextStyle(fontSize:10,color:BatiProTheme.muted))),
            if(p.palletCount>0) IconButton(
              tooltip:'إضافة بالبالطة (${p.palletCount} حبة)',
              visualDensity:VisualDensity.compact,
              constraints:const BoxConstraints(minWidth:30,minHeight:30),
              padding:EdgeInsets.zero,
              onPressed:()=>_posAdd(p,pallet:true),
              icon:const Icon(Icons.inventory_2_outlined,color:Color(0xFF245A9A),size:18),
            ),
            const Icon(Icons.add_circle,color:Color(0xFF176B4A),size:19),
          ]),
        ]))));},
      )),
    ]);
    final cartPanel = Container(color:Colors.white,padding:const EdgeInsets.fromLTRB(12,10,12,10),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[const Icon(Icons.shopping_cart_outlined,color:BatiProTheme.ink),const SizedBox(width:7),const Expanded(child:Text('السلة الحالية',style:TextStyle(fontWeight:FontWeight.w900,fontSize:14))),Text('${_posCart.length} مواد',style:const TextStyle(fontSize:10,color:BatiProTheme.muted))]),
      const SizedBox(height:6),
      TextField(controller:_posClient,decoration:const InputDecoration(isDense:true,labelText:'اسم الزبون (اختياري)',prefixIcon:Icon(Icons.person_outline,size:18))),
      Expanded(child:_posCart.isEmpty?const Center(child:Text('اضغط على أي مادة لإضافتها مباشرةً',style:TextStyle(color:BatiProTheme.muted,fontSize:12))):ListView.separated(itemCount:_posCart.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,i){final line=_posCart[i];return Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(line.product.name,translate:false,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800)),
          Text('${line.quantity} ${line.saleUnit} × ${_money(line.price)}',style:const TextStyle(fontSize:9,color:BatiProTheme.muted)),
          Text(_money(line.total),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:BatiProTheme.ink)),
        ])),
        IconButton(visualDensity:VisualDensity.compact,onPressed:()=>_posChangeQty(i,-1),icon:const Icon(Icons.remove_circle_outline,size:19)),
        Text(line.quantity.toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
        IconButton(visualDensity:VisualDensity.compact,onPressed:()=>_posChangeQty(i,1),icon:const Icon(Icons.add_circle_outline,size:19)),
        IconButton(visualDensity:VisualDensity.compact,onPressed:()=>_posRemoveLine(i),icon:const Icon(Icons.delete_outline,color:Colors.red,size:18)),
      ]));})),
      const Divider(height:10),
      Row(children:[const Expanded(child:Text('الإجمالي',style:TextStyle(fontWeight:FontWeight.bold))),Text(_money(_posTotal),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:BatiProTheme.ink))]),
      const SizedBox(height:6),
      DropdownButtonFormField<String>(value:_posPayment,isExpanded:true,decoration:const InputDecoration(isDense:true,labelText:'طريقة الدفع'),items:const[
        DropdownMenuItem(value:'نقداً',child:Text('نقداً — كامل')),DropdownMenuItem(value:'دفع جزئي',child:Text('دفع جزئي')),DropdownMenuItem(value:'على الحساب',child:Text('على الحساب')),
      ],onChanged:(v)=>setState((){_posPayment=v??'نقداً';if(_posPayment=='نقداً')_posPaid.text=(_posTotal/100).toStringAsFixed(2);if(_posPayment=='على الحساب')_posPaid.text='0';})),
      const SizedBox(height:5),
      TextField(controller:_posPaid,keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>setState((){}),decoration:const InputDecoration(isDense:true,labelText:'المدفوع بالدينار (دج)')),
      Align(alignment:Alignment.centerLeft,child:Text('المتبقي: ${_money((_posTotal-_posPaidAmount).clamp(0,double.infinity).toDouble())}',style:const TextStyle(color:Colors.redAccent,fontSize:11,fontWeight:FontWeight.bold))),
      const SizedBox(height:7),
      SizedBox(height:43,child:FilledButton.icon(onPressed:_posSave,icon:const Icon(Icons.check_circle),label:const Text('تأكيد البيع وحفظ الفاتورة'))),
    ]));
    return SafeArea(child:loading?const Center(child:CircularProgressIndicator()):Column(children:[
      Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),decoration:const BoxDecoration(gradient:LinearGradient(colors:[Color(0xFF173B68),Color(0xFF245A9A)])),child:Row(children:[
        const Icon(Icons.point_of_sale,color:BatiProTheme.gold),const SizedBox(width:9),const Expanded(child:Text('نقطة البيع',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:16))),Text('${widget.sellerName??''}',style:const TextStyle(color:Colors.white,fontSize:11)),
      ])),
      Expanded(child:compact?Column(children:[Expanded(flex:5,child:catalog),const Divider(height:1),Expanded(flex:5,child:cartPanel)]):Row(children:[Expanded(flex:6,child:catalog),const VerticalDivider(width:1),Expanded(flex:5,child:cartPanel)])),
    ]));
  }

  Future<void> _newSale() async {
    if(products.isEmpty){_toast('أضف منتجات إلى المخزون أولاً.');return;}
    final invoice=await showDialog<_SaleInvoice>(context:context,barrierDismissible:false,builder:(_)=>_SaleEditor(products:List.of(products), sellerName: widget.sellerName));
    if(invoice==null||!mounted)return;
    final prefs = await AppStorage.getInstance();
    final movementRaw = prefs.getString('batipro_stock_movements_v1');
    final movements = <Map<String, dynamic>>[];
    if (movementRaw != null) {
      try {
        movements.addAll((jsonDecode(movementRaw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map)));
      } catch (_) {
        _toast('تعذر قراءة سجل حركات المخزون؛ لم يتم اعتماد البيع.');
        return;
      }
    }
    final now = invoice.date.toIso8601String();
    for (var movementIndex = 0; movementIndex < invoice.items.length; movementIndex++) {
      final item = invoice.items[movementIndex];
      final movementId = '${invoice.id}-sale-${item['productId']}-$movementIndex';
      if (movements.any((entry) => entry['id'] == movementId)) continue;
      movements.insert(0, {
        'id': movementId,
        'date': now,
        'type': 'sale',
        'referenceId': invoice.id,
        'productId': item['productId'],
        'productName': item['name'],
        'quantityDelta': -((item['quantity'] as num).toDouble()),
        'unit': item['unit'],
        'displayQuantity': item['displayQuantity'],
        'displayUnit': item['displayUnit'],
        'reason': 'بيع ضمن فاتورة ${invoice.id}',
      });
    }
    if (movements.length > 500) movements.removeRange(500, movements.length);
    final updated=< _SaleProduct >[];
    for(final p in products){
      final sold=invoice.items.where((e)=>e['productId']==p.id).fold<double>(0,(s,e)=>s+(e['quantity'] as num).toDouble());
      if (sold > p.quantity + 0.0000001) {
        _toast('الكمية المتوفرة تغيرت؛ أعد فتح الفاتورة قبل اعتماد البيع.');
        return;
      }
      updated.add(_SaleProduct(p.raw,p.quantity-sold));
    }
    setState(()=>products=updated);
    setState(()=>invoices.insert(0,invoice));
    await _registerCustomer(invoice.client);
    await _persist(movements: movements);
    var drawerMessage = '';
    if (invoice.paid > 0) {
      try {
        if (await PosDrawerService.openAfterSale()) {
          drawerMessage = ' تم إرسال أمر فتح درج النقود.';
        }
      } catch (error) {
        drawerMessage = ' تعذر فتح الدرج: $error';
      }
    }
    _toast('تم حفظ الفاتورة وخصم الكميات من المخزون.$drawerMessage');
  }



  Future<void> _printReturnReceipt({
    required String returnId,
    required _SaleInvoice invoice,
    required DateTime date,
    required String mode,
    required double amount,
    required List<Map<String, dynamic>> lines,
  }) async {
    if (!Platform.isWindows) {
      _toast('طباعة وصل الإرجاع متاحة حالياً في نسخة Windows فقط.');
      return;
    }
    final storage = await AppStorage.getInstance();
    final printer = (storage.getString(PosDrawerService.printerKey) ?? '').trim();
    if (printer.isEmpty) {
      _toast('لم يتم تحديد طابعة الإيصالات. اختر الطابعة من إعدادات أجهزة POS ثم أعد الطباعة.');
      return;
    }
    final buffer = StringBuffer()
      ..writeln('             BATIPRO DZ')
      ..writeln('             ${AppLanguage.translate('وصل إرجاع')}')
      ..writeln('--------------------------------')
      ..writeln(AppLanguage.translate('رقم الوصل: ${returnId}'))
      ..writeln(AppLanguage.translate('رقم الفاتورة: ${invoice.id}'))
      ..writeln(AppLanguage.translate('الزبون: ') + invoice.client)
      ..writeln(AppLanguage.translate('التاريخ: ${_date(date)}'))
      ..writeln('--------------------------------')
      ..writeln(AppLanguage.translate('السلعة'))
      ..writeln('--------------------------------');
    for (final line in lines) {
      buffer.writeln('${line['productName']}');
      buffer.writeln('  ${line['quantity']} ${line['unit']}    ${_money((line['amount'] as num).toDouble())}');
    }
    buffer
      ..writeln('--------------------------------')
      ..writeln(AppLanguage.translate('قيمة الإرجاع: ${_money(amount)}'))
      ..writeln(AppLanguage.translate('طريقة التسوية: ${mode == 'cash' ? 'رد نقدي' : 'تخفيض الدين'}'))
      ..writeln(AppLanguage.translate('الفاتورة الأصلية: ${invoice.id}'))
      ..writeln('--------------------------------')
      ..writeln('       ${AppLanguage.translate('شكراً لتعاملكم معنا')}')
      ..writeln('\n\n\n');
    final encodedText = base64Encode(utf8.encode(buffer.toString()));
    final encodedPrinter = base64Encode(utf8.encode(printer));
    final script = r"""
$text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('TEXT64'));
$name = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PRINTER64'));
$text | Out-Printer -Name $name
""".replaceAll('TEXT64', encodedText).replaceAll('PRINTER64', encodedPrinter);
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-Command', script,
      ]);
      if (result.exitCode != 0) {
        _toast('تعذرت طباعة وصل الإرجاع: ${result.stderr.toString().trim()}');
      } else {
        _toast('تم إرسال وصل الإرجاع إلى الطابعة.');
      }
    } catch (e) {
      _toast('تعذرت الطباعة. تحقق من اتصال الطابعة وإعداداتها.');
    }
  }

  Future<void> _confirmPrintReturn({
    required String returnId,
    required _SaleInvoice invoice,
    required DateTime date,
    required String mode,
    required double amount,
    required List<Map<String, dynamic>> lines,
  }) async {
    if (!mounted) return;
    final shouldPrint = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تم تسجيل الإرجاع'),
        content: Text('تمت إضافة الكمية للمخزون وتسجيل مبلغ ${_money(amount)}. هل تريد طباعة وصل الإرجاع الآن؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لاحقاً')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.print),
            label: const Text('طباعة الوصل'),
          ),
        ],
      ),
    );
    if (shouldPrint == true) {
      await _printReturnReceipt(
        returnId: returnId, invoice: invoice, date: date,
        mode: mode, amount: amount, lines: lines,
      );
    }
  }

  Future<void> _returnSale(_SaleInvoice invoice) async {
    final prefs = await AppStorage.getInstance();
    List<Map<String, dynamic>> returns = [];
    List<Map<String, dynamic>> movements = [];
    try {
      final rr = prefs.getString('batipro_sales_returns_v1');
      if (rr != null) returns = (jsonDecode(rr) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final mr = prefs.getString('batipro_stock_movements_v1');
      if (mr != null) movements = (jsonDecode(mr) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      _toast('تعذر قراءة سجل الإرجاع أو المخزون؛ لم يتم تنفيذ العملية.');
      return;
    }
    final returned = <int, double>{};
    for (final r in returns.where((e) => e['invoiceId'] == invoice.id)) {
      final i = (r['lineIndex'] as num?)?.toInt();
      if (i != null) returned[i] = (returned[i] ?? 0) + ((r['quantity'] as num?)?.toDouble() ?? 0);
    }
    final remaining = <int, double>{};
    for (var i = 0; i < invoice.items.length; i++) {
      remaining[i] = (((invoice.items[i]['quantity'] as num).toDouble()) - (returned[i] ?? 0)).clamp(0, double.infinity).toDouble();
    }
    final draft = await showDialog<_SaleReturnDraft>(
      context: context, barrierDismissible: false,
      builder: (_) => _SaleReturnEditor(invoice: invoice, remaining: remaining),
    );
    if (draft == null || !mounted) return;
    var refund = 0.0;
    final lines = <Map<String, dynamic>>[];
    for (final entry in draft.quantities.entries) {
      final i = entry.key, qty = entry.value, item = invoice.items[entry.key];
      if (!qty.isFinite || qty <= 0 || qty > (remaining[i] ?? 0) + 0.0000001) {
        _toast('كمية الإرجاع غير صالحة.'); return;
      }
      final original = (item['quantity'] as num).toDouble();
      final amount = original <= 0 ? 0.0 : (((item['total'] as num).toDouble() / original) * qty).roundToDouble();
      refund += amount;
      lines.add({'lineIndex': i, 'productId': item['productId'], 'productName': item['name'], 'quantity': qty, 'unit': item['unit'], 'amount': amount});
    }
    refund = refund.roundToDouble();
    if (lines.isEmpty || refund <= 0) { _toast('حدد كمية واحدة على الأقل.'); return; }
    if (draft.mode == 'cash' && refund > invoice.paid) { _toast('قيمة الرد النقدي أكبر من المبلغ المدفوع.'); return; }
    if (draft.mode == 'credit' && refund > invoice.due) { _toast('قيمة الإرجاع أكبر من الدين المتبقي.'); return; }

    final updatedProducts = List<_SaleProduct>.of(products);
    final now = DateTime.now();
    final returnId = 'RET-${now.microsecondsSinceEpoch}';
    for (final line in lines) {
      final pi = updatedProducts.indexWhere((p) => p.id == line['productId']);
      if (pi < 0) { _toast('المنتج ${line['productName']} غير موجود في المخزون.'); return; }
      final p = updatedProducts[pi], qty = (line['quantity'] as num).toDouble();
      updatedProducts[pi] = _SaleProduct(p.raw, p.quantity + qty);
      movements.insert(0, {
        'id': '$returnId-${line['lineIndex']}', 'date': now.toIso8601String(),
        'type': 'sale_return', 'referenceId': invoice.id, 'returnId': returnId,
        'productId': line['productId'], 'productName': line['productName'],
        'quantityDelta': qty, 'unit': line['unit'], 'reason': 'إرجاع من فاتورة ${invoice.id}',
      });
    }
    final ii = invoices.indexWhere((e) => e.id == invoice.id);
    if (ii < 0) return;
    final current = invoices[ii];
    final newTotal = (current.total - refund).clamp(0, double.infinity).toDouble();
    final newPaid = draft.mode == 'cash' ? (current.paid - refund).clamp(0, double.infinity).toDouble() : current.paid;
    final updated = _SaleInvoice(current.id, current.client, current.method, current.date, newTotal, newPaid, current.items);
    for (final line in lines) {
      returns.insert(0, {
        'id': '$returnId-${line['lineIndex']}', 'returnId': returnId,
        'invoiceId': invoice.id, 'lineIndex': line['lineIndex'],
        'quantity': line['quantity'], 'amount': line['amount'],
        'mode': draft.mode, 'date': now.toIso8601String(),
      });
    }
    if (movements.length > 500) movements.removeRange(500, movements.length);
    final savedInvoices = List<_SaleInvoice>.of(invoices);
    savedInvoices[ii] = updated;
    await AppStorage.setStrings({
      stockKey: jsonEncode(updatedProducts.map((e) => e.toJson()).toList()),
      salesKey: jsonEncode(savedInvoices.map((e) => e.toJson()).toList()),
      'batipro_sales_returns_v1': jsonEncode(returns),
      'batipro_stock_movements_v1': jsonEncode(movements),
    });
    if (!mounted) return;
    setState(() { products = updatedProducts; invoices = savedInvoices; });
    await _confirmPrintReturn(
      returnId: returnId, invoice: invoice, date: now,
      mode: draft.mode, amount: refund, lines: lines,
    );
  }

  Future<void> _registerCustomer(String name) async {
    if (name.trim().isEmpty || name == 'زبون نقدي') return;
    final prefs = await AppStorage.getInstance();
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
          decoration: InputDecoration(labelText: AppLanguage.translate('المبلغ بالدينار (دج)'), helperText: AppLanguage.translate('المتبقي: ${_money(invoice.due)}')), 
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text(AppLanguage.text('إلغاء', 'Annuler'))),
          FilledButton(onPressed: (){
            final value = _parseDzd(controller.text);
            if (!value.isFinite || value <= 0 || value > invoice.due) {
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
    final updated = _SaleInvoice(current.id,current.client,current.method,current.date,current.total,(current.paid+amount).clamp(0,current.total).toDouble(),current.items,seller: current.seller);
    setState(()=>invoices[index]=updated);
    await _persist();
    var drawerMessage = '';
    try {
      if (await PosDrawerService.openAfterSale()) {
        drawerMessage = ' تم إرسال أمر فتح درج النقود.';
      }
    } catch (error) {
      drawerMessage = ' تعذر فتح الدرج: $error';
    }
    _toast('تم تسجيل التحصيل وتحديث دين الزبون.$drawerMessage');
  }

  Future<void> _showInvoice(_SaleInvoice i) async {
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('فاتورة '+i.id),
      content:SizedBox(width:440,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
        Text(AppLanguage.translate('الزبون: ') + i.client, translate: false),Text('التاريخ: '+_date(i.date)),const Divider(height:22),
        for(final e in i.items)Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[Expanded(child:Text(e['name'].toString()+' • '+(e['displayQuantity']??e['quantity']).toString()+' '+(e['displayUnit']??e['unit']).toString(),style:const TextStyle(fontSize:12))),Text(_money((e['total'] as num).toDouble()))])),
        const Divider(height:22),_detail('الإجمالي',_money(i.total)),_detail('المدفوع',_money(i.paid)),_detail('المتبقي',_money(i.due),i.due>0?BatiProTheme.red:BatiProTheme.green),_detail(AppLanguage.text('طريقة الدفع', 'Mode de paiement'),i.method),_detail('الحالة',i.status),
      ]))),
      actions:[
        if(i.due>0) FilledButton.icon(onPressed:()=>_collectPayment(i),icon:const Icon(Icons.payments_outlined),label:const Text('تحصيل دفعة')),
        OutlinedButton.icon(onPressed:()=>_returnSale(i),icon:const Icon(Icons.assignment_return),label:const Text('إرجاع سلعة')),
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق')),
      ],
    ));
  }
  Widget _detail(String a,String b,[Color? color])=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(child:Text(a,style:const TextStyle(color:BatiProTheme.muted,fontSize:12))),Text(b,style:TextStyle(fontWeight:FontWeight.bold,color:color??BatiProTheme.ink))]));
  @override Widget build(BuildContext context){
    if (widget.sellerName != null) return _sellerPosLayout();
    final total=invoices.fold<double>(0,(s,e)=>s+e.total),paid=invoices.fold<double>(0,(s,e)=>s+e.paid),debt=invoices.fold<double>(0,(s,e)=>s+e.due);
    return SafeArea(child:loading?const Center(child:CircularProgressIndicator()):LayoutBuilder(builder:(context,c){
      final compact=c.maxWidth<650;
      return SingleChildScrollView(padding:EdgeInsets.all(compact?10:20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(
          width:double.infinity,
          padding:EdgeInsets.all(compact?12:17),
          decoration:BoxDecoration(
            gradient:const LinearGradient(begin:Alignment.topRight,end:Alignment.bottomLeft,colors:[Color(0xFF173447),Color(0xFF31566A)]),
            borderRadius:BorderRadius.circular(20),
          ),
          child:Row(children:[
            Container(width:42,height:42,decoration:BoxDecoration(color:BatiProTheme.gold,borderRadius:BorderRadius.circular(13)),child:const Icon(Icons.point_of_sale_rounded,color:BatiProTheme.ink)),
            const SizedBox(width:11),
            const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('نقطة البيع وإدارة الفواتير',style:TextStyle(color:Color(0xFFD5E2E9),fontSize:10)),
              SizedBox(height:3),Text('المبيعات والفواتير',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900,color:Colors.white)),
            ])),
            FilledButton.icon(
              style:FilledButton.styleFrom(backgroundColor:BatiProTheme.gold,foregroundColor:BatiProTheme.ink,padding:EdgeInsets.symmetric(horizontal:compact?10:15,vertical:13)),
              onPressed:_newSale,icon:const Icon(Icons.add_shopping_cart_rounded,size:18),label:Text(compact?'بيع جديد':'فاتورة جديدة'),
            ),
          ]),
        ),
        const SizedBox(height:20),
        GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:compact?2:4,crossAxisSpacing:10,mainAxisSpacing:10,childAspectRatio:compact?1.7:1.8,children:[
          _metric('عدد الفواتير',invoices.length.toString(),Icons.receipt_long),
          _metric('قيمة المبيعات',_money(total),Icons.point_of_sale),
          _metric('المبالغ المحصلة',_money(paid),Icons.payments),
          _metric('الديون',_money(debt),Icons.account_balance_wallet,warning:debt>0),
        ]),
        const SizedBox(height:18),
        TextField(controller:search,onChanged:(_)=>setState((){}),decoration:InputDecoration(hintText: AppLanguage.translate('ابحث برقم الفاتورة أو اسم الزبون'),prefixIcon:Icon(Icons.search))),
        const SizedBox(height:18),
        Row(children:[const Expanded(child:Text('سجل الفواتير',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800,color:BatiProTheme.ink))),Text(_visible.length.toString()+' فاتورة',style:const TextStyle(fontSize:11,color:BatiProTheme.muted))]),
        const SizedBox(height:6),
        if(_visible.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(28),child:Center(child:Column(children:[const Icon(Icons.receipt_long_outlined,size:42,color:BatiProTheme.muted),const SizedBox(height:10),const Text('لا توجد فواتير بعد',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:5),const Text('أنشئ أول فاتورة بيع وستظهر هنا.',style:TextStyle(fontSize:11,color:BatiProTheme.muted)),const SizedBox(height:10),OutlinedButton.icon(onPressed:_newSale,icon:const Icon(Icons.add),label:const Text('إنشاء فاتورة'))]))))
        else ..._visible.map((i)=>Card(margin:const EdgeInsets.only(bottom:9),child:InkWell(borderRadius:BorderRadius.circular(18),onTap:()=>_showInvoice(i),child:Padding(padding:const EdgeInsets.all(13),child:Row(children:[
          Container(width:42,height:42,decoration:BoxDecoration(color:BatiProTheme.gold.withValues(alpha:.14),borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.receipt_long,color:BatiProTheme.ink)),
          const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(i.client,translate:false,style:const TextStyle(fontWeight:FontWeight.w800,color:BatiProTheme.ink)),Text(i.id+' • '+_date(i.date),style:const TextStyle(fontSize:10,color:BatiProTheme.muted))])),
          Column(crossAxisAlignment:CrossAxisAlignment.end,children:[Text(_money(i.total),style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:4),Text(i.status,style:TextStyle(fontSize:10,fontWeight:FontWeight.bold,color:i.due>0?BatiProTheme.red:BatiProTheme.green))]),const Icon(Icons.chevron_left,color:BatiProTheme.muted),
        ]))))),
        const SizedBox(height:7),const Text('الفواتير محفوظة محلياً دون إنترنت، والبيع يخصم الكمية من المخزون تلقائياً.',style:TextStyle(fontSize:11,color:BatiProTheme.muted)),
      ]));
    }));
  }
  Widget _metric(String label,String value,IconData icon,{bool warning=false})=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:warning?BatiProTheme.red:BatiProTheme.gold,size:19),const Spacer(),FittedBox(fit:BoxFit.scaleDown,child:Text(value,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800,color:BatiProTheme.ink))),Text(label,style:const TextStyle(fontSize:10,color:BatiProTheme.muted))])));
}


class _SaleReturnDraft {
  final Map<int, double> quantities;
  final String mode;
  const _SaleReturnDraft(this.quantities, this.mode);
}

class _SaleReturnEditor extends StatefulWidget {
  final _SaleInvoice invoice;
  final Map<int, double> remaining;
  const _SaleReturnEditor({required this.invoice, required this.remaining});
  @override State<_SaleReturnEditor> createState() => _SaleReturnEditorState();
}

class _SaleReturnEditorState extends State<_SaleReturnEditor> {
  late final List<TextEditingController> controllers;
  String mode = 'credit';
  @override void initState() {
    super.initState();
    controllers = List.generate(widget.invoice.items.length, (_) => TextEditingController(text: '0'));
  }
  @override void dispose() { for (final c in controllers) { c.dispose(); } super.dispose(); }
  double get estimated {
    var sum = 0.0;
    for (var i = 0; i < controllers.length; i++) {
      final q = double.tryParse(controllers[i].text.trim().replaceAll(',', '.')) ?? 0;
      final item = widget.invoice.items[i], original = (item['quantity'] as num).toDouble();
      if (original > 0 && q > 0) sum += (item['total'] as num).toDouble() / original * q;
    }
    return sum.roundToDouble();
  }
  void submit() {
    final q = <int, double>{};
    for (var i = 0; i < controllers.length; i++) {
      final n = double.tryParse(controllers[i].text.trim().replaceAll(',', '.')) ?? 0;
      if (!n.isFinite || n < 0 || n > (widget.remaining[i] ?? 0) + 0.0000001) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تحقق من الكميات؛ تجاوزت الكمية القابلة للإرجاع.'))); return;
      }
      if (n > 0) q[i] = n;
    }
    if (q.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل كمية واحدة على الأقل.'))); return; }
    Navigator.pop(context, _SaleReturnDraft(q, mode));
  }
  @override Widget build(BuildContext context) => AlertDialog(
    title: Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: BatiProTheme.gold.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.assignment_return_outlined, color: BatiProTheme.ink)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('إرجاع من الفاتورة'), const SizedBox(height: 3), Text(widget.invoice.id, style: const TextStyle(fontSize: 11, color: BatiProTheme.muted, fontWeight: FontWeight.w500))]))]),
    content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('أدخل الكمية المرجعة بوحدة المخزون الأصلية، وليس بالباليطة.'),
        const SizedBox(height: 10),
        for (var i = 0; i < widget.invoice.items.length; i++)
          Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.invoice.items[i]['name'].toString(), translate: false, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('المتبقي: ${widget.remaining[i]} ${widget.invoice.items[i]['unit']}', style: const TextStyle(fontSize: 11, color: BatiProTheme.muted)),
            ])),
            SizedBox(width: 90, child: TextField(controller: controllers[i],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BatiProTheme.ink, height: 1.45),
              enabled: (widget.remaining[i] ?? 0) > 0,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: AppLanguage.translate('الكمية'), isDense: true),
              onChanged: (_) => setState(() {}))),
          ])),
        const Divider(),
        const Text('طريقة التسوية', style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: 'credit', groupValue: mode,
          onChanged: (v) => setState(() => mode = v ?? 'credit'),
          title: const Text('تخفيض دين الفاتورة'), subtitle: const Text('ينقص المبلغ المتبقي على الزبون')),
        RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: 'cash', groupValue: mode,
          onChanged: (v) => setState(() => mode = v ?? 'cash'),
          title: const Text('ردّ المبلغ نقداً'), subtitle: const Text('يُخصم من المبلغ المدفوع سابقاً')),
        Text('قيمة الإرجاع التقديرية: ${_formatDzd(estimated)}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLanguage.text('إلغاء', 'Annuler'))),
      FilledButton.icon(onPressed: submit, icon: const Icon(Icons.assignment_return), label: const Text('تأكيد الإرجاع')),
    ],
  );
}

class _SaleEditor extends StatefulWidget {
  final List<_SaleProduct> products;
  final String? sellerName;
  const _SaleEditor({required this.products, this.sellerName});
  @override State<_SaleEditor> createState()=>_SaleEditorState();
}
class _SaleEditorState extends State<_SaleEditor>{
  final form=GlobalKey<FormState>();
  final client=TextEditingController(),paid=TextEditingController(text:'0'),catalogSearch=TextEditingController();
  final cart=<_SaleLine>[];
  String? selected;
  String method='نقداً';
  String saleUnit='حبة';
  double quantity=1,price=0;
  @override void initState(){super.initState();if(widget.products.isNotEmpty){selected=widget.products.first.id;price=widget.products.first.price;}}
  @override void dispose(){client.dispose();paid.dispose();catalogSearch.dispose();super.dispose();}
  _SaleProduct? get _product {for(final p in widget.products){if(p.id==selected)return p;}return null;}
  double get _total=>cart.fold<double>(0,(s,e)=>s+e.total).roundToDouble();
  double get _paid=>_parseDzd(paid.text);
  double _factor(_SaleProduct p)=>saleUnit=='باليطة'?p.palletCount.toDouble():1;
  String _money(double n)=>_formatDzd(n);
  void _quickAdd(_SaleProduct item) {
    selected = item.id;
    saleUnit = 'حبة';
    quantity = 1;
    price = item.price;
    _add();
  }

  void _add(){
    final p=_product;if(p==null||!quantity.isFinite||quantity<=0||!price.isFinite||price<0)return;
    if(p.palletCount>0&&quantity!=quantity.roundToDouble()){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('كمية الآجر يجب أن تكون عدداً صحيحاً، سواء بالحبة أو بالباليطة.')));return;}
    final baseQuantity=quantity*_factor(p);
    final old=cart.where((e)=>e.product.id==p.id).fold<double>(0,(s,e)=>s+e.baseQuantity);
    if(old+baseQuantity>p.quantity){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(AppLanguage.translate('المتوفر من ') + p.name + AppLanguage.translate(': ') + p.quantity.toString() + ' ' + AppLanguage.translate(p.unit) + AppLanguage.translate(' فقط، والكمية المطلوبة تعادل ') + baseQuantity.toString() + ' ' + AppLanguage.translate(p.unit) + '.', translate:false)));return;}
    setState((){cart.add(_SaleLine(p,quantity,price,baseQuantity,saleUnit=='باليطة'?'باليطة':p.unit));if(method=='نقداً')paid.text=(_total/100).toStringAsFixed(2).replaceAll('.', ',');});
  }
  void _save(){
    if(!form.currentState!.validate())return;
    if(cart.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أضف منتجاً إلى الفاتورة.')));return;}
    if(_paid>_total){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('المدفوع أكبر من إجمالي الفاتورة.')));return;}
    if(method=='نقداً'&&_paid<_total){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('الدفع نقداً يتطلب دفع كامل المبلغ.')));return;}
    Navigator.pop(context,_SaleInvoice('INV-'+DateTime.now().millisecondsSinceEpoch.toString(),client.text.trim().isEmpty?'زبون نقدي':client.text.trim(),method,DateTime.now(),_total,_paid,cart.map((e)=>e.toJson()).toList(),seller:widget.sellerName ?? ''));
  }
  @override Widget build(BuildContext context){
    final p=_product;
    final q=catalogSearch.text.trim().toLowerCase();
    final shown=widget.products.where((x)=>x.name.toLowerCase().contains(q)||(x.raw['category']??'').toString().toLowerCase().contains(q)).toList();
    final size=MediaQuery.of(context).size;
    return Dialog(
      insetPadding:const EdgeInsets.all(12),
      backgroundColor:const Color(0xFFF1F4F7),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
      child:SizedBox(
        width:size.width>1180?1120:size.width-24,
        height:size.height>820?760:size.height-24,
        child:Form(key:form,child:Column(children:[
          Container(height:60,padding:const EdgeInsets.symmetric(horizontal:16),
            decoration:const BoxDecoration(gradient:LinearGradient(colors:[Color(0xFF173B68),Color(0xFF245A9A)]),borderRadius:BorderRadius.vertical(top:Radius.circular(18))),
            child:Row(children:[
              const Icon(Icons.point_of_sale,color:Colors.white,size:25),const SizedBox(width:10),
              Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(AppLanguage.text('واجهة البائع • نقطة البيع','Espace vendeur • Point de vente'),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:15)),
                Text(AppLanguage.text('فاتورة متعددة المنتجات','Facture multi-articles'),style:const TextStyle(color:Color(0xFFD8E7F7),fontSize:10)),
              ])),
              Text(cart.length.toString()+' '+AppLanguage.text('أنواع','articles'),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),
              IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close,color:Colors.white)),
            ]),
          ),
          Expanded(child:LayoutBuilder(builder:(context,box){
            final narrow=box.maxWidth<760;
            final left=Container(color:Colors.white,padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Row(children:[const Icon(Icons.receipt_long,color:Color(0xFF244D78)),const SizedBox(width:7),Expanded(child:Text(AppLanguage.text('الفاتورة الحالية','Ticket en cours'),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:14))),Text(cart.length.toString()+' '+AppLanguage.text('مواد','articles'),style:const TextStyle(fontSize:10,color:BatiProTheme.muted))]),
              const SizedBox(height:7),
              TextFormField(controller:client,decoration:InputDecoration(isDense:true,labelText:AppLanguage.text('اسم الزبون (اختياري)','Client (facultatif)'),prefixIcon:const Icon(Icons.person_outline,size:18))),
              const SizedBox(height:6),
              Expanded(child:cart.isEmpty?Center(child:Text(AppLanguage.text('اختر المواد لإضافتها للفاتورة','Choisissez des articles'),style:const TextStyle(color:BatiProTheme.muted,fontSize:12))):ListView.separated(
                itemCount:cart.length,separatorBuilder:(_,__)=>const Divider(height:1),
                itemBuilder:(context,i){final line=cart[i];return Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Row(children:[
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(line.product.name,translate:false,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800)),
                    Text(line.quantity.toString()+' '+AppLanguage.translate(line.saleUnit)+' × '+_money(line.price),style:const TextStyle(fontSize:9,color:BatiProTheme.muted)),
                  ])),
                  Text(_money(line.total),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),
                  IconButton(visualDensity:VisualDensity.compact,onPressed:()=>setState((){cart.removeAt(i);if(method=='نقداً')paid.text=(_total/100).toStringAsFixed(2).replaceAll('.',',');}),icon:const Icon(Icons.delete_outline,color:Colors.redAccent,size:18)),
                ]));},
              )),
              const Divider(height:12),
              Row(children:[Expanded(child:Text(AppLanguage.text('الإجمالي','Total'),style:const TextStyle(fontWeight:FontWeight.bold))),FittedBox(child:Text(_money(_total),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:Color(0xFF173B68))))]),
              const SizedBox(height:6),
              DropdownButtonFormField<String>(value:method,isExpanded:true,decoration:InputDecoration(isDense:true,labelText:AppLanguage.text('طريقة الدفع','Paiement')),items:const[
                DropdownMenuItem(value:'نقداً',child:Text('نقداً — كامل')),DropdownMenuItem(value:'دفع جزئي',child:Text('دفع جزئي')),DropdownMenuItem(value:'على الحساب',child:Text('على الحساب')),
              ],onChanged:(v)=>setState((){method=v??'نقداً';if(method=='نقداً')paid.text=(_total/100).toStringAsFixed(2).replaceAll('.',',');if(method=='على الحساب')paid.text='0';})),
              const SizedBox(height:6),
              TextFormField(controller:paid,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(isDense:true,labelText:AppLanguage.text('المبلغ المدفوع بالدينار (دج)','Montant payé (DZD)')),onChanged:(_)=>setState((){}),validator:(v){final n=_parseDzd(v??'');if(!n.isFinite||n<0)return AppLanguage.translate('أدخل مبلغاً صحيحاً');if(n>_total)return AppLanguage.translate('المبلغ أكبر من الإجمالي');return null;}),
              const SizedBox(height:4),
              Text(AppLanguage.text('المتبقي','Reste')+': '+_money((_total-_paid).clamp(0,double.infinity).toDouble()),style:const TextStyle(fontSize:10,color:Colors.redAccent,fontWeight:FontWeight.bold)),
              const SizedBox(height:7),
              SizedBox(height:42,child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:const Color(0xFF176B4A),foregroundColor:Colors.white),onPressed:_save,icon:const Icon(Icons.check_circle_outline),label:Text(AppLanguage.text('اعتماد وحفظ الفاتورة','Valider la facture')))),
            ]));
            final right=Container(padding:const EdgeInsets.all(11),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              TextField(controller:catalogSearch,onChanged:(_)=>setState((){}),decoration:InputDecoration(isDense:true,hintText:AppLanguage.text('ابحث عن مادة أو صنف...','Rechercher un article...'),prefixIcon:const Icon(Icons.search,size:19))),
              const SizedBox(height:8),
              if(p!=null)Container(padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(11),border:Border.all(color:const Color(0xFFD8E1EA))),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                Text(p.name,translate:false,style:const TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF173B68))),
                Text(AppLanguage.text('المتوفر','Disponible')+': '+p.quantity.toString()+' '+p.unit+' • '+_money(p.price),style:const TextStyle(fontSize:10,color:BatiProTheme.muted)),
                if(p.palletCount>0)DropdownButtonFormField<String>(value:saleUnit,isExpanded:true,decoration:InputDecoration(isDense:true,labelText:AppLanguage.text('طريقة البيع','Unité de vente')),items:[const DropdownMenuItem(value:'حبة',child:Text('بالحبة')),DropdownMenuItem(value:'باليطة',child:Text('بالباليطة ('+p.palletCount.toString()+' حبة)'))],onChanged:(v){if(v!=null)setState((){saleUnit=v;quantity=1;price=p.price*_factor(p);});}),
                Row(children:[
                  Expanded(child:TextFormField(key:ValueKey('qty-'+selected.toString()+'-'+saleUnit),initialValue:'1',keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(isDense:true,labelText:AppLanguage.text('الكمية','Quantité')),onChanged:(v)=>quantity=double.tryParse(v.replaceAll(',','.'))??0)),
                  const SizedBox(width:6),
                  Expanded(child:TextFormField(key:ValueKey('price-'+selected.toString()+'-'+saleUnit),initialValue:(price/100).toStringAsFixed(2).replaceAll('.',','),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(isDense:true,labelText:AppLanguage.text('السعر بالدينار','Prix DZD')),onChanged:(v)=>price=_parseDzd(v))),
                  const SizedBox(width:6),
                  SizedBox(height:42,width:45,child:FilledButton(style:FilledButton.styleFrom(backgroundColor:const Color(0xFF176B4A),padding:EdgeInsets.zero),onPressed:_add,child:const Icon(Icons.add_shopping_cart))),
                ]),
              ])),
              const SizedBox(height:8),
              Text(AppLanguage.text('اختيار سريع للمواد','Sélection rapide'),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:12,color:Color(0xFF244D78))),
              const SizedBox(height:6),
              Expanded(child:shown.isEmpty?Center(child:Text(AppLanguage.text('لا توجد مواد مطابقة','Aucun article trouvé'))):GridView.builder(
                gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:narrow?2:3,mainAxisSpacing:7,crossAxisSpacing:7,childAspectRatio:1.45),
                itemCount:shown.length,itemBuilder:(context,i){final item=shown[i];final active=item.id==selected;return Material(color:active?const Color(0xFFE2EDF8):Colors.white,borderRadius:BorderRadius.circular(10),child:InkWell(borderRadius:BorderRadius.circular(10),onTap:()=>_quickAdd(item),child:Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(borderRadius:BorderRadius.circular(10),border:Border.all(color:active?const Color(0xFF315F91):const Color(0xFFDCE3EA),width:active?1.6:1)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                  Text(item.name,translate:false,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:10,color:Color(0xFF20384D))),
                  Text(_money(item.price),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:10,color:Color(0xFF176B4A))),
                  Text(item.quantity.toString()+' '+item.unit,style:const TextStyle(fontSize:9,color:BatiProTheme.muted)),
                ]))));},
              )),
            ]));
            if(narrow)return Column(children:[SizedBox(height:box.maxHeight*.47,child:right),const Divider(height:1),Expanded(child:left)]);
            return Row(children:[Expanded(flex:5,child:left),Container(width:1,color:const Color(0xFFDDE3E9)),Expanded(flex:6,child:right)]);
          })),
        ])),
      ),
    );
  }
}
