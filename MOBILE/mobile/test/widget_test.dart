import 'package:flutter/material.dart';
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

  testWidgets('numeric paid status shows receipt instead of pay action',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HistoryPage(
          loading: false,
          rides: [
            {
              'id': 42,
              'status': 'completed',
              'fare': 6.5,
              'paid': 1,
              'rated': 1,
              'driver_id': 9,
              'ride_type': 'Car',
              'pickup_location': 'Pickup',
              'destination': 'Market',
              'driver_name': 'Driver',
            },
          ],
        ),
      ),
    ));

    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('View receipt'), findsOneWidget);
    expect(find.text('Pay cash'), findsNothing);
    expect(find.text('Rate driver'), findsNothing);
  });
}
