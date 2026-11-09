import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:batipro_dz/app/batipro_app.dart';

void main() {
  testWidgets('BatiPro dashboard renders', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
}
