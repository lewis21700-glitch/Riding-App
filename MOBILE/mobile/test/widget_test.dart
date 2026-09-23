import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('RideApp starts', (WidgetTester tester) async {
    await tester.pumpWidget(const RideApp());
    expect(find.text('RideApp'), findsOneWidget);
  });
}
