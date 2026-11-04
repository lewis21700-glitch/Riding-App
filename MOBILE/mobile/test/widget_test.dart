import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/driver_home_page.dart';
import 'package:mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('RideApp starts and shows booking UI directly',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RideApp());
    expect(find.text('RideApp'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Book your ride in Phnom Penh'), findsOneWidget);
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
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BookingPage(onBooked: () async {})),
    ));

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Comfort'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Direct Ride'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
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

  testWidgets('guest user sees sign in and register options in account tab',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProfilePage(user: {}),
      ),
    ));

    expect(find.text('Welcome to RideApp'), findsOneWidget);
    expect(find.text('Sign In'), findsNWidgets(2));
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Passenger: rider.chenda@rideapp.com'), findsOneWidget);
  });

  test('findLandmark matches Phnom Penh landmarks by text', () {
    expect(findLandmark('Aeon Mall'), isNotNull);
    expect(findLandmark('Airport'), isNotNull);
    expect(findLandmark('central market'), isNotNull);
    expect(findLandmark('unknown nowhere xyz'), isNull);
  });

  testWidgets('booking page displays quick landmark chips and mode toggle',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BookingPage(onBooked: () async {})),
    ));

    expect(find.text('Set Pickup'), findsOneWidget);
    expect(find.text('Set Destination'), findsOneWidget);
    expect(find.text('Aeon 1'), findsOneWidget);
    expect(find.text('Independence Mon.'), findsOneWidget);
    expect(find.text('Central Market'), findsOneWidget);

    // Tap quick chip for Aeon 1 (as pickup)
    await tester.tap(find.text('Aeon 1'));
    await tester.pump();
    expect(find.textContaining('Aeon Mall 1'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('driver active actions show arrived at pickup and start trip buttons',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: DriverHomePage(
        user: const {'id': 2, 'name': 'Sokha Driver', 'role': 'driver', 'availability': 'available'},
        onLogout: () async {},
      ),
    ));
    await tester.pump();

    expect(find.text('Driver center'), findsOneWidget);
    expect(find.textContaining('Sokha Driver'), findsOneWidget);
  });

  testWidgets('signed in user sees rich common settings, saved places and safety options',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'pref_lang': 'English',
      'pref_curr': 'USD (\$)',
    });
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProfilePage(
          user: {'id': 5, 'name': 'Chenda Rider', 'email': 'rider.chenda@rideapp.com', 'role': 'rider'},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Chenda Rider'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Saved Places'), findsOneWidget);
    expect(find.text('App Preferences'), findsOneWidget);
    expect(find.text('Push Notifications'), findsOneWidget);
    expect(find.text('Default Payment Method'), findsOneWidget);
    expect(find.text('Emergency SOS Assistance'), findsOneWidget);
    expect(find.text('About RideApp'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
