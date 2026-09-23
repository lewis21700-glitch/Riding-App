import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiBase = 'http://10.0.2.2:3000/api';

void main() {
  runApp(const RideApp());
}

// ============================================================
// APP
// ============================================================

class RideApp extends StatelessWidget {
  const RideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RideApp',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFE5E7EB),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFE5E7EB),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF2563EB),
              width: 1.5,
            ),
          ),
        ),
      ),
      home: const SplashPage(),
    );
  }
}

// ============================================================
// API
// ============================================================

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class Api {
  static Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$apiBase$path');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };

    http.Response response;

    try {
      if (method == 'GET') {
        response = await http.get(
          uri,
          headers: headers,
        );
      } else if (method == 'POST') {
        response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      } else if (method == 'PUT') {
        response = await http.put(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
      } else {
        throw const ApiException('Unsupported request method.');
      }
    } catch (e) {
      if (e is ApiException) rethrow;

      throw const ApiException(
        'Cannot connect to RideApp server.\n\n'
        'Make sure the backend is running on port 3000.',
      );
    }

    dynamic data;

    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Server error (${response.statusCode}).';

      if (data is Map && data['error'] != null) {
        message = data['error'].toString();
      } else if (data is Map && data['message'] != null) {
        message = data['message'].toString();
      }

      throw ApiException(message);
    }

    return data;
  }

  // ---------------- LOGIN ----------------

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final data = await request(
      'POST',
      '/login',
      body: {
        'email': email,
        'password': password,
      },
    );

    return Map<String, dynamic>.from(data as Map);
  }

  // ---------------- REGISTER ----------------

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final data = await request(
      'POST',
      '/users',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': 'rider',
      },
    );

    return Map<String, dynamic>.from(data as Map);
  }

  // ---------------- FARE ----------------

  static Future<Map<String, dynamic>> estimateFare({
    required String pickup,
    required String destination,
    required String rideType,
  }) async {
    final data = await request(
      'POST',
      '/fare/estimate',
      body: {
        'pickup': pickup,
        'destination': destination,
        'ride_type': rideType,
      },
    );

    return Map<String, dynamic>.from(data as Map);
  }

  // ---------------- CREATE RIDE ----------------

  static Future<Map<String, dynamic>> createRide({
    required int riderId,
    required String pickup,
    String? destination,
    required String rideType,
    double? fare,
    double? distanceKm,
    String? token,
  }) async {
    final data = await request(
      'POST',
      '/rides',
      token: token,
      body: {
        'rider_id': riderId,
        'pickup_location': pickup,
        'destination': destination,
        'ride_type': rideType,
        'fare': fare,
        'distance_km': distanceKm,
      },
    );

    return Map<String, dynamic>.from(data as Map);
  }

  // ---------------- RIDER HISTORY ----------------

  static Future<List<Map<String, dynamic>>> myRides({
    required int riderId,
    String? token,
  }) async {
    final data = await request(
      'GET',
      '/my-rides?rider_id=$riderId',
      token: token,
    );

    if (data is Map && data['rides'] is List) {
      return (data['rides'] as List)
          .map(
            (item) => Map<String, dynamic>.from(item as Map),
          )
          .toList();
    }

    if (data is List) {
      return data
          .map(
            (item) => Map<String, dynamic>.from(item as Map),
          )
          .toList();
    }

    return [];
  }
}

// ============================================================
// SESSION
// ============================================================

class Session {
  static Future<void> save({
    required Map<String, dynamic> user,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'user',
      jsonEncode(user),
    );

    await prefs.setString(
      'token',
      token,
    );
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString('user');

    if (value == null) {
      return null;
    }

    try {
      return Map<String, dynamic>.from(
        jsonDecode(value) as Map,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('token');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('user');
    await prefs.remove('token');
  }
}

// ============================================================
// SPLASH
// ============================================================

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();

    checkSession();
  }

  Future<void> checkSession() async {
    await Future.delayed(
      const Duration(milliseconds: 600),
    );

    final user = await Session.getUser();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (user == null) {
            return const LoginPage();
          }

          return const HomePage();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(),
            SizedBox(height: 18),
            Text(
              'RideApp',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Cambodia ride-hailing',
              style: TextStyle(
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LOGO
// ============================================================

class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Icon(
        Icons.local_taxi_rounded,
        color: Colors.white,
        size: 42,
      ),
    );
  }
}

// ============================================================
// LOGIN
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      showMessage(
        'Please enter your email and password.',
      );

      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final data = await Api.login(
        email,
        password,
      );

      final user = Map<String, dynamic>.from(
        data['user'] as Map,
      );

