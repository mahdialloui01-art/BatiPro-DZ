import 'dart:convert';
import 'dart:math';

import 'app_storage.dart';
import 'api_client.dart';

/// One-time migration of the current Windows local ledger to PostgreSQL.
/// Current stock is imported as an opening snapshot; old invoices are archived
/// without replaying their stock movements.
class InitialSyncService {
  InitialSyncService._();

  static const _deviceKey = 'batipro_sync_device_id_v1';
  static const _resultPrefix = 'batipro_sync_initial_result_v1_';

  static List<Map<String, dynamic>> _readList(AppStorage storage, String key) {
    final raw = storage.getString(key);
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('بيانات $key ليست قائمة صالحة؛ أوقفنا المزامنة لحماية بياناتك.');
    }
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  static String _text(dynamic value, [String fallback = '']) =>
      value == null ? fallback : value.toString();

  static double _number(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value).replaceAll(',', '.')) ?? fallback;
  }

  static Future<String> _deviceId(AppStorage storage) async {
    final saved = storage.getString(_deviceKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final random = Random.secure();
    final generated = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await storage.setString(_deviceKey, generated);
    return generated;
  }

  static Future<Map<String, dynamic>> run() async {
    final api = ApiClient.instance;
    if (!api.isAuthenticated) {
      throw StateError('سجّل الدخول إلى خادم PostgreSQL أولاً.');
    }
    final account = await api.me();
    final email = _text(account['email']).trim().toLowerCase();
    if (email.isEmpty) throw const FormatException('تعذر تحديد حساب الخادم الحالي.');

    final storage = await AppStorage.getInstance();
    final resultKey = _resultPrefix + base64Url.encode(utf8.encode(email));
    final previous = storage.getString(resultKey);
    if (previous != null) {
      final result = Map<String, dynamic>.from(jsonDecode(previous) as Map);
      return <String, dynamic>{...result, 'already_imported_on_device': true};
    }

    final products = _readList(storage, 'batipro_inventory_v1');
    final suppliers = _readList(storage, 'batipro_suppliers_v1');
    final customers = _readList(storage, 'batipro_customers_v1');
    final purchases = _readList(storage, 'batipro_purchases_v1');
    final sales = _readList(storage, 'batipro_sales_v1');

    final productPayload = products.map((product) {
      final id = _text(product['id']).trim();
      final name = _text(product['name']).trim();
      if (id.isEmpty || name.isEmpty) {
        throw const FormatException('يوجد منتج بلا معرّف أو اسم؛ أصلح بيانات المخزون قبل المزامنة.');
      }
      return <String, dynamic>{
        'local_id': id,
        'name': name,
        'category': _text(product['category'], 'مواد البناء'),
        'unit': _text(product['unit'], 'وحدة'),
        'quantity': _number(product['quantity']),
        'minimum_stock': _number(product['minimum']),
        'purchase_price': _number(product['purchasePrice']),
        'sale_price': _number(product['salePrice']),
        'piece_weight_kg': product['pieceWeightKg'],
        'rebar_diameter_mm': product['diameterMm'],
        'bar_length_m': product['lengthM'],
      };
    }).toList(growable: false);

    final productByNameAndCategory = <String, String>{};
    for (final product in products) {
      final key = _productKey(_text(product['name']), _text(product['category'], 'مواد البناء'));
      productByNameAndCategory[key] = _text(product['id']);
    }

    final purchasePayload = purchases.map((purchase) {
      final name = _text(purchase['product']).trim();
      final category = _text(
        purchase['inventoryCategory'],
        _text(purchase['category'], 'مواد البناء'),
      );
      final localProductId = productByNameAndCategory[_productKey(name, category)] ?? '';
      return <String, dynamic>{
        'local_id': _text(purchase['id']),
        'product_local_id': localProductId,
        'product': name,
        'category': _text(purchase['category'], 'مواد البناء'),
        'inventory_category': category,
        'supplier': _text(purchase['supplier'], 'مورد غير محدد'),
        'quantity': _number(purchase['quantity']),
        'input_quantity': _number(purchase['inputQuantity'], _number(purchase['quantity'])),
        'input_unit': _text(purchase['inputUnit'], _text(purchase['stockUnit'], 'وحدة')),
        'stock_unit': _text(purchase['stockUnit'], _text(purchase['inputUnit'], 'وحدة')),
        'unit_price': _number(purchase['unitPrice']),
        'stock_unit_price': _number(purchase['stockUnitPrice'], _number(purchase['unitPrice'])),
        'total': _number(purchase['total']),
        'paid': _number(purchase['paid']),
        'weight_kg': purchase['weightKg'],
        'date': _text(purchase['date']),
        'reference': _text(purchase['reference']),
      };
    }).toList(growable: false);

    final salesPayload = sales.map((invoice) {
      final rawItems = invoice['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        throw FormatException('فاتورة البيع ${_text(invoice['id'])} بلا تفاصيل؛ لم نرسل أي بيانات.');
      }
      final items = rawItems.map((rawLine) {
        final line = Map<String, dynamic>.from(rawLine as Map);
        return <String, dynamic>{
          'productId': _text(line['productId']),
          'name': _text(line['name']),
          'unit': _text(line['unit'], 'وحدة'),
          'quantity': _number(line['quantity']),
          'price': _number(line['price']),
          'total': _number(line['total']),
        };
      }).toList(growable: false);
      return <String, dynamic>{
        'local_id': _text(invoice['id']),
        'client': _text(invoice['client'], 'زبون نقدي'),
        'method': _text(invoice['method']),
        'date': _text(invoice['date']),
        'total': _number(invoice['total']),
        'paid': _number(invoice['paid']),
        'items': items,
      };
    }).toList(growable: false);

    final deviceId = await _deviceId(storage);
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'idempotency_key': 'initial-snapshot-v1',
      'products': productPayload,
      'suppliers': suppliers.map((item) => <String, dynamic>{
        'local_id': _text(item['id']),
        'name': _text(item['name']),
        'phone': _text(item['phone']),
        'address': _text(item['address']),
      }).toList(growable: false),
      'customers': customers.map((item) => <String, dynamic>{
        'local_id': _text(item['id']),
        'name': _text(item['name']),
        'phone': _text(item['phone']),
        'address': _text(item['address']),
      }).toList(growable: false),
      'purchases': purchasePayload,
      'sales': salesPayload,
    };

    final result = await api.importInitialSnapshot(payload);
    await storage.setString(resultKey, jsonEncode(result));
    final idMap = result['id_map'];
    if (idMap is Map) {
      await storage.setString(
        'batipro_sync_id_map_v1_' + base64Url.encode(utf8.encode(email)),
        jsonEncode(idMap),
      );
    }
    return result;
  }

  static String _productKey(String name, String category) =>
      '${name.trim().toLowerCase()}::${category.trim().toLowerCase()}';
}
