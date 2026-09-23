import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiBase = 'http://10.0.2.2:3000/api';

void main() => runApp(const RideApp());

class RideApp extends StatelessWidget {
  const RideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
  static Future<Map<String, dynamic>> request(
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

    late http.Response response;
    if (method == 'POST') {
      response = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
    } else if (method == 'PUT') {
      response = await http.put(uri, headers: headers, body: jsonEncode(body ?? {}));
    } else {
      response = await http.get(uri, headers: headers);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = {'error': response.body.isEmpty ? 'Server error' : response.body};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded is Map && decoded['error'] != null
            ? decoded['error'].toString()
            : 'Request failed (${response.statusCode})',
      );
    }

    return Map<String, dynamic>.from(decoded as Map);
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

  static Future<void> saveChatGPTAccount(String account, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chatgpt_account', account);
    await prefs.setString('chatgpt_api_key', apiKey);
  }

  static Future<Map<String, String>?> chatGPTAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final account = prefs.getString('chatgpt_account');
    final apiKey = prefs.getString('chatgpt_api_key');

    if (account == null || apiKey == null) {
      return null;
    }

    return {'account': account, 'apiKey': apiKey};
  }

  static Future<void> clearChatGPTAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chatgpt_account');
    await prefs.remove('chatgpt_api_key');
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
      MaterialPageRoute(builder: (_) => user == null ? const LoginPage() : const HomePage()),
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
              Text('RideApp', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('Cambodia ride-hailing'),
            ],
          ),
        ),
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
        child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 42),
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
      await Session.save(Map<String, dynamic>.from(result['user']), result['token'].toString());
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _msg(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
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
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Login'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterPage()),
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
  bool loading = false;

  Future<void> register() async {
    if (name.text.trim().isEmpty || email.text.trim().isEmpty || password.text.isEmpty) {
      _msg('Name, email and password are required.');
      return;
    }
    setState(() => loading = true);
    try {
      await Api.request(
        'POST',
        '/users',
        body: {
          'name': name.text.trim(),
          'email': email.text.trim(),
          'phone': phone.text.trim(),
          'password': password.text,
          'role': 'rider',
        },
      );
      if (!mounted) return;
      _msg('Account created. Please login.');
      Navigator.pop(context);
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
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
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: loading ? null : register,
                child: loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
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
          title: const Text('RideApp', style: TextStyle(fontWeight: FontWeight.w800)),
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
            HistoryPage(rides: rides, loading: loading),
            ProfilePage(user: user, embedded: true, onLogout: logout),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Book'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Rides'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
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
        message = 'Final fare will be calculated after the driver completes the ride.';
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
        estimatedFare = rawFare == null ? null : double.tryParse(rawFare.toString());
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
          'destination': type == RideType.direct ? null : destination.text.trim(),
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

  void _msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                      child: const Text('Direct Ride does not require a destination.'),
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
                      color: type == t ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon(t), color: type == t ? Colors.white : const Color(0xFF111827), size: 30),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title(t),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: type == t ? Colors.white : const Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle(t),
                              style: TextStyle(
                                color: type == t ? Colors.white70 : const Color(0xFF6B7280),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        type == t ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: type == t ? Colors.white : const Color(0xFF9CA3AF),
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
                        type == RideType.direct ? 'Final fare' : 'Estimated fare',
                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        estimatedFare == null
                            ? '—'
                            : '\$${estimatedFare!.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                      ),
                      if (distanceKm != null)
                        Text('${distanceKm!.toStringAsFixed(2)} km',
                            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                      if (message != null)
                        Text(message!,
                            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Request Ride', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      );
}

class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> rides;
  final bool loading;

  const HistoryPage({super.key, required this.rides, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (rides.isEmpty) {
      return const Center(
        child: Text('No rides yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 25),
      itemCount: rides.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final ride = rides[i];
        final fare = double.tryParse((ride['fare'] ?? '').toString());
        final direct = ride['ride_type']?.toString() == 'direct';
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
                    _StatusPill(status: (ride['status'] ?? 'requested').toString()),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Pickup: ${ride['pickup_location'] ?? '-'}'),
                if (!direct)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text('Destination: ${ride['destination'] ?? '-'}'),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      direct && fare == null ? 'Final fare pending' : '\$${(fare ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                    ),
                    const Spacer(),
                    Text(
                      (ride['driver_name'] ?? 'Waiting for driver').toString(),
                      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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

class ProfilePage extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool embedded;
  final Future<void> Function()? onLogout;

  const ProfilePage({
    super.key,
    required this.user,
    this.embedded = false,
    this.onLogout,
  });

  Future<void> _connectChatGPT(BuildContext context) async {
    final accountCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController();

    final existing = await Session.chatGPTAccount();
    if (!context.mounted) {
      accountCtrl.dispose();
      apiKeyCtrl.dispose();
      return;
    }

    if (existing != null) {
      accountCtrl.text = existing['account'] ?? '';
      apiKeyCtrl.text = existing['apiKey'] ?? '';
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect ChatGPT account'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accountCtrl,
                decoration: const InputDecoration(labelText: 'ChatGPT account email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKeyCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API key'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final account = accountCtrl.text.trim();
              final apiKey = apiKeyCtrl.text.trim();

              if (account.isEmpty || apiKey.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter your ChatGPT account and API key.')),
                );
                return;
              }

              await Session.saveChatGPTAccount(account, apiKey);
              if (context.mounted) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Connect'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ChatGPT account connected.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<Map<String, String>?>(
      future: Session.chatGPTAccount(),
      builder: (context, snapshot) {
        final connected = snapshot.data != null;
        final accountName = snapshot.data?['account'] ?? 'Not connected';

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Center(
              child: CircleAvatar(
                radius: 35,
                child: Text(
                  (user['name']?.toString().isNotEmpty ?? false)
                      ? user['name'].toString().substring(0, 1).toUpperCase()
                      : 'R',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(user['name']?.toString() ?? 'Rider',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 18),
            _InfoTile('Email', user['email']?.toString() ?? '-'),
            _InfoTile('Phone', user['phone']?.toString() ?? '-'),
            _InfoTile('Role', user['role']?.toString() ?? 'rider'),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => _connectChatGPT(context),
                icon: Icon(connected ? Icons.check_circle : Icons.smart_toy_outlined),
                label: Text(connected ? 'ChatGPT connected' : 'Connect to ChatGPT'),
              ),
            ),
            if (connected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_circle_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(accountName)),
                    TextButton(
                      onPressed: () async {
                        await Session.clearChatGPTAccount();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ChatGPT account disconnected.')),
                          );
                        }
                      },
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              ),
            ],
            if (onLogout != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
              ),
            ],
          ],
        );
      },
    );

    return embedded ? body : Scaffold(appBar: AppBar(title: const Text('Account')), body: body);
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
