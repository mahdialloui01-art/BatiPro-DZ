import 'package:flutter_test/flutter_test.dart';
import 'package:batipro_dz/data/app_storage.dart';
import 'package:batipro_dz/app/batipro_app.dart';

void main() {
  setUp(() async {
    await AppStorage.resetForTests();
    await AppStorage.initialize(inMemory: true);
  });

  tearDown(() async {
    await AppStorage.resetForTests();
  });

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(const BatiProApp());
    // Advance a bounded amount of time instead of waiting for every animation
    // to become idle; some dashboard animations are intentionally continuous.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('BatiPro dashboard renders', (tester) async {
    await openApp(tester);
    expect(find.text('ملخص تجارتك اليوم'), findsOneWidget);
    expect(find.text('لوحة القيادة'), findsOneWidget);
    expect(find.text('مبيعات اليوم'), findsOneWidget);
  });

  testWidgets('Inventory shows the four requested groups and rebar sizes', (tester) async {
    await openApp(tester);
    await tester.tap(find.text('المخزون').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('أقسام المخزون'), findsOneWidget);
    expect(find.text('حديد التسليح'), findsOneWidget);
    expect(find.text('الآجر'), findsWidgets);
    expect(find.text('الإسمنت'), findsWidgets);
    expect(find.text('الڨرافي'), findsOneWidget);
    await tester.tap(find.text('حديد التسليح'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('حديد تسليح T8'), findsOneWidget);
    expect(find.text('حديد تسليح T32'), findsOneWidget);
  });

  testWidgets('Dashboard sales chart switches between day, week, month and year', (tester) async {
    await openApp(tester);
    for (final period in ['اليوم', 'الأسبوع', 'الشهر', 'العام']) {
      await tester.ensureVisible(find.text(period));
      await tester.tap(find.text(period));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('مجموع المبيعات • $period'), findsOneWidget);
    }
  });
}
