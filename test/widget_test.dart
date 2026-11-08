import 'package:flutter_test/flutter_test.dart';
import 'package:batipro_dz/app/batipro_app.dart';

void main() {
  testWidgets('BatiPro dashboard renders', (tester) async {
    await tester.pumpWidget(const BatiProApp());
    await tester.pumpAndSettle();

    expect(find.text('ملخص تجارتك اليوم'), findsOneWidget);
    expect(find.text('لوحة القيادة'), findsOneWidget);
    expect(find.text('مبيعات اليوم'), findsOneWidget);
  });
}
