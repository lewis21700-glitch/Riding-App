import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'driver_home_page.dart';

const String apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000/api',
);
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() => runApp(const RideApp());

class RideApp extends StatelessWidget {
  const RideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'RideApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF111827)),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF111827), width: 1.3),
          ),
        ),
      ),
      home: const SplashGate(),
    );
  }
}

class Api {
  static Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$apiBase$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final encodedBody = body == null ? null : jsonEncode(body);
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (encodedBody != null) request.body = encodedBody;
    final client = http.Client();
    late http.Response response;
    try {
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = {
        'error': response.body.isEmpty ? 'Server error' : response.body
      };
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded is Map && decoded['error'] != null
            ? decoded['error'].toString()
            : 'Request failed (${response.statusCode})',
      );
    }

    return decoded;
  }
}

class Session {
  static Future<void> save(Map<String, dynamic> user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user));
    await prefs.setString('token', token);
  }

  static Future<Map<String, dynamic>?> user() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('user');
    return value == null ? null : Map<String, dynamic>.from(jsonDecode(value));
  }

  static Future<String?> token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    await prefs.remove('token');
    await prefs.remove('chatgpt_account');
    await prefs.remove('chatgpt_api_key');
  }
}

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final user = await Session.user();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => user == null
            ? const LoginPage()
            : user['role'] == 'driver'
                ? DriverHomePage(user: user, onLogout: _signOut)
                : const HomePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TaxiLogo(),
              SizedBox(height: 16),
              Text('RideApp',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('Cambodia ride-hailing'),
            ],
          ),
        ),
      );
}

Future<void> _signOut() async {
  await Session.clear();
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (_) => false,
  );
}

class _TaxiLogo extends StatelessWidget {
  const _TaxiLogo();
  @override
  Widget build(BuildContext context) => Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child:
            const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 42),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  Future<void> login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      _msg('Enter email and password.');
      return;
    }
    setState(() => loading = true);
    try {
      final result = await Api.request(
        'POST',
        '/login',
        body: {'email': email.text.trim(), 'password': password.text},
      );
      final user = Map<String, dynamic>.from(result['user']);
      await Session.save(user, result['token'].toString());
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => user['role'] == 'driver'
              ? DriverHomePage(user: user, onLogout: _signOut)
              : const HomePage(),
        ),
      );
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _msg(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: _TaxiLogo()),
                    const SizedBox(height: 18),
                    const Text('Welcome back',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 29, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 7),
                    const Text('Sign in to book a ride',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF6B7280))),
                    const SizedBox(height: 28),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      onSubmitted: (_) => login(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: loading ? null : login,
                        child: loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Login'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegisterPage()),
                        );
                      },
                      child: const Text('Create account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final vehicleType = TextEditingController(text: 'Car');
  final vehicleModel = TextEditingController();
  final plateNumber = TextEditingController();
  String role = 'rider';
  bool loading = false;

  Future<void> register() async {
    if (name.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        password.text.isEmpty) {
      _msg('Name, email and password are required.');
      return;
    }
    if (password.text.length < 8) {
      _msg('Choose a password with at least 8 characters.');
      return;
    }
    if (role == 'driver' &&
        [vehicleType, vehicleModel, plateNumber]
            .any((field) => field.text.trim().isEmpty)) {
      _msg('Add your vehicle type, model and plate number.');
      return;
    }
    setState(() => loading = true);
    try {
      final data = await Api.request(
        'POST',
        '/register',
        body: {
          'name': name.text.trim(),
          'email': email.text.trim(),
          'phone': phone.text.trim(),
          'password': password.text,
          'role': role,
        },
      );
      if (!mounted) return;
      final user = Map<String, dynamic>.from(data['user']);
      final token = data['token'].toString();
      await Session.save(user, token);
      if (role == 'driver') {
        try {
          await Api.request('POST', '/my-vehicle', token: token, body: {
            'vehicle_type': vehicleType.text.trim(),
            'vehicle_model': vehicleModel.text.trim(),
            'plate_number': plateNumber.text.trim().toUpperCase(),
          });
        } catch (e) {
          if (!mounted) return;
          _msg(
              'Account created. Add your vehicle after signing in: ${e.toString().replaceFirst('Exception: ', '')}');
        }
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => role == 'driver'
              ? DriverHomePage(user: user, onLogout: _signOut)
              : const HomePage(),
        ),
        (_) => false,
      );
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _msg(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
    vehicleType.dispose();
    vehicleModel.dispose();
    plateNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Account type'),
              items: const [
                DropdownMenuItem(value: 'rider', child: Text('Passenger')),
                DropdownMenuItem(value: 'driver', child: Text('Driver')),
              ],
              onChanged: loading
                  ? null
                  : (value) => setState(() => role = value ?? 'rider'),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Password (at least 8 characters)'),
            ),
            if (role == 'driver') ...[
              const SizedBox(height: 18),
              const Text('Vehicle details',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                  controller: vehicleType,
                  decoration: const InputDecoration(labelText: 'Vehicle type')),
              const SizedBox(height: 12),
              TextField(
                  controller: vehicleModel,
                  decoration:
                      const InputDecoration(labelText: 'Make and model')),
              const SizedBox(height: 12),
              TextField(
                  controller: plateNumber,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Plate number')),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: loading ? null : register,
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create account'),
              ),
            ),
          ],
        ),
      );
}

