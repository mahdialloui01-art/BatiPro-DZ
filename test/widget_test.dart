import 'package:flutter_test/flutter_test.dart';
import 'package:batipro_dz/data/app_storage.dart';
import 'package:batipro_dz/app/batipro_app.dart';

void main() {
  testWidgets('BatiPro dashboard renders', (tester) async {
    await AppStorage.initialize(inMemory: true);
    await tester.pumpWidget(const BatiProApp());
    await tester.pumpAndSettle();

    expect(find.text('ملخص تجارتك اليوم'), findsOneWidget);
    expect(find.text('لوحة القيادة'), findsOneWidget);
    expect(find.text('مبيعات اليوم'), findsOneWidget);
  });
  testWidgets('Inventory shows the four requested groups and rebar sizes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BatiProApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('المخزون'));
    await tester.pumpAndSettle();
    expect(find.text('أقسام المخزون'), findsOneWidget);
    expect(find.text('حديد التسليح'), findsOneWidget);
    expect(find.text('الآجر'), findsWidgets);
    expect(find.text('الإسمنت'), findsWidgets);
    expect(find.text('الڨرافي'), findsOneWidget);
    await tester.tap(find.text('حديد التسليح'));
    await tester.pumpAndSettle();
    expect(find.text('حديد تسليح T8'), findsOneWidget);
    expect(find.text('حديد تسليح T32'), findsOneWidget);
  });

  testWidgets('Dashboard sales chart switches between day, week, month and year', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BatiProApp());
    await tester.pumpAndSettle();

    for (final period in ['اليوم', 'الأسبوع', 'الشهر', 'العام']) {
      await tester.ensureVisible(find.text(period));
      await tester.tap(find.text(period));
      await tester.pumpAndSettle();
      expect(find.text('مجموع المبيعات • $period'), findsOneWidget);
    }
  });
}