      final token = data['token']?.toString() ?? '';

      await Session.save(
        user: user,
        token: token,
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const HomePage(),
        ),
        (_) => false,
      );
    } catch (e) {
      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 430,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const AppLogo(),

                  const SizedBox(height: 22),

                  const Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 7),

                  const Text(
                    'Sign in to book a ride',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                    ),
                  ),

                  const SizedBox(height: 28),

                  TextField(
                    controller: emailController,
                    keyboardType:
                        TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(
                        Icons.email_outlined,
                      ),
                    ),
                  ),

                  const SizedBox(height: 13),

                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(
                        Icons.lock_outline,
                      ),
                    ),
                    onSubmitted: (_) => login(),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed:
                          loading ? null : login,
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const RegisterPage(),
                        ),
                      );
                    },
                    child: const Text(
                      'Create account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// REGISTER
// ============================================================

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() =>
      _RegisterPageState();
}

class _RegisterPageState
    extends State<RegisterPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;

  Future<void> register() async {
    if (nameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      showMessage(
        'Name, email and password are required.',
      );

      return;
    }

    setState(() {
      loading = true;
    });

    try {
      await Api.register(
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        phone: phoneController.text.trim(),
        password: passwordController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account created successfully.',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Account',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(
                Icons.person_outline,
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: emailController,
            keyboardType:
                TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(
                Icons.email_outlined,
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(
                Icons.phone_outlined,
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(
                Icons.lock_outline,
              ),
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed:
                  loading ? null : register,
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Create Account',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RIDE TYPES
// ============================================================

enum RideType {
  passApp,
  comfort,
  premium,
  direct,
}

extension RideTypeData on RideType {
  String get apiValue {
    switch (this) {
      case RideType.passApp:
        return 'passapp';

      case RideType.comfort:
        return 'comfort';

      case RideType.premium:
        return 'premium';

      case RideType.direct:
        return 'direct';
    }
  }

  String get title {
    switch (this) {
      case RideType.passApp:
        return 'PassApp';

      case RideType.comfort:
        return 'Comfort';

      case RideType.premium:
        return 'Premium';

      case RideType.direct:
        return 'Direct Ride';
    }
  }

  String get description {
    switch (this) {
      case RideType.passApp:
        return 'Affordable everyday ride';

      case RideType.comfort:
        return 'More comfortable vehicle';

      case RideType.premium:
        return 'Premium ride experience';

      case RideType.direct:
        return 'No destination • final fare later';
    }
  }

  IconData get icon {
    switch (this) {
      case RideType.passApp:
        return Icons.electric_rickshaw_rounded;

      case RideType.comfort:
        return Icons.directions_car_rounded;

      case RideType.premium:
        return Icons.local_taxi_rounded;

      case RideType.direct:
        return Icons.route_rounded;
    }
  }
}

// ============================================================
// HOME
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int currentTab = 0;

  Map<String, dynamic> user = {};

  List<Map<String, dynamic>> rides = [];

  bool loadingRides = false;

  @override
  void initState() {
    super.initState();

    loadData();
  }

  Future<void> loadData() async {
    user = await Session.getUser() ?? {};

    final riderId =
        int.tryParse('${user['id']}');

    if (riderId == null) {
      if (mounted) {
        setState(() {});
      }

      return;
    }

    setState(() {
      loadingRides = true;
    });

    try {
      rides = await Api.myRides(
        riderId: riderId,
        token: await Session.getToken(),
      );
    } catch (_) {
      // Booking screen remains usable.
    }

    if (mounted) {
      setState(() {
        loadingRides = false;
      });
    }
  }

  Future<void> logout() async {
    await Session.clear();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RideApp',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ProfilePage(user: user),
                ),
              );
            },
            icon: const Icon(
              Icons.person_outline,
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: currentTab,
        children: [
          BookingPage(
            onRideCreated: loadData,
          ),

          HistoryPage(
            rides: rides,
            loading: loadingRides,
          ),

          ProfilePage(
            user: user,
            embedded: true,
            onLogout: logout,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab,
        onDestinationSelected: (index) {
          setState(() {
            currentTab = index;
          });

          if (index == 1) {
            loadData();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons.home_outlined,
            ),
            selectedIcon: Icon(
              Icons.home,
            ),
            label: 'Book',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.receipt_long_outlined,
            ),
            selectedIcon: Icon(
              Icons.receipt_long,
            ),
            label: 'Rides',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.person_outline,
            ),
            selectedIcon: Icon(
              Icons.person,
            ),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BOOKING
// ============================================================

class BookingPage extends StatefulWidget {
  final Future<void> Function() onRideCreated;

  const BookingPage({
    super.key,
    required this.onRideCreated,
  });

  @override
  State<BookingPage> createState() =>
      _BookingPageState();
}

class _BookingPageState
    extends State<BookingPage> {
  final pickupController =
      TextEditingController();

  final destinationController =
      TextEditingController();

  RideType selectedRide =
      RideType.passApp;

  double? estimatedFare;

  double? distanceKm;

  bool locating = false;

  bool calculating = false;

  bool requesting = false;

  String? fareMessage;

  // ----------------------------------------------------------
  // CURRENT LOCATION
  // ----------------------------------------------------------

  Future<void> useCurrentLocation() async {
    setState(() {
      locating = true;
      estimatedFare = null;
      distanceKm = null;
      fareMessage = null;
    });

    try {
      final enabled =
          await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        throw const ApiException(
          'Location service is turned off.',
        );
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission ==
              LocationPermission.denied ||
          permission ==
              LocationPermission.deniedForever) {
        throw const ApiException(
          'Location permission was not granted.',
        );
      }

      final position =
          await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      pickupController.text =
          'GPS: ${position.latitude.toStringAsFixed(5)}, '
          '${position.longitude.toStringAsFixed(5)}';

      if (mounted) {
        setState(() {});
      }

      if (selectedRide != RideType.direct &&
          destinationController.text
              .trim()
              .isNotEmpty) {
        await calculateFare();
      }
    } catch (e) {
      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          locating = false;
        });
      }
    }
  }

  // ----------------------------------------------------------
  // FARE
  // ----------------------------------------------------------

  Future<void> calculateFare() async {
    if (selectedRide == RideType.direct) {
      setState(() {
        estimatedFare = null;
        distanceKm = null;
        fareMessage =
            'Final fare will be calculated after the ride is completed.';
      });

      return;
    }

    final pickup =
        pickupController.text.trim();

    final destination =
        destinationController.text.trim();

    if (pickup.isEmpty) {
      showMessage(
        'Please enter pickup location first.',
      );

      return;
    }

    if (destination.isEmpty) {
      setState(() {
        estimatedFare = null;
        distanceKm = null;
        fareMessage =
            'Enter destination to see estimated fare.';
      });

      return;
    }

    setState(() {
      calculating = true;
    });

    try {
      final data =
          await Api.estimateFare(
        pickup: pickup,
        destination: destination,
        rideType: selectedRide.apiValue,
      );

      final fareValue =
          data['estimated_fare'] ??
              data['fare'];

      final distanceValue =
          data['distance_km'] ??
              data['distance'];

      setState(() {
        estimatedFare =
            double.tryParse(
          '$fareValue',
        );

        distanceKm =
            double.tryParse(
          '$distanceValue',
        );

        fareMessage = null;
      });
    } catch (e) {
      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          calculating = false;
        });
      }
    }
  }

  // ----------------------------------------------------------
  // REQUEST RIDE
  // ----------------------------------------------------------

  Future<void> requestRide() async {
    final pickup =
        pickupController.text.trim();

    final destination =
        destinationController.text.trim();

    if (pickup.isEmpty) {
      showMessage(
        'Please select pickup location.',
      );

      return;
    }

    if (selectedRide != RideType.direct &&
        destination.isEmpty) {
      showMessage(
        'Please enter your destination.',
      );

      return;
    }

    if (selectedRide != RideType.direct &&
        estimatedFare == null) {
      await calculateFare();

      if (!mounted ||
          estimatedFare == null) {
        return;
      }
    }

    final user =
        await Session.getUser();

    final token =
        await Session.getToken();

    final riderId =
        int.tryParse('${user?['id']}');

    if (riderId == null) {
      showMessage(
        'Login session expired. Please login again.',
      );

      return;
    }

    setState(() {
      requesting = true;
    });

    try {
      final data =
          await Api.createRide(
        riderId: riderId,
        pickup: pickup,
        destination:
            selectedRide == RideType.direct
                ? null
                : destination,
        rideType: selectedRide.apiValue,
        fare:
            selectedRide == RideType.direct
                ? null
                : estimatedFare,
        distanceKm: distanceKm,
        token: token,
      );

      await widget.onRideCreated();

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              size: 52,
              color: Colors.green,
            ),
            title: const Text(
              'Ride Requested',
            ),
            content: Text(
              selectedRide ==
                      RideType.direct
                  ? 'Your Direct Ride has been requested. '
                      'The final fare will be calculated after completion.'
                  : 'Your ride has been requested.\n\n'
                      'Estimated fare: \$${estimatedFare!.toStringAsFixed(2)}',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'Done',
                ),
              ),
            ],
          );
        },
      );

      pickupController.clear();
      destinationController.clear();

      setState(() {
        estimatedFare = null;
        distanceKm = null;
        fareMessage = null;
        selectedRide = RideType.passApp;
      });
    } catch (e) {
      showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    } finally {
      if (mounted) {
        setState(() {
          requesting = false;
        });
      }
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  void dispose() {
    pickupController.dispose();
    destinationController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direct =
        selectedRide == RideType.direct;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        30,
      ),
      children: [
        const Text(
          'Where are you going?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 5),

        const Text(
          'Book a ride anywhere in Phnom Penh.',
          style: TextStyle(
            color: Color(0xFF6B7280),
          ),
        ),

        const SizedBox(height: 18),

        // ----------------------------------------------------
        // LOCATIONS
        // ----------------------------------------------------

        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(18),
            side: const BorderSide(
              color: Color(0xFFE5E7EB),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller:
                      pickupController,
                  onChanged: (_) {
                    setState(() {
                      estimatedFare = null;
                      distanceKm = null;
                      fareMessage = null;
                    });
                  },
                  decoration:
                      InputDecoration(
                    labelText:
                        'Pickup Location',
                    prefixIcon: const Icon(
                      Icons.trip_origin,
                    ),
                    suffixIcon: IconButton(
                      tooltip:
                          'Use current location',
                      onPressed:
                          locating
                              ? null
                              : useCurrentLocation,
                      icon: locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.my_location,
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (direct)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(
                      13,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFFF3F4F6,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: const Text(
                      'Direct Ride does not require a destination.',
                    ),
                  )
                else
                  TextField(
                    controller:
                        destinationController,
                    onChanged: (_) {
                      setState(() {
                        estimatedFare = null;
                        distanceKm = null;
                        fareMessage = null;
                      });
                    },
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Destination',
                      prefixIcon: Icon(
                        Icons.location_on_outlined,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        // ----------------------------------------------------
        // RIDE TYPES
        // ----------------------------------------------------

        const Text(
          'Choose Ride',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 10),

        ...RideType.values.map(
          (ride) {
            final selected =
                selectedRide == ride;

            return Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 10,
              ),
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
                onTap: () {
                  setState(() {
                    selectedRide = ride;
                    estimatedFare = null;
                    distanceKm = null;

                    fareMessage =
                        ride ==
                                RideType.direct
                            ? 'Final fare will be calculated after the ride is completed.'
                            : null;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.all(
                    14,
                  ),
                  decoration:
                      BoxDecoration(
                    color: selected
                        ? const Color(
                            0xFF111827,
                          )
                        : Colors.white,
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                    border: Border.all(
                      color: selected
                          ? const Color(
                              0xFF111827,
                            )
                          : const Color(
                              0xFFE5E7EB,
                            ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ride.icon,
                        size: 31,
                        color: selected
                            ? Colors.white
                            : const Color(
                                0xFF111827,
                              ),
                      ),

                      const SizedBox(
                        width: 13,
                      ),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              ride.title,
                              style: TextStyle(
                                fontWeight:
                                    FontWeight
                                        .w900,
                                color: selected
                                    ? Colors
                                        .white
                                    : const Color(
                                        0xFF111827,
                                      ),
                              ),
                            ),

                            const SizedBox(
                              height: 3,
                            ),

                            Text(
                              ride.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: selected
                                    ? Colors
                                        .white70
                                    : const Color(
                                        0xFF6B7280,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Icon(
                        selected
                            ? Icons
                                .check_circle
                            : Icons
                                .radio_button_unchecked,
                        color: selected
                            ? Colors.white
                            : const Color(
                                0xFF9CA3AF,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // ----------------------------------------------------
        // CALCULATE FARE
        // ----------------------------------------------------

        if (!direct)
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed:
                  calculating
                      ? null
                      : calculateFare,
              icon: calculating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons
                          .calculate_outlined,
                    ),
              label: const Text(
                'Calculate Estimated Fare',
              ),
            ),
          ),

        const SizedBox(height: 14),

        // ----------------------------------------------------
        // FARE
        // ----------------------------------------------------

        Container(
          padding:
              const EdgeInsets.all(17),
          decoration:
              BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(18),
            border: Border.all(
              color:
                  const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.payments_outlined,
                size: 31,
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      direct
                          ? 'Final Fare'
                          : 'Estimated Fare',
                      style:
                          const TextStyle(
                        color:
                            Color(0xFF6B7280),
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      estimatedFare ==
                              null
                          ? '—'
                          : '\$${estimatedFare!.toStringAsFixed(2)}',
                      style:
                          const TextStyle(
                        fontSize: 25,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),

                    if (distanceKm != null)
                      Text(
                        '${distanceKm!.toStringAsFixed(2)} km',
                        style:
                            const TextStyle(
                          color:
                              Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),

                    if (fareMessage != null)
                      Text(
                        fareMessage!,
                        style:
                            const TextStyle(
                          color:
                              Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ----------------------------------------------------
        // REQUEST
        // ----------------------------------------------------

        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed:
                requesting
                    ? null
                    : requestRide,
            child: requesting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Request Ride',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// RIDE HISTORY
// ============================================================

class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> rides;

  final bool loading;

  const HistoryPage({
    super.key,
    required this.rides,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (rides.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 55,
              color: Color(0xFF9CA3AF),
            ),
            SizedBox(height: 12),
            Text(
              'No rides yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        28,
      ),
      itemCount: rides.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final ride = rides[index];

        final status =
            '${ride['status'] ?? 'requested'}';

        final type =
            '${ride['ride_type'] ?? ''}';

        final fare =
            double.tryParse(
          '${ride['fare'] ?? ''}',
        );

        final direct =
            type == 'direct';

        return Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(17),
            side: const BorderSide(
              color: Color(0xFFE5E7EB),
            ),
          ),
          child: Padding(
            padding:
                const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Ride #${ride['id'] ?? '-'}',
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    StatusPill(
                      status: status,
                    ),
                  ],
                ),

                const SizedBox(height: 11),

                Text(
                  'Pickup: ${ride['pickup_location'] ?? '-'}',
                ),

                if (!direct)
                  Padding(
                    padding:
                        const EdgeInsets.only(
                      top: 5,
                    ),
                    child: Text(
                      'Destination: ${ride['destination'] ?? '-'}',
                    ),
                  ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Text(
                      direct &&
                              fare == null
                          ? 'Final fare pending'
                          : '\$${(fare ?? 0).toStringAsFixed(2)}',
                      style:
                          const TextStyle(
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),

                    const Spacer(),

                    Text(
                      '${ride['driver_name'] ?? 'Waiting for driver'}',
                      style:
                          const TextStyle(
                        color:
                            Color(0xFF6B7280),
                        fontSize: 13,
                      ),
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

// ============================================================
// STATUS
// ============================================================

class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final value =
        status.toLowerCase();

    Color background;
    Color foreground;

    if (value == 'completed') {
      background =
          const Color(0xFFDCFCE7);
      foreground =
          const Color(0xFF166534);
    } else if (value == 'cancelled') {
      background =
          const Color(0xFFFEE2E2);
      foreground =
          const Color(0xFF991B1B);
    } else if (value == 'ongoing') {
      background =
          const Color(0xFFDBEAFE);
      foreground =
          const Color(0xFF1D4ED8);
    } else {
      background =
          const Color(0xFFFEF3C7);
      foreground =
          const Color(0xFF92400E);
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration:
          BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ============================================================
// PROFILE
// ============================================================

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

  @override
  Widget build(BuildContext context) {
    final name =
        user['name']?.toString() ??
            'Rider';

    final initial =
        name.isNotEmpty
            ? name
                .substring(0, 1)
                .toUpperCase()
            : 'R';

    final content = ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 15),

        Center(
          child: CircleAvatar(
            radius: 38,
            backgroundColor:
                const Color(0xFF2563EB),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight:
                    FontWeight.w900,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Center(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),

        const SizedBox(height: 20),

        InfoTile(
          label: 'Email',
          value:
              '${user['email'] ?? '-'}',
        ),

        InfoTile(
          label: 'Phone',
          value:
              '${user['phone'] ?? '-'}',
        ),

        InfoTile(
          label: 'Role',
          value:
              '${user['role'] ?? 'rider'}',
        ),

        if (onLogout != null) ...[
          const SizedBox(height: 10),

          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(
                Icons.logout,
              ),
              label: const Text(
                'Log Out',
              ),
            ),
          ),
        ],
      ],
    );

    if (embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Account',
        ),
      ),
      body: content,
    );
  }
}

// ============================================================
// INFO TILE
// ============================================================

class InfoTile extends StatelessWidget {
  final String label;

  final String value;

  const InfoTile({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 15,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color:
              const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style:
                const TextStyle(
              color:
                  Color(0xFF6B7280),
            ),
          ),

          const Spacer(),

          Flexible(
            child: Text(
              value,
              textAlign:
                  TextAlign.right,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
