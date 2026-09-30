import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('RideApp starts', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RideApp());
    expect(find.text('RideApp'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