enum RideType { car, tukTuk, direct }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  Map<String, dynamic> user = {};
  List<Map<String, dynamic>> rides = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    user = await Session.user() ?? {};
    final token = await Session.token();
    if (token != null) {
      try {
        final data = await Api.request('GET', '/my-rides', token: token);
        rides = ((data['rides'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('RideApp',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfilePage(user: user)),
              ),
              icon: const Icon(Icons.person_outline),
            ),
          ],
        ),
        body: IndexedStack(
          index: tab,
          children: [
            BookingPage(onBooked: load),
            HistoryPage(rides: rides, loading: loading, onRefresh: load),
            ProfilePage(user: user, embedded: true, onLogout: logout),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Book'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Rides'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Account'),
          ],
        ),
      );
}

class BookingPage extends StatefulWidget {
  final Future<void> Function() onBooked;
  const BookingPage({super.key, required this.onBooked});
  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final pickup = TextEditingController();
  final destination = TextEditingController();

  RideType type = RideType.car;
  bool locating = false;
  bool estimating = false;
  bool booking = false;
  double? estimatedFare;
  double? distanceKm;
  String? message;

  Future<void> useCurrentLocation() async {
    setState(() {
      locating = true;
      estimatedFare = null;
      distanceKm = null;
      message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Please turn on location on the emulator.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted.');
      }

      final pos = await Geolocator.getCurrentPosition();
      pickup.text =
          'GPS: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      if (mounted) setState(() {});
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> estimateFare() async {
    if (type == RideType.direct) {
      setState(() {
        estimatedFare = null;
        distanceKm = null;
        message =
            'Final fare will be calculated after the driver completes the ride.';
      });
      return;
    }
    if (pickup.text.trim().isEmpty) {
      _msg('Enter pickup or use current location.');
      return;
    }
    if (destination.text.trim().isEmpty) {
      setState(() {
        estimatedFare = null;
        distanceKm = null;
        message = 'Enter your destination to see the fare.';
      });
      return;
    }

    setState(() => estimating = true);
    try {
      final data = await Api.request(
        'POST',
        '/fare/estimate',
        body: {
          'pickup': pickup.text.trim(),
          'destination': destination.text.trim(),
          'ride_type': type.name,
        },
      );
      final rawFare = data['estimated_fare'] ?? data['fare'];
      setState(() {
        estimatedFare =
            rawFare == null ? null : double.tryParse(rawFare.toString());
        distanceKm = data['distance_km'] == null
            ? null
            : double.tryParse(data['distance_km'].toString());
        message = null;
      });
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => estimating = false);
    }
  }

  Future<void> requestRide() async {
    if (pickup.text.trim().isEmpty) {
      _msg('Please select or enter pickup.');
      return;
    }
    if (type != RideType.direct && destination.text.trim().isEmpty) {
      _msg('Please enter destination.');
      return;
    }
    if (type != RideType.direct && estimatedFare == null) {
      await estimateFare();
      if (estimatedFare == null) return;
    }

    final user = await Session.user();
    if (user == null) {
      _msg('Please login again.');
      return;
    }

    setState(() => booking = true);
    try {
      final data = await Api.request(
        'POST',
        '/rides',
        body: {
          'rider_id': user['id'],
          'pickup_location': pickup.text.trim(),
          'destination':
              type == RideType.direct ? null : destination.text.trim(),
          'ride_type': type.name,
          'fare': type == RideType.direct ? null : estimatedFare,
          'distance_km': distanceKm,
        },
      );

      await widget.onBooked();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, size: 48),
              const SizedBox(height: 10),
              const Text('Ride requested',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                type == RideType.direct
                    ? 'Your driver will complete the ride and the final fare will be calculated then.'
                    : 'Estimated fare: \$${estimatedFare!.toStringAsFixed(2)}',
              ),
              if (data['ride'] != null) ...[
                const SizedBox(height: 6),
                Text('Ride #${data['ride']['id']}'),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );

      pickup.clear();
      destination.clear();
      estimatedFare = null;
      distanceKm = null;
      message = null;
      setState(() {});
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => booking = false);
    }
  }

  void _msg(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  void dispose() {
    pickup.dispose();
    destination.dispose();
    super.dispose();
  }

  String title(RideType t) => switch (t) {
        RideType.car => 'Car',
        RideType.tukTuk => 'TukTuk',
        RideType.direct => 'Direct Ride',
      };

  String subtitle(RideType t) => switch (t) {
        RideType.car => 'Comfortable city car',
        RideType.tukTuk => 'Popular Cambodia ride',
        RideType.direct => 'No destination • final fare later',
      };

  IconData icon(RideType t) => switch (t) {
        RideType.car => Icons.directions_car_filled_rounded,
        RideType.tukTuk => Icons.electric_rickshaw_rounded,
        RideType.direct => Icons.route_rounded,
      };

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          const Text('Where are you going?',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Choose pickup, ride type and destination.',
              style: TextStyle(color: Color(0xFF6B7280))),
          const SizedBox(height: 18),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: pickup,
                    onChanged: (_) => setState(() {
                      estimatedFare = null;
                      distanceKm = null;
                    }),
                    decoration: InputDecoration(
                      labelText: 'Pickup location',
                      prefixIcon: const Icon(Icons.trip_origin),
                      suffixIcon: IconButton(
                        tooltip: 'Use current location',
                        onPressed: locating ? null : useCurrentLocation,
                        icon: locating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (type == RideType.direct)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                          'Direct Ride does not require a destination.'),
                    )
                  else
                    TextField(
                      controller: destination,
                      onChanged: (_) => setState(() {
                        estimatedFare = null;
                        distanceKm = null;
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Destination',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Choose ride',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...RideType.values.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    type = t;
                    estimatedFare = null;
                    distanceKm = null;
                    message = t == RideType.direct
                        ? 'Final fare will be calculated after the driver completes the ride.'
                        : null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: type == t ? const Color(0xFF111827) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: type == t
                          ? const Color(0xFF111827)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon(t),
                          color: type == t
                              ? Colors.white
                              : const Color(0xFF111827),
                          size: 30),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title(t),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: type == t
                                    ? Colors.white
                                    : const Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle(t),
                              style: TextStyle(
                                color: type == t
                                    ? Colors.white70
                                    : const Color(0xFF6B7280),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        type == t
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color:
                            type == t ? Colors.white : const Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (type != RideType.direct)
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: estimating ? null : estimateFare,
                icon: estimating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.calculate_outlined),
                label: const Text('Calculate estimated fare'),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, size: 30),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type == RideType.direct
                            ? 'Final fare'
                            : 'Estimated fare',
                        style: const TextStyle(
                            color: Color(0xFF6B7280), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        estimatedFare == null
                            ? '—'
                            : '\$${estimatedFare!.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 25, fontWeight: FontWeight.w900),
                      ),
                      if (distanceKm != null)
                        Text('${distanceKm!.toStringAsFixed(2)} km',
                            style: const TextStyle(
                                color: Color(0xFF6B7280), fontSize: 12)),
                      if (message != null)
                        Text(message!,
                            style: const TextStyle(
                                color: Color(0xFF6B7280), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: booking ? null : requestRide,
              child: booking
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Request Ride',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      );
}

class HistoryPage extends StatefulWidget {
  final List<Map<String, dynamic>> rides;
  final bool loading;
  final Future<void> Function()? onRefresh;

  const HistoryPage(
      {super.key, required this.rides, required this.loading, this.onRefresh});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final Set<int> busyRides = {};

  Future<void> _action(Map<String, dynamic> ride, String action,
      Future<void> Function() operation) async {
    final id = ride['id'] as int;
    setState(() => busyRides.add(id));
    try {
      await operation();
      if (!mounted) return;
      if (action.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(action)));
      }
      await widget.onRefresh?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => busyRides.remove(id));
    }
  }

  Future<String?> _token() => Session.token();

  Future<void> _cancel(Map<String, dynamic> ride) async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Cancel this ride?'),
              content: Text(
                  'Ride #${ride['id']} has not been assigned to a driver yet.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Keep ride')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Cancel ride')),
              ],
            ));
    if (accepted != true) return;
    await _action(ride, 'Ride cancelled.', () async {
      final token = await _token();
      if (token == null) throw Exception('Please sign in again.');
      await Api.request('PUT', '/rides/${ride['id']}/cancel', token: token);
    });
  }

  Future<void> _pay(Map<String, dynamic> ride) =>
      _action(ride, 'Cash payment recorded.', () async {
        final token = await _token();
        if (token == null) throw Exception('Please sign in again.');
        await Api.request('POST', '/payments',
            token: token,
            body: {'ride_id': ride['id'], 'payment_method': 'cash'});
      });

  Future<void> _rate(Map<String, dynamic> ride) async {
    int score = 5;
    final comment = TextEditingController();
    final rating = await showDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, setRating) => AlertDialog(
                title: const Text('Rate your driver'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          5,
                          (index) => IconButton(
                                onPressed: () =>
                                    setRating(() => score = index + 1),
                                color: const Color(0xFFF59E0B),
                                icon: Icon(index < score
                                    ? Icons.star
                                    : Icons.star_border),
                              ))),
                  TextField(
                      controller: comment,
                      maxLength: 500,
                      decoration: const InputDecoration(
                          labelText: 'Comment (optional)')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, score),
                      child: const Text('Submit rating')),
                ],
              ),
            ));
    if (rating != null) {
      await _action(ride, 'Thanks for your feedback.', () async {
        final token = await _token();
        if (token == null) throw Exception('Please sign in again.');
        await Api.request('POST', '/ratings', token: token, body: {
          'ride_id': ride['id'],
          'score': rating,
          'comment': comment.text.trim(),
        });
      });
    }
    comment.dispose();
  }

  Future<void> _track(Map<String, dynamic> ride) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TrackRideSheet(rideId: ride['id'] as int),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator());
    if (widget.rides.isEmpty) {
      return const Center(
        child: Text('No rides yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 25),
      itemCount: widget.rides.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final ride = widget.rides[i];
        final fare = double.tryParse((ride['fare'] ?? '').toString());
        final direct =
            ride['ride_type']?.toString().toLowerCase() == 'direct ride';
        final status = ride['status']?.toString() ?? 'requested';
        final busy = busyRides.contains(ride['id']);
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Ride #${ride['id'] ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    _StatusPill(
                        status: (ride['status'] ?? 'requested').toString()),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Pickup: ${ride['pickup_location'] ?? '-'}'),
                if (!direct &&
                    (ride['destination'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text('Destination: ${ride['destination'] ?? '-'}'),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      fare == null
                          ? (direct ? 'Final fare pending' : 'Fare pending')
                          : '\$${fare.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 17),
                    ),
                    const Spacer(),
                    Text(
                      (ride['driver_name'] ?? 'Waiting for driver').toString(),
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 13),
                    ),
                  ],
                ),
                if (['accepted', 'ongoing'].contains(status)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _track(ride),
                        icon: const Icon(Icons.location_searching),
                        label: const Text('Track driver'),
                      )),
                ],
                if (status == 'requested') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: busy ? null : () => _cancel(ride),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel request'),
                      )),
                ],
                if (status == 'completed' && fare != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    if (ride['paid'] != true)
                      Expanded(
                          child: FilledButton.icon(
                        onPressed: busy ? null : () => _pay(ride),
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.payments_outlined),
                        label: const Text('Pay cash'),
                      )),
                    if (ride['driver_id'] != null && ride['rated'] != true)
                      Expanded(
                          child: TextButton.icon(
                        onPressed: busy ? null : () => _rate(ride),
                        icon: const Icon(Icons.star_outline),
                        label: const Text('Rate driver'),
                      )),
                  ]),
                  if (ride['paid'] == true)
                    const Text('Paid',
                        style: TextStyle(
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrackRideSheet extends StatefulWidget {
  final int rideId;
  const _TrackRideSheet({required this.rideId});

  @override
  State<_TrackRideSheet> createState() => _TrackRideSheetState();
}

class _TrackRideSheetState extends State<_TrackRideSheet> {
  Map<String, dynamic>? tracking;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final token = await Session.token();
      if (token == null) return;
      final data = await Api.request('GET', '/rides/${widget.rideId}/track',
          token: token);
      if (!mounted) return;
      setState(() {
        tracking = Map<String, dynamic>.from(data as Map);
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = tracking?['location'];
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ride #${widget.rideId}',
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Status: ${tracking?['status'] ?? 'loading'}',
                    style: const TextStyle(color: Color(0xFF6B7280))),
                const SizedBox(height: 12),
                if (location is Map) ...[
                  const Text('Driver location',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${location['latitude']}, ${location['longitude']}'),
                  Text('Updated ${location['updated_at'] ?? 'just now'}',
                      style: const TextStyle(color: Color(0xFF6B7280))),
                ] else
                  const Text(
                      'Waiting for the driver to share their live location.'),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!,
                          style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 12),
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                        onPressed: refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh now'))),
              ],
            )));
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final completed = s == 'completed';
    final cancelled = s == 'cancelled';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: completed
            ? const Color(0xFFDCFCE7)
            : cancelled
                ? const Color(0xFFFEE2E2)
                : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: completed
              ? const Color(0xFF166534)
              : cancelled
                  ? const Color(0xFF991B1B)
                  : const Color(0xFF374151),
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool embedded;
  final Future<void> Function()? onLogout;

  const ProfilePage(
      {super.key, required this.user, this.embedded = false, this.onLogout});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<Map<String, dynamic>> profile = _loadProfile();

  Future<Map<String, dynamic>> _loadProfile() async {
    final token = await Session.token();
    if (token == null) return widget.user;
    final result = await Api.request('GET', '/profile', token: token);
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> _editProfile(Map<String, dynamic> current) async {
    final name = TextEditingController(text: current['name']?.toString() ?? '');
    final phone =
        TextEditingController(text: current['phone']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit your profile'),
        content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Enter your name'
                      : null),
              const SizedBox(height: 12),
              TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number')),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save changes')),
        ],
      ),
    );
    if (save == true && mounted) {
      final token = await Session.token();
      if (token != null) {
        try {
          final updated = await Api.request('PUT', '/profile',
              token: token,
              body: {'name': name.text.trim(), 'phone': phone.text.trim()});
          await Session.save(Map<String, dynamic>.from(updated as Map), token);
          if (mounted) setState(() => profile = _loadProfile());
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(e.toString().replaceFirst('Exception: ', ''))));
          }
        }
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadNotifications() async {
    final token = await Session.token();
    if (token == null) return [];
    final data = await Api.request('GET', '/my-notifications', token: token);
    return ((data as Map)['notifications'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item))
        .take(5)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<Map<String, dynamic>>(
      future: profile,
      builder: (context, snapshot) {
        final user = snapshot.data ?? widget.user;
        final displayName = user['name']?.toString() ?? 'Passenger';
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(22)),
                child: Row(children: [
                  CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF111827),
                      child: Text(
                          displayName.isEmpty
                              ? 'R'
                              : displayName[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900))),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(user['email']?.toString() ?? '',
                            style: const TextStyle(color: Colors.white70)),
                      ])),
                  IconButton(
                      tooltip: 'Edit profile',
                      onPressed:
                          snapshot.connectionState == ConnectionState.waiting
                              ? null
                              : () => _editProfile(user),
                      icon:
                          const Icon(Icons.edit_outlined, color: Colors.white)),
                ])),
            const SizedBox(height: 18),
            _InfoTile(
                'Phone',
                user['phone']?.toString().isNotEmpty == true
                    ? user['phone'].toString()
                    : 'Add a phone number'),
            _InfoTile('Account type',
                user['role']?.toString() == 'driver' ? 'Driver' : 'Passenger'),
            const SizedBox(height: 16),
            const Text('Recent notifications',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadNotifications(),
                builder: (context, notifications) {
                  if (notifications.connectionState ==
                      ConnectionState.waiting) {
                    return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  if (notifications.hasError) {
                    return const _InfoTile(
                        'Notifications', 'Unable to load right now');
                  }
                  if (notifications.data!.isEmpty) {
                    return const _InfoTile('You are all caught up',
                        'Ride updates will appear here');
                  }
                  return Column(
                      children: notifications.data!
                          .map((item) => Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                      color: Color(0xFFE5E7EB))),
                              child: ListTile(
                                  leading: const Icon(Icons.notifications_none),
                                  title: Text(
                                      item['title']?.toString() ??
                                          'Ride update',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  subtitle:
                                      Text(item['message']?.toString() ?? ''))))
                          .toList());
                }),
            if (widget.onLogout != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Log out'))),
            ],
          ],
        );
      },
    );
    return widget.embedded
        ? body
        : Scaffold(appBar: AppBar(title: const Text('Account')), body: body);
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
            const Spacer(),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
}
