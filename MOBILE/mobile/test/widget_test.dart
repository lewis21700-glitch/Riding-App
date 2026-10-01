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

  testWidgets('booking offers every backend ride type',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BookingPage(onBooked: () async {})),
    ));

    expect(find.text('Car'), findsOneWidget);
    expect(find.text('TukTuk'), findsOneWidget);
    expect(find.text('Motorbike'), findsOneWidget);
    expect(find.text('Direct Ride'), findsOneWidget);
  });

  test('unread notification count accepts MySQL integer flags', () {
    expect(
      unreadNotificationCount([
        {'id': 1, 'is_read': 0},
        {'id': 2, 'is_read': 1},
        {'id': 3, 'is_read': false},
        {'id': 4, 'is_read': true},
      ]),
      2,
    );
  });
}
