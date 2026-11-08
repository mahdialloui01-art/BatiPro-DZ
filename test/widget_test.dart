import 'package:flutter_test/flutter_test.dart';
import 'package:batipro_dz/app/batipro_app.dart';

void main() {
  testWidgets('BatiPro dashboard renders', (tester) async {
    await tester.view.setPhysicalSize(const Size(1080, 1920));
    await tester.view.setDevicePixelRatio(1);

    await tester.pumpWidget(const BatiProApp());
    await tester.pumpAndSettle();

    expect(find.text('ملخص تجارتك اليوم'), findsOneWidget);
    expect(find.text('لوحة القيادة'), findsOneWidget);
    expect(find.text('مبيعات اليوم'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
