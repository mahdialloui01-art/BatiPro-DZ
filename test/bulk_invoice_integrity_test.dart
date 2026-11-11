import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:batipro_dz/data/app_storage.dart';

void main() {
  setUp(() async {
    await AppStorage.resetForTests();
    await AppStorage.initialize(inMemory: true);
  });

  tearDown(() async {
    await AppStorage.resetForTests();
  });

  test('1000 mixed purchase and sale invoices preserve stock and centime totals', () async {
    final storage = await AppStorage.getInstance();
    const productCount = 5;
    final stock = List<int>.filled(productCount, 0);
    final purchaseInvoices = <Map<String, dynamic>>[];
    final saleInvoices = <Map<String, dynamic>>[];
    final movements = <Map<String, dynamic>>[];
    var purchaseTotal = 0;
    var saleTotal = 0;
    var paidTotal = 0;
    var debtTotal = 0;

    // 250 purchase invoices: five products, quantities and integer centime prices.
    for (var i = 0; i < 250; i++) {
      final product = i % productCount;
      final quantity = 20 + (i % 7);
      final unitCost = 10000 + (i % 11) * 125;
      final total = quantity * unitCost;
      stock[product] += quantity;
      purchaseTotal += total;
      purchaseInvoices.add({
        'id': 'P-${i.toString().padLeft(4, '0')}',
        'productId': 'SKU-$product',
        'quantity': quantity,
        'unitPrice': unitCost,
        'total': total,
        'paid': total,
        'date': DateTime.utc(2026, 1, 1).add(Duration(minutes: i)).toIso8601String(),
      });
      movements.add({'type': 'purchase', 'productId': 'SKU-$product', 'quantity': quantity});
    }

    // 750 sale invoices. Cycle through products while keeping stock non-negative.
    for (var i = 0; i < 750; i++) {
      final product = i % productCount;
      final quantity = 1 + (i % 3);
      final unitPrice = 16000 + (i % 13) * 175;
      final total = quantity * unitPrice;
      expect(stock[product] - quantity, greaterThanOrEqualTo(0));
      stock[product] -= quantity;
      final paid = i % 4 == 0 ? total ~/ 2 : total;
      saleTotal += total;
      paidTotal += paid;
      debtTotal += total - paid;
      saleInvoices.add({
        'id': 'S-${i.toString().padLeft(4, '0')}',
        'productId': 'SKU-$product',
        'quantity': quantity,
        'unitPrice': unitPrice,
        'total': total,
        'paid': paid,
        'date': DateTime.utc(2026, 2, 1).add(Duration(minutes: i)).toIso8601String(),
      });
      movements.add({'type': 'sale', 'productId': 'SKU-$product', 'quantity': -quantity});
    }

    expect(purchaseInvoices.length + saleInvoices.length, 1000);
    expect(stock.every((quantity) => quantity >= 0), isTrue);
    expect(purchaseTotal, greaterThan(0));
    expect(saleTotal, greaterThan(0));
    expect(paidTotal + debtTotal, saleTotal);

    await AppStorage.setStrings({
      'batipro_inventory_v1': jsonEncode(List.generate(productCount, (i) => {
        'id': 'SKU-$i', 'quantity': stock[i], 'unit': 'حبة',
      })),
      'batipro_purchases_v1': jsonEncode(purchaseInvoices),
      'batipro_sales_v1': jsonEncode(saleInvoices),
      'batipro_stock_movements_v1': jsonEncode(movements),
      'batipro_test_totals_v1': jsonEncode({
        'purchaseTotal': purchaseTotal,
        'saleTotal': saleTotal,
        'paidTotal': paidTotal,
        'debtTotal': debtTotal,
      }),
    });

    final backup = await AppStorage.exportBackupJson();
    await AppStorage.clearAll();
    final restoredCount = await AppStorage.restoreBackupJson(backup);
    expect(restoredCount, 5);

    final restoredPurchases = jsonDecode(storage.getString('batipro_purchases_v1')!) as List;
    final restoredSales = jsonDecode(storage.getString('batipro_sales_v1')!) as List;
    final restoredMovements = jsonDecode(storage.getString('batipro_stock_movements_v1')!) as List;
    final restoredStock = jsonDecode(storage.getString('batipro_inventory_v1')!) as List;
    final totals = jsonDecode(storage.getString('batipro_test_totals_v1')!) as Map;

    expect(restoredPurchases, hasLength(250));
    expect(restoredSales, hasLength(750));
    expect(restoredMovements, hasLength(1000));
    expect(restoredStock, hasLength(productCount));
    expect(totals['purchaseTotal'], purchaseTotal);
    expect(totals['saleTotal'], saleTotal);
    expect(totals['paidTotal'], paidTotal);
    expect(totals['debtTotal'], debtTotal);
    expect(restoredSales.fold<int>(0, (sum, row) => sum + (row['total'] as int)), saleTotal);
    expect(restoredPurchases.fold<int>(0, (sum, row) => sum + (row['total'] as int)), purchaseTotal);
    for (var i = 0; i < productCount; i++) {
      expect(restoredStock[i]['quantity'], stock[i]);
    }
  });
}
