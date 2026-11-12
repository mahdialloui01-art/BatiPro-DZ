import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:batipro_dz/data/app_storage.dart';
import 'package:batipro_dz/screens/dashboard_screen.dart';
import 'package:batipro_dz/screens/inventory_screen.dart';

void main() {
  setUp(() async {
    await AppStorage.resetForTests();
    await AppStorage.initialize(inMemory: true);
  });

  tearDown(() async {
    await AppStorage.resetForTests();
  });

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: DashboardScreen()))));
    // Advance a bounded amount of time instead of waiting for every animation
    // to become idle; some dashboard animations are intentionally continuous.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('BatiPro dashboard renders', (tester) async {
    await openApp(tester);
    expect(find.text('مرحباً بك في BatiPro 👋'), findsOneWidget);
    expect(find.text('لوحة القيادة'), findsOneWidget);
    expect(find.text('مبيعات اليوم'), findsOneWidget);
  });

  testWidgets('Inventory shows the four requested groups and rebar sizes', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    // Test InventoryScreen in isolation. Navigation is owned by AppShell;
    // tapping a sidebar label here made this content test depend on layout
    // hit-testing rather than the inventory screen itself.
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: InventoryScreen(),
        ),
      ),
    ));
    await tester.pump();
    // SQLite FFI completes outside the widget test's fake clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
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
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
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
