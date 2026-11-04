import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'driver_home_page.dart';

String get _resolveApiBase {
  const env = String.fromEnvironment('API_BASE_URL');
  if (env.isNotEmpty) return env;
  if (kIsWeb) return 'http://127.0.0.1:3000/api';
  try {
    if (Platform.isAndroid) return 'http://10.0.2.2:3000/api';
  } catch (_) {}
  return 'http://127.0.0.1:3000/api';
}

final String apiBase = _resolveApiBase;
String get _resolveMapTileUrl {
  const configuredUrl = String.fromEnvironment('MAP_TILE_URL');
  if (configuredUrl.isNotEmpty) return configuredUrl;
  // The Android emulator cannot validate the machine's locally installed TLS
  // interception CA. Use the development tile proxy on the host instead of
  // weakening certificate checks in the Android app.
  if (!kIsWeb && Platform.isAndroid) {
    return 'http://10.0.2.2:3001/tiles/{z}/{x}/{y}.png';
  }
  return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}

final String mapTileUrl = _resolveMapTileUrl;
const String mapAttribution = String.fromEnvironment(
  'MAP_ATTRIBUTION',
  defaultValue: '© OpenStreetMap contributors',
);
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class PushNotifications {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static bool _initialized = false;
  static bool _listening = false;

  static bool get configured =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _senderId.isNotEmpty &&
      _projectId.isNotEmpty;

  static Future<bool> _initialize() async {
    if (!configured) return false;
    if (!_initialized) {
      try {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: _apiKey,
            appId: _appId,
            messagingSenderId: _senderId,
            projectId: _projectId,
          ),
        );
        _initialized = true;
      } catch (_) {
        return false;
      }
    }
    _installMessageListeners();
    return true;
  }

  static void _installMessageListeners() {
    if (_listening) return;
    _listening = true;
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_saveToken(token));
    }, onError: (_) {});
    FirebaseMessaging.onMessage.listen((message) {
      final context = appNavigatorKey.currentContext;
      if (context == null) return;
      final title = message.notification?.title ?? 'RideApp update';
      final body = message.notification?.body ?? '';
      // This Firebase stream callback is synchronous and reads the current navigator context.
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(body.isEmpty ? title : '$title: $body')));
    }, onError: (_) {});
  }

  static Future<void> registerDevice() async {
    if (!await _initialize()) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _saveToken(token);
    } catch (_) {
      // Push is optional; a missing Firebase setup must not block sign-in.
    }
  }

  static Future<void> _saveToken(String token) async {
    final accessToken = await Session.token();
    if (accessToken == null) return;
    try {
      await Api.request(
        'POST',
        '/push-tokens?${Uri(queryParameters: {
              'token': token,
              'platform': 'android'
            }).query}',
        token: accessToken,
      );
    } catch (_) {
      // Retried on the next app start or FCM token refresh.
    }
  }

  static Future<void> unregisterDevice() async {
    final accessToken = await Session.token();
    if (accessToken == null) return;
    try {
      await Api.request('DELETE', '/push-tokens', token: accessToken);
    } catch (_) {}
    if (await _initialize()) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
  }
}

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B3ACD),
          primary: const Color(0xFF0B3ACD),
          secondary: const Color(0xFF264399),
        ),
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
    final authToken = token ?? await Session.token();
    final headers = {
      'Content-Type': 'application/json',
      if (authToken != null) 'Authorization': 'Bearer $authToken',
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
  static const _secureStorage = FlutterSecureStorage();
  static const _tokenKey = 'token';

  static Future<void> save(Map<String, dynamic> user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user));
    await _secureStorage.write(key: _tokenKey, value: token);
    await prefs.remove(_tokenKey);
  }

  static Future<Map<String, dynamic>?> user() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('user');
    return value == null ? null : Map<String, dynamic>.from(jsonDecode(value));
  }

  static Future<String?> token() async {
    final secureToken = await _secureStorage.read(key: _tokenKey);
    if (secureToken != null) return secureToken;

    // Upgrade sessions saved by earlier app versions without signing users out.
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_tokenKey);
    if (legacyToken == null) return null;
    await _secureStorage.write(key: _tokenKey, value: legacyToken);
    await prefs.remove(_tokenKey);
    return legacyToken;
  }

  static Future<void> clear() async {
    unawaited(PushNotifications.unregisterDevice());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    await _secureStorage.delete(key: _tokenKey);
    await prefs.remove(_tokenKey);
    await prefs.remove('chatgpt_account');
    await prefs.remove('chatgpt_api_key');
  }
}

int unreadNotificationCount(Iterable<Map<String, dynamic>> notifications) =>
    notifications.where((item) => !_asBool(item['is_read'])).length;

List<Map<String, dynamic>> notificationItems(dynamic data) {
  final raw = data is List
      ? data
      : data is Map
          ? (data['notifications'] as List? ?? const [])
          : const [];
  return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
}

String formatFare(Object? amount, [Object? currency]) {
  final value = double.tryParse(amount?.toString() ?? '');
  if (value == null) return '—';
  if (currency?.toString().toUpperCase() == 'KHR') {
    final digits = value.round().toString();
    final grouped = digits.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},');
    return '$grouped៛';
  }
  return '\$${value.toStringAsFixed(2)}';
}

const int khrPerUsd = 4100;

int usdToKhr(Object? amount) {
  final value = double.tryParse(amount?.toString() ?? '');
  if (value == null || !value.isFinite || value < 0) return 0;
  return (value * khrPerUsd / 100).round() * 100;
}

String formatFarePair(Object? amount) {
  final value = double.tryParse(amount?.toString() ?? '');
  if (value == null || !value.isFinite) return '—';
  return '\$${value.toStringAsFixed(2)}  •  ${formatFare(usdToKhr(value), 'KHR')}';
}

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  Timer? refreshTimer;
  bool requestActive = false;
  int unreadCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCount();
    _startRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefresh();
      _loadCount();
    } else {
      refreshTimer?.cancel();
      refreshTimer = null;
    }
  }

  void _startRefresh() {
    refreshTimer?.cancel();
    refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadCount();
    });
  }

  Future<void> _loadCount() async {
    if (requestActive) return;
    requestActive = true;
    try {
      final token = await Session.token();
      if (token == null) return;
      final data = await Api.request('GET', '/my-notifications', token: token);
      final notifications = notificationItems(data);
      if (mounted) {
        setState(() => unreadCount = unreadNotificationCount(notifications));
      }
    } catch (_) {
      // Keep the last known badge while the API is temporarily unavailable.
    } finally {
      requestActive = false;
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
    if (mounted) await _loadCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: unreadCount == 0
            ? 'Notifications'
            : '$unreadCount unread notifications',
        onPressed: _openNotifications,
        icon: Badge(
          isLabelVisible: unreadCount > 0,
          label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
          child: const Icon(Icons.notifications_outlined),
        ),
      );
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
    if (user != null) unawaited(PushNotifications.registerDevice());
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => user != null && user['role'] == 'driver'
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
    MaterialPageRoute(builder: (_) => const HomePage()),
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
      unawaited(PushNotifications.registerDevice());
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
                    const Text('Sign in to your RideApp account',
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
        },
      );
      if (!mounted) return;
      final user = Map<String, dynamic>.from(data['user']);
      final token = data['token'].toString();
      await Session.save(user, token);
      unawaited(PushNotifications.registerDevice());
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Create a passenger account to book rides.'),
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

enum RideType { standard, comfort, premium, directRide }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int tab = 0;
  Map<String, dynamic> user = {};
  List<Map<String, dynamic>> rides = [];
  bool loading = true;
  bool _requestActive = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load(showLoading: false);
      }
    });
  }

  Future<void> load() => _load(showLoading: true);

  Future<void> _load({required bool showLoading}) async {
    if (_requestActive) return;
    _requestActive = true;
    if (showLoading && mounted) setState(() => loading = true);
    try {
      final nextUser = await Session.user() ?? {};
      final token = await Session.token();
      List<Map<String, dynamic>>? nextRides;
      if (token != null) {
        try {
          final data = await Api.request('GET', '/my-rides', token: token);
          nextRides = ((data['rides'] ?? []) as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } catch (_) {
          // Keep the last successful ride list while the API is unavailable.
        }
      }
      if (!mounted) return;
      setState(() {
        user = nextUser;
        if (nextRides != null) rides = nextRides;
      });
    } finally {
      _requestActive = false;
      if (mounted && loading) setState(() => loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(showLoading: false);
  }

  Future<void> logout() async {
    await Session.clear();
    if (!mounted) return;
    setState(() {
      user = {};
      rides = [];
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: tab == 0
            ? null
            : AppBar(
                title: const Text('RideApp',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                actions: [
                  const NotificationBell(),
                  IconButton(
                    tooltip: 'Passenger account',
                    onPressed: () => setState(() => tab = 2),
                    icon: const Icon(Icons.person_outline),
                  ),
                ],
              ),
        body: IndexedStack(
          index: tab,
          children: [
            BookingPage(
              onBooked: load,
              onProfileTap: () => setState(() => tab = 2),
            ),
            HistoryPage(rides: rides, loading: loading, onRefresh: load),
            ProfilePage(
              user: user,
              embedded: true,
              onLogout: logout,
              onAuthSuccess: load,
            ),
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

class PlaceItem {
  final String label;
  final double lat;
  final double lng;
  final IconData icon;
  final String category;

  const PlaceItem(this.label, this.lat, this.lng, this.icon, this.category);
}

const List<PlaceItem> kPhnomPenhLandmarks = [
  PlaceItem('Aeon Mall 1 (Samdach Sothearos Blvd)', 11.5475, 104.9351,
      Icons.shopping_bag_outlined, 'Shopping Mall'),
  PlaceItem('Independence Monument', 11.5564, 104.9282,
      Icons.account_balance_outlined, 'Landmark / City Center'),
  PlaceItem('Royal Palace Phnom Penh', 11.5638, 104.9317, Icons.castle_outlined,
      'Historical Palace'),
  PlaceItem('Central Market (Phsar Thmey)', 11.5696, 104.9213,
      Icons.storefront_outlined, 'Famous Market'),
  PlaceItem('Wat Phnom Historical Park', 11.5762, 104.9230,
      Icons.temple_buddhist_outlined, 'Temple Park'),
  PlaceItem('Russian Market (Toul Tom Poung)', 11.5408, 104.9142,
      Icons.shopping_cart_outlined, 'Market & Food'),
  PlaceItem('Phnom Penh International Airport (PNH)', 11.5466, 104.8441,
      Icons.flight_takeoff_outlined, 'Airport'),
  PlaceItem('Tuol Sleng Genocide Museum (S-21)', 11.5494, 104.9174,
      Icons.museum_outlined, 'Museum'),
  PlaceItem('Phnom Penh Railway Station', 11.5739, 104.9169,
      Icons.train_outlined, 'Train Station'),
  PlaceItem('Riverside (Sisowath Quay)', 11.5682, 104.9312,
      Icons.water_outlined, 'Riverside Promenade'),
  PlaceItem('Olympic Stadium Phnom Penh', 11.5578, 104.9126,
      Icons.stadium_outlined, 'Sports Complex'),
  PlaceItem('Aeon Mall 2 Sen Sok', 11.5976, 104.8860,
      Icons.shopping_bag_outlined, 'Shopping Mall'),
  PlaceItem('Calmette Hospital', 11.5833, 104.9167,
      Icons.local_hospital_outlined, 'General Hospital'),
  PlaceItem('NagaWorld Resort & Casino', 11.5528, 104.9392,
      Icons.hotel_outlined, 'Resort & Entertainment'),
  PlaceItem('Koh Pich (Diamond Island)', 11.5478, 104.9431,
      Icons.apartment_outlined, 'Business & Convention'),
  PlaceItem('BKK1 (Boeung Keng Kang 1)', 11.5510, 104.9248,
      Icons.location_city_outlined, 'Cafe & Embassy District'),
];

PlaceItem? findLandmark(String text) {
  final clean = text.trim().toLowerCase();
  if (clean.isEmpty) return null;
  for (final item in kPhnomPenhLandmarks) {
    final label = item.label.toLowerCase();
    if (label.contains(clean) || clean.contains(label)) return item;
  }
  final words = clean.split(RegExp(r'\s+')).where((w) => w.length > 2);
  for (final item in kPhnomPenhLandmarks) {
    if (words.any((w) => item.label.toLowerCase().contains(w))) return item;
  }
  return null;
}

class BookingPage extends StatefulWidget {
  final Future<void> Function() onBooked;
  final VoidCallback? onProfileTap;
  const BookingPage({super.key, required this.onBooked, this.onProfileTap});
  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final pickup = TextEditingController();
  final destination = TextEditingController();
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];

  RideType type = RideType.standard;
  bool locating = false;
  bool estimating = false;
  bool booking = false;
  bool _mapReady = false;
  bool _pickingDestination = false;
  double? estimatedFare;
  double? distanceKm;
  double? estimatedDurationMinutes;
  double? pickupLatitude;
  double? pickupLongitude;
  double? destinationLatitude;
  double? destinationLongitude;
  String? message;
  Map<String, double> typeFaresUsd = {};
  Map<String, int> typeFaresKhr = {};
  Map<String, dynamic>? fareBreakdown;

  LatLng? get _pickupPoint => pickupLatitude == null || pickupLongitude == null
      ? null
      : LatLng(pickupLatitude!, pickupLongitude!);

  LatLng? get _destinationPoint =>
      destinationLatitude == null || destinationLongitude == null
          ? null
          : LatLng(destinationLatitude!, destinationLongitude!);

  List<LatLng> get _selectedPoints => [
        if (_pickupPoint != null) _pickupPoint!,
        if (_destinationPoint != null) _destinationPoint!,
      ];

  List<LatLng> _generateRoadCurve(LatLng p1, LatLng p2) {
    final list = <LatLng>[];
    const steps = 10;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final lat = p1.latitude + (p2.latitude - p1.latitude) * t;
      final lng = p1.longitude + (p2.longitude - p1.longitude) * t;
      final offset = math.sin(t * math.pi) * 0.0006;
      list.add(LatLng(lat + offset, lng - offset));
    }
    return list;
  }

  void _focusBookingMap() {
    if (!_mapReady) return;
    final points = _selectedPoints;
    if (points.length > 1) {
      _mapController.fitCamera(CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(56),
        maxZoom: 16,
      ));
    } else if (points.length == 1) {
      _mapController.move(points.first, 15);
    }
  }

  void _swapLocations() {
    setState(() {
      final tempText = pickup.text;
      pickup.text = destination.text;
      destination.text = tempText;

      final tempLat = pickupLatitude;
      final tempLng = pickupLongitude;
      pickupLatitude = destinationLatitude;
      pickupLongitude = destinationLongitude;
      destinationLatitude = tempLat;
      destinationLongitude = tempLng;

      estimatedFare = null;
      distanceKm = null;
      estimatedDurationMinutes = null;
      _routePoints = [];
      message = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusBookingMap();
      if (pickupLatitude != null && destinationLatitude != null) {
        estimateFare();
      }
    });
  }

  void _selectPlace(PlaceItem place, {required bool isPickup}) {
    setState(() {
      if (isPickup) {
        pickup.text = place.label;
        pickupLatitude = place.lat;
        pickupLongitude = place.lng;
        _pickingDestination = true;
      } else {
        destination.text = place.label;
        destinationLatitude = place.lat;
        destinationLongitude = place.lng;
      }
      estimatedFare = null;
      distanceKm = null;
      estimatedDurationMinutes = null;
      _routePoints = [];
      message = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusBookingMap();
      if (pickupLatitude != null && destinationLatitude != null) {
        estimateFare();
      }
    });
  }

  Future<void> _openPlacePicker({required bool isPickup}) async {
    final searchCtrl = TextEditingController();
    List<PlaceItem> filteredLandmarks = List.of(kPhnomPenhLandmarks);
    List<Map<String, dynamic>> remoteResults = [];
    bool isSearchingRemote = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void filterPlaces(String q) async {
              final clean = q.trim().toLowerCase();
              if (clean.isEmpty) {
                setModalState(() {
                  filteredLandmarks = List.of(kPhnomPenhLandmarks);
                  remoteResults = [];
                  isSearchingRemote = false;
                });
                return;
              }

              final local = kPhnomPenhLandmarks.where((p) {
                return p.label.toLowerCase().contains(clean) ||
                    p.category.toLowerCase().contains(clean);
              }).toList();

              setModalState(() {
                filteredLandmarks = local;
                if (clean.length >= 3) {
                  isSearchingRemote = true;
                }
              });

              if (clean.length >= 3) {
                try {
                  final resp = await Api.request(
                    'GET',
                    '/places/search?q=${Uri.encodeQueryComponent(clean)}',
                  );
                  final places = ((resp as Map)['places'] as List? ?? const [])
                      .map((p) => Map<String, dynamic>.from(p as Map))
                      .toList();
                  if (ctx.mounted) {
                    setModalState(() {
                      remoteResults = places;
                      isSearchingRemote = false;
                    });
                  }
                } catch (_) {
                  if (ctx.mounted) {
                    setModalState(() => isSearchingRemote = false);
                  }
                }
              }
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.45,
              maxChildSize: 0.94,
              expand: false,
              builder: (ctx, scrollCtrl) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            isPickup ? Icons.trip_origin : Icons.location_on,
                            color: isPickup
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isPickup
                                ? 'Select Pickup Location'
                                : 'Select Destination',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: searchCtrl,
                        autofocus: false,
                        onChanged: filterPlaces,
                        decoration: InputDecoration(
                          hintText: 'Search landmark, hotel, street...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    filterPlaces('');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          if (isPickup) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.my_location, size: 18),
                                label: const Text('My GPS',
                                    style: TextStyle(fontSize: 12)),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  useCurrentLocation();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.touch_app_outlined,
                                  size: 18),
                              label: const Text('Pick on Map',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _pickingDestination = !isPickup;
                                });
                                _msg(isPickup
                                    ? 'Tap anywhere on the map to set pickup'
                                    : 'Tap anywhere on the map to set destination');
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 18),
                    Expanded(
                      child: ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          if (isSearchingRemote)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            ),
                          if (remoteResults.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'SEARCH RESULTS',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF6B7280)),
                              ),
                            ),
                            ...remoteResults.map((place) {
                              final label = place['label']?.toString() ?? '';
                              final lat = double.tryParse(
                                      place['latitude']?.toString() ?? '') ??
                                  11.5564;
                              final lng = double.tryParse(
                                      place['longitude']?.toString() ?? '') ??
                                  104.9282;
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.search,
                                    color: Color(0xFF0B3ACD)),
                                title: Text(label,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _selectPlace(
                                    PlaceItem(label, lat, lng,
                                        Icons.location_on, 'Search Result'),
                                    isPickup: isPickup,
                                  );
                                },
                              );
                            }),
                            const Divider(height: 18),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              'POPULAR PLACES & LANDMARKS',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6B7280)),
                            ),
                          ),
                          ...filteredLandmarks.map((place) {
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(place.icon,
                                    color: const Color(0xFF0B3ACD), size: 20),
                              ),
                              title: Text(place.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(place.category,
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF6B7280))),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 18, color: Color(0xFF9CA3AF)),
                              onTap: () {
                                Navigator.pop(ctx);
                                _selectPlace(place, isPickup: isPickup);
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _selectMapPoint(LatLng point) {
    final label =
        'GPS: ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    final wasPickingDest = _pickingDestination;
    setState(() {
      if (wasPickingDest) {
        destinationLatitude = point.latitude;
        destinationLongitude = point.longitude;
        destination.text = label;
      } else {
        pickupLatitude = point.latitude;
        pickupLongitude = point.longitude;
        pickup.text = label;
        _pickingDestination = true;
      }
      estimatedFare = null;
      distanceKm = null;
      estimatedDurationMinutes = null;
      _routePoints = [];
      message = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusBookingMap());
    unawaited(_reverseGeocode(point, destination: wasPickingDest));
    if (pickupLatitude != null && destinationLatitude != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => estimateFare());
    }
  }

  Future<void> _reverseGeocode(LatLng point,
      {required bool destination}) async {
    try {
      final data = await Api.request('GET',
          '/places/reverse?lat=${point.latitude}&lon=${point.longitude}');
      final label = (data as Map)['label']?.toString();
      if (!mounted || label == null || label.isEmpty) {
        if (!destination && mounted) {
          setState(() {
            if (pickupLatitude == point.latitude &&
                pickupLongitude == point.longitude) {
              pickup.text =
                  'Current location (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';
            }
          });
        }
        return;
      }
      setState(() {
        if (destination &&
            destinationLatitude == point.latitude &&
            destinationLongitude == point.longitude) {
          this.destination.text = label;
        } else if (!destination &&
            pickupLatitude == point.latitude &&
            pickupLongitude == point.longitude) {
          pickup.text = label;
        }
      });
      if (destination && pickupLatitude != null) await estimateFare();
    } catch (_) {
      if (!destination && mounted) {
        setState(() {
          if (pickupLatitude == point.latitude &&
              pickupLongitude == point.longitude) {
            pickup.text =
                'Current location (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';
          }
        });
      }
      if (destination && pickupLatitude != null) await estimateFare();
    }
  }

  Future<void> _searchPlace({required bool isPickup}) async {
    await _openPlacePicker(isPickup: isPickup);
  }

  Future<void> useCurrentLocation() async {
    setState(() {
      locating = true;
      estimatedFare = null;
      distanceKm = null;
      message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on Location services, then try again.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        throw Exception(
            'Allow RideApp to access location in Android Settings.');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!pos.latitude.isFinite ||
          !pos.longitude.isFinite ||
          pos.latitude.abs() > 90 ||
          pos.longitude.abs() > 180) {
        throw Exception('The device returned an invalid GPS location.');
      }
      final double lat = pos.latitude;
      final double lng = pos.longitude;

      setState(() {
        pickupLatitude = lat;
        pickupLongitude = lng;
        pickup.text = 'Finding nearby address…';
        _routePoints = [];
        _pickingDestination = true;
      });
      await _reverseGeocode(LatLng(lat, lng), destination: false);

      if (destinationLatitude != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => estimateFare());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mapReady && mounted) {
          _mapController.move(LatLng(lat, lng), 15);
        }
      });
    } catch (error) {
      if (mounted) {
        final detail = error.toString().replaceFirst('Exception: ', '');
        _msg(detail.isEmpty
            ? 'Could not get your current location. Check GPS and permissions.'
            : detail);
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> estimateFare() async {
    if (pickup.text.trim().isEmpty) {
      _msg('Enter pickup or use current location.');
      return;
    }

    if (pickupLatitude == null || pickupLongitude == null) {
      final match = findLandmark(pickup.text);
      if (match != null) {
        pickupLatitude = match.lat;
        pickupLongitude = match.lng;
      } else {
        pickupLatitude = 11.5564;
        pickupLongitude = 104.9282;
      }
    }

    if (destination.text.trim().isEmpty) {
      setState(() {
        estimatedFare = null;
        distanceKm = null;
        estimatedDurationMinutes = null;
        typeFaresUsd.clear();
        typeFaresKhr.clear();
        fareBreakdown = null;
        message =
            'Choose “Where to?” for an upfront fare, or book without a destination and settle after the ride.';
      });
      return;
    }

    if (destinationLatitude == null || destinationLongitude == null) {
      final match = findLandmark(destination.text);
      if (match != null) {
        destinationLatitude = match.lat;
        destinationLongitude = match.lng;
      } else {
        destinationLatitude = 11.5475;
        destinationLongitude = 104.9351;
      }
    }

    setState(() => estimating = true);
    try {
      final data = await Api.request(
        'POST',
        '/fare/estimate',
        body: {
          'pickup': pickup.text.trim(),
          'destination': destination.text.trim(),
          'ride_type': vehicleType(type),
          'pickup_lat': pickupLatitude,
          'pickup_lng': pickupLongitude,
          'destination_lat': destinationLatitude,
          'destination_lng': destinationLongitude,
        },
      );
      final rawFare = data['estimated_fare'] ?? data['fare'];
      final tfMap = data['type_fares'];
      final newTypeFaresUsd = <String, double>{};
      final newTypeFaresKhr = <String, int>{};
      if (tfMap is Map) {
        tfMap.forEach((k, v) {
          if (v is Map) {
            newTypeFaresUsd[k.toString()] =
                double.tryParse(v['usd']?.toString() ?? '0') ?? 0.0;
            newTypeFaresKhr[k.toString()] =
                int.tryParse(v['khr']?.toString() ?? '0') ?? 0;
          }
        });
      }
      final newBreakdown = data['breakdown'] is Map
          ? Map<String, dynamic>.from(data['breakdown'] as Map)
          : null;
      setState(() {
        typeFaresUsd = newTypeFaresUsd;
        typeFaresKhr = newTypeFaresKhr;
        fareBreakdown = newBreakdown;
        estimatedFare =
            rawFare == null ? null : double.tryParse(rawFare.toString());
        distanceKm = data['distance_km'] == null
            ? null
            : double.tryParse(data['distance_km'].toString());
        estimatedDurationMinutes = data['estimated_duration_minutes'] == null
            ? null
            : double.tryParse(data['estimated_duration_minutes'].toString());
        pickupLatitude ??=
            double.tryParse(data['pickup_lat']?.toString() ?? '');
        pickupLongitude ??=
            double.tryParse(data['pickup_lng']?.toString() ?? '');
        destinationLatitude ??=
            double.tryParse(data['destination_lat']?.toString() ?? '');
        destinationLongitude ??=
            double.tryParse(data['destination_lng']?.toString() ?? '');
        message = null;
        _routePoints = ((data['route_points'] as List?) ?? const [])
            .map((point) => LatLng(
                  double.parse((point as Map)['latitude'].toString()),
                  double.parse(point['longitude'].toString()),
                ))
            .toList();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusBookingMap());
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
    final hasDestination = destination.text.trim().isNotEmpty;
    if (hasDestination && estimatedFare == null) {
      await estimateFare();
      if (estimatedFare == null) return;
    }

    final user = await Session.user();
    if (user == null) {
      _msg('Please sign in from the Account tab to book your ride.');
      widget.onProfileTap?.call();
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
          'destination': hasDestination ? destination.text.trim() : null,
          'ride_type': vehicleType(type),
          'fare': hasDestination ? estimatedFare : null,
          'distance_km': distanceKm,
          if (pickupLatitude != null && pickupLongitude != null) ...{
            'pickup_lat': pickupLatitude,
            'pickup_lng': pickupLongitude,
          },
          if (destinationLatitude != null && destinationLongitude != null) ...{
            'destination_lat': destinationLatitude,
            'destination_lng': destinationLongitude,
          },
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
              const Icon(Icons.check_circle,
                  size: 48, color: Color(0xFF16A34A)),
              const SizedBox(height: 10),
              const Text('Ride requested',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                hasDestination
                    ? 'Estimated fare: ${formatFarePair(estimatedFare)}'
                    : 'No destination set. The driver will record the trip distance and calculate the final fare after the ride.',
              ),
              if (data['ride_id'] != null) ...[
                const SizedBox(height: 6),
                Text('Ride #${data['ride_id']}'),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0B3ACD)),
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
      pickupLatitude = null;
      pickupLongitude = null;
      destinationLatitude = null;
      destinationLongitude = null;
      estimatedFare = null;
      distanceKm = null;
      estimatedDurationMinutes = null;
      _routePoints = [];
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

  String vehicleType(RideType t) => switch (t) {
        RideType.standard => 'Standard',
        RideType.comfort => 'Comfort',
        RideType.premium => 'Premium',
        RideType.directRide => 'Direct Ride',
      };

  int capacity(RideType t) => switch (t) {
        RideType.standard => 4,
        RideType.comfort => 4,
        RideType.premium => 4,
        RideType.directRide => 4,
      };

  int startingFareKhr(RideType t) => switch (t) {
        RideType.standard => 4000,
        RideType.comfort => 6000,
        RideType.premium => 10000,
        RideType.directRide => 0,
      };

  String fareKey(RideType t) => switch (t) {
        RideType.standard => 'Car',
        RideType.comfort => 'Comfort',
        RideType.premium => 'Premium',
        RideType.directRide => 'Direct Ride',
      };

  String subtitle(RideType t) => switch (t) {
        RideType.standard => 'Affordable everyday ride • Up to 4 seats',
        RideType.comfort => 'Spacious vehicle & AC • Up to 4 seats',
        RideType.premium => 'Executive comfort • Up to 4 seats',
        RideType.directRide => 'No destination • Final fare calculated later',
      };

  IconData icon(RideType t) => switch (t) {
        RideType.standard => Icons.directions_car_filled_rounded,
        RideType.comfort => Icons.airport_shuttle_rounded,
        RideType.premium => Icons.local_taxi_rounded,
        RideType.directRide => Icons.route_rounded,
      };

  Widget _buildBookingMap() => FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _pickupPoint ??
              _destinationPoint ??
              const LatLng(11.5564, 104.9282),
          initialZoom: 14,
          onMapReady: () {
            _mapReady = true;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _focusBookingMap());
          },
          onTap: (_, point) => _selectMapPoint(point),
        ),
        children: [
          TileLayer(
            urlTemplate: mapTileUrl,
            userAgentPackageName: 'com.example.mobile',
            maxNativeZoom: 19,
          ),
          if (_pickupPoint != null && _destinationPoint != null)
            PolylineLayer(polylines: [
              // High-contrast casing border
              Polyline(
                points: _routePoints.length > 1
                    ? _routePoints
                    : _generateRoadCurve(_pickupPoint!, _destinationPoint!),
                strokeWidth: 8,
                color: const Color(0xFF1E293B),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
              // Main navigation line with gradient towards drop-off pin
              Polyline(
                points: _routePoints.length > 1
                    ? _routePoints
                    : _generateRoadCurve(_pickupPoint!, _destinationPoint!),
                strokeWidth: 5,
                color: const Color(0xFF0B3ACD),
                gradientColors: const [
                  Color(0xFF0B3ACD),
                  Color(0xFF2563EB),
                  Color(0xFFDC2626),
                ],
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ]),
          MarkerLayer(markers: [
            if (_pickupPoint != null)
              Marker(
                point: _pickupPoint!,
                width: 90,
                height: 54,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      child: const Text('Pickup',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                    const Icon(Icons.location_on,
                        color: Color(0xFF16A34A), size: 32),
                  ],
                ),
              ),
            if (_destinationPoint != null)
              Marker(
                point: _destinationPoint!,
                width: 100,
                height: 54,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      child: const Text('Destination',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                    const Icon(Icons.location_on,
                        color: Color(0xFFDC2626), size: 32),
                  ],
                ),
              ),
          ]),
          RichAttributionWidget(attributions: [
            TextSourceAttribution(mapAttribution),
          ]),
        ],
      );

  Widget _buildRideCard(RideType rideType) {
    final selected = type == rideType;
    final typeName = vehicleType(rideType);
    final typeFareKey = fareKey(rideType);
    final hasMultiFare = typeFaresUsd.containsKey(typeFareKey);
    final cardFare = hasMultiFare
        ? typeFaresUsd[typeFareKey]
        : (rideType == type ? estimatedFare : null);
    final cardFareKhr = hasMultiFare
        ? typeFaresKhr[typeFareKey]
        : cardFare == null
            ? null
            : usdToKhr(cardFare);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            type = rideType;
            if (hasMultiFare) {
              estimatedFare = typeFaresUsd[typeFareKey];
            }
            message = destination.text.trim().isEmpty
                ? 'Choose “Where to?” for an upfront fare, or book now and settle after the trip.'
                : null;
            if (destinationLatitude != null &&
                pickupLatitude != null &&
                !hasMultiFare) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => estimateFare());
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF1FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  selected ? const Color(0xFF0B3ACD) : const Color(0xFFE5E7EB),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected ? Colors.white : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon(rideType), color: const Color(0xFF0B3ACD)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(typeName,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle(rideType),
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rideType == RideType.directRide
                      ? 'Final fare after ride'
                      : cardFareKhr != null
                          ? formatFare(cardFareKhr, 'KHR')
                          : 'from ${formatFare(startingFareKhr(rideType), 'KHR')}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? const Color(0xFF0B3ACD)
                        : const Color(0xFF1E293B),
                    fontSize: 14,
                  ),
                ),
                if (rideType != RideType.directRide)
                  Text(
                    cardFare != null
                        ? '\$${cardFare.toStringAsFixed(2)}'
                        : '\$${(startingFareKhr(rideType) / khrPerUsd).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _quickChip(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ActionChip(
          avatar: Icon(icon, size: 15, color: const Color(0xFF0B3ACD)),
          label: Text(label,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          onPressed: onTap,
        ),
      );

  void _quickSelect(PlaceItem item) {
    if (_pickingDestination) {
      _selectPlace(item, isPickup: false);
    } else {
      _selectPlace(item, isPickup: true);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          _buildBookingMap(),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 16,
                              offset: Offset(0, 4)),
                        ],
                      ),
                      child: Column(children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B3ACD)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.local_taxi_rounded,
                                color: Color(0xFF0B3ACD), size: 24),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('RideApp',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF212633))),
                                Text('Book your ride in Phnom Penh',
                                    style: TextStyle(
                                        color: Color(0xFF2E3C66),
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                          const NotificationBell(),
                          IconButton(
                            tooltip: 'Passenger account',
                            onPressed: widget.onProfileTap,
                            icon: const Icon(Icons.person_outline),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    setState(() => _pickingDestination = false),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: !_pickingDestination
                                        ? const Color(0xFF0B3ACD)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.trip_origin,
                                          size: 14,
                                          color: !_pickingDestination
                                              ? Colors.white
                                              : const Color(0xFF16A34A)),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Set Pickup',
                                        style: TextStyle(
                                          color: !_pickingDestination
                                              ? Colors.white
                                              : const Color(0xFF2B2D33),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    setState(() => _pickingDestination = true),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _pickingDestination
                                        ? const Color(0xFF0B3ACD)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on,
                                          size: 14,
                                          color: _pickingDestination
                                              ? Colors.white
                                              : const Color(0xFFDC2626)),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Set Destination',
                                        style: TextStyle(
                                          color: _pickingDestination
                                              ? Colors.white
                                              : const Color(0xFF2B2D33),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0x1F000000),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                        child: Column(children: [
                          Row(
                            children: [
                              const Icon(Icons.trip_origin,
                                  color: Color(0xFF16A34A), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: pickup,
                                  onSubmitted: (_) =>
                                      _searchPlace(isPickup: true),
                                  onChanged: (_) => setState(() {
                                    pickupLatitude = null;
                                    pickupLongitude = null;
                                    estimatedFare = null;
                                    distanceKm = null;
                                    estimatedDurationMinutes = null;
                                    _routePoints = [];
                                  }),
                                  style: const TextStyle(fontSize: 14),
                                  decoration: const InputDecoration(
                                    hintText: 'Enter or pick pickup location',
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding:
                                        EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              if (pickup.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() {
                                    pickup.clear();
                                    pickupLatitude = null;
                                    pickupLongitude = null;
                                    estimatedFare = null;
                                    _routePoints = [];
                                  }),
                                ),
                              IconButton(
                                tooltip: 'Browse places',
                                icon: const Icon(Icons.list_alt,
                                    size: 20, color: Color(0xFF0B3ACD)),
                                onPressed: () =>
                                    _openPlacePicker(isPickup: true),
                              ),
                              IconButton(
                                tooltip: 'Use current location',
                                onPressed: locating ? null : useCurrentLocation,
                                icon: locating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location,
                                        size: 20, color: Color(0xFF0B3ACD)),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Expanded(child: Divider(height: 1)),
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _swapLocations,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: const Icon(Icons.swap_vert,
                                      size: 18, color: Color(0xFF0B3ACD)),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: destination,
                                  onChanged: (_) => setState(() {
                                    destinationLatitude = null;
                                    destinationLongitude = null;
                                    estimatedFare = null;
                                    distanceKm = null;
                                    estimatedDurationMinutes = null;
                                    _routePoints = [];
                                  }),
                                  onSubmitted: (_) =>
                                      _searchPlace(isPickup: false),
                                  style: const TextStyle(fontSize: 14),
                                  decoration: const InputDecoration(
                                    hintText: 'Where to? (Destination)',
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding:
                                        EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              if (destination.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() {
                                    destination.clear();
                                    destinationLatitude = null;
                                    destinationLongitude = null;
                                    estimatedFare = null;
                                    _routePoints = [];
                                  }),
                                ),
                              IconButton(
                                tooltip: 'Browse places',
                                icon: const Icon(Icons.search,
                                    size: 20, color: Color(0xFF0B3ACD)),
                                onPressed: () =>
                                    _openPlacePicker(isPickup: false),
                              ),
                            ],
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _quickChip(Icons.shopping_bag_outlined, 'Aeon 1',
                              () => _quickSelect(kPhnomPenhLandmarks[0])),
                          _quickChip(
                              Icons.account_balance_outlined,
                              'Independence Mon.',
                              () => _quickSelect(kPhnomPenhLandmarks[1])),
                          _quickChip(
                              Icons.storefront_outlined,
                              'Central Market',
                              () => _quickSelect(kPhnomPenhLandmarks[3])),
                          _quickChip(
                              Icons.flight_takeoff_outlined,
                              'Airport PNH',
                              () => _quickSelect(kPhnomPenhLandmarks[6])),
                          _quickChip(
                              Icons.shopping_cart_outlined,
                              'Russian Market',
                              () => _quickSelect(kPhnomPenhLandmarks[5])),
                          _quickChip(
                              Icons.temple_buddhist_outlined,
                              'Wat Phnom',
                              () => _quickSelect(kPhnomPenhLandmarks[4])),
                          _quickChip(Icons.castle_outlined, 'Royal Palace',
                              () => _quickSelect(kPhnomPenhLandmarks[2])),
                          _quickChip(
                              Icons.local_hospital_outlined,
                              'Calmette Hospital',
                              () => _quickSelect(kPhnomPenhLandmarks[12])),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.22,
            maxChildSize: 0.78,
            snap: true,
            snapSizes: const [0.38, 0.78],
            builder: (context, scrollController) => Material(
              color: const Color(0xFFF9FAFB),
              elevation: 12,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(26)),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Row(children: [
                    const Expanded(
                      child: Text('Choose your ride',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w900)),
                    ),
                    if (_selectedPoints.length == 2)
                      const Text('Route selected',
                          style: TextStyle(
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                  ]),
                  const SizedBox(height: 10),
                  ...RideType.values.map(_buildRideCard),
                  if (destination.text.trim().isEmpty && message == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Add “Where to?” for an upfront fare, or book without a destination.',
                        style:
                            TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                      ),
                    ),
                  if (estimatedFare != null || message != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF1FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.payments_outlined,
                                  color: Color(0xFF0B3ACD), size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Estimated fare',
                                    style: TextStyle(
                                        color: Color(0xFF6B7280), fontSize: 12),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        estimatedFare == null
                                            ? (message ?? '—')
                                            : formatFare(
                                                typeFaresKhr[fareKey(type)] ??
                                                    usdToKhr(estimatedFare),
                                                'KHR'),
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900),
                                      ),
                                      if (estimatedFare != null) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '(\$${estimatedFare!.toStringAsFixed(2)})',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF4B5563)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ]),
                          if (distanceKm != null ||
                              estimatedDurationMinutes != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${distanceKm?.toStringAsFixed(1) ?? "—"} km road distance',
                                  style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  '~${estimatedDurationMinutes?.round().toString() ?? "—"} min drive',
                                  style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ],
                          if (fareBreakdown != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Base \$${fareBreakdown!['base_fare']} + \$${fareBreakdown!['per_km_rate']}/km',
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                  ),
                                  Text(
                                    '1 USD = ${khrPerUsd.toString()} KHR',
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0B3ACD),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: booking ? null : requestRide,
                      child: booking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Book ${vehicleType(type)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
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

  Future<void> _payKhqr(Map<String, dynamic> ride) async {
    final fare = ride['fare'];
    if (fare == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StaticKhqrPaymentSheet(amount: fare),
    );
  }

  Future<void> _showReceipt(Map<String, dynamic> ride) =>
      _action(ride, '', () async {
        final token = await _token();
        if (token == null) throw Exception('Please sign in again.');
        final receipt = await Api.request('GET', '/rides/${ride['id']}/receipt',
            token: token);
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) =>
              _ReceiptSheet(receipt: Map<String, dynamic>.from(receipt as Map)),
        );
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
                          : formatFarePair(fare),
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
                  if (!_asBool(ride['paid']))
                    Row(children: [
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
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton.icon(
                        onPressed: busy ? null : () => _payKhqr(ride),
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Pay KHQR'),
                      )),
                    ]),
                  if (ride['driver_id'] != null && !_asBool(ride['rated']))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: busy ? null : () => _rate(ride),
                        icon: const Icon(Icons.star_outline),
                        label: const Text('Rate driver'),
                      ),
                    ),
                  if (_asBool(ride['paid']))
                    Row(children: [
                      const Expanded(
                          child: Text('Paid',
                              style: TextStyle(
                                  color: Color(0xFF166534),
                                  fontWeight: FontWeight.w700))),
                      TextButton.icon(
                          onPressed: busy ? null : () => _showReceipt(ride),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('View receipt')),
                    ]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StaticKhqrPaymentSheet extends StatelessWidget {
  final Object? amount;

  const _StaticKhqrPaymentSheet({required this.amount});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pay with ACLEDA KHQR',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Ride fare  ${formatFarePair(amount)}',
                style: const TextStyle(color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            const Text('Payee: SENG KIMVICHSA',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Container(
              constraints: const BoxConstraints(maxWidth: 360, maxHeight: 470),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/acleda_khqr.png',
                fit: BoxFit.contain,
                semanticLabel: 'ACLEDA KHQR payment code for SENG KIMVICHSA',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Open ACLEDA Super App, scan the QR, and enter the exact ride fare shown above. This static QR does not verify payment in RideApp. Confirm the transfer in ACLEDA before marking the ride paid.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF4B5563), height: 1.45),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptSheet extends StatelessWidget {
  final Map<String, dynamic> receipt;
  const _ReceiptSheet({required this.receipt});

  String _money(Object? amount) => formatFarePair(amount);

  String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? 'Date unavailable' : formatReceiptDate(date);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                  child: Icon(Icons.check_circle,
                      size: 44, color: Color(0xFF15803D))),
              const SizedBox(height: 10),
              const Center(
                  child: Text('Payment receipt',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800))),
              const SizedBox(height: 4),
              Center(child: Text('Receipt #${receipt['receipt_id']}')),
              const Divider(height: 28),
              _ReceiptLine(label: 'Ride', value: '#${receipt['ride_id']}'),
              _ReceiptLine(
                  label: 'Passenger',
                  value: '${receipt['rider_name'] ?? 'Passenger'}'),
              _ReceiptLine(
                  label: 'Driver',
                  value: '${receipt['driver_name'] ?? 'Driver'}'),
              _ReceiptLine(
                  label: 'Pickup',
                  value: '${receipt['pickup_location'] ?? '-'}'),
              if ((receipt['destination'] ?? '').toString().isNotEmpty)
                _ReceiptLine(
                    label: 'Destination', value: '${receipt['destination']}'),
              _ReceiptLine(
                  label: 'Payment method',
                  value: '${receipt['payment_method'] ?? 'cash'}'),
              _ReceiptLine(label: 'Paid', value: _date(receipt['paid_at'])),
              const Divider(height: 26),
              Row(children: [
                const Expanded(
                    child: Text('Total paid',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                Text(_money(receipt['amount']),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'))),
            ],
          ),
        ),
      );
}

bool _asBool(Object? value) =>
    value == true || value == 1 || value == '1' || value == 'true';

class _ReceiptLine extends StatelessWidget {
  final String label;
  final String value;
  const _ReceiptLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 112,
              child: Text(label,
                  style: const TextStyle(color: Color(0xFF6B7280)))),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

String formatReceiptDate(DateTime date) {
  final local = date.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$mm-$dd $hh:$min';
}

class _TrackRideSheet extends StatefulWidget {
  final int rideId;
  const _TrackRideSheet({required this.rideId});

  @override
  State<_TrackRideSheet> createState() => _TrackRideSheetState();
}

class _TrackRideSheetState extends State<_TrackRideSheet> {
  final MapController _mapController = MapController();
  Map<String, dynamic>? tracking;
  String? error;
  Timer? timer;
  bool _mapReady = false;
  bool _didFocusDriver = false;

  LatLng? _pointFrom(dynamic value) {
    if (value is! Map) return null;
    final latitude = double.tryParse(value['latitude']?.toString() ?? '');
    final longitude = double.tryParse(value['longitude']?.toString() ?? '');
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  LatLng? get _driverPoint => _pointFrom(tracking?['location']);
  LatLng? get _pickupPoint => _pointFrom(tracking?['pickup']);
  LatLng? get _destinationPoint => _pointFrom(tracking?['destination']);

  List<LatLng> get _routePoints {
    final raw = tracking?['route_points'] as List?;
    if (raw != null && raw.length > 1) {
      return raw
          .map((p) => LatLng(
                double.parse((p as Map)['latitude'].toString()),
                double.parse(p['longitude'].toString()),
              ))
          .toList();
    }
    return [
      if (_pickupPoint != null) _pickupPoint!,
      if (_driverPoint != null) _driverPoint!,
      if (_destinationPoint != null) _destinationPoint!,
    ];
  }

  void _focusDriverIfAvailable() {
    if (!_mapReady || _didFocusDriver || _driverPoint == null) return;
    _didFocusDriver = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _routePoints,
          padding: const EdgeInsets.all(48),
          maxZoom: 16,
        ),
      );
    });
  }

  void _recenterMap() {
    final points = _routePoints;
    if (points.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      ),
    );
  }

  Widget _mapMarker(String label, IconData icon, Color color) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 5),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
          Icon(icon, color: color, size: 34),
        ],
      );

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
      _focusDriverIfAvailable();
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
    final pickup = tracking?['pickup'];
    final destination = tracking?['destination'];
    final driverPoint = _driverPoint;
    final pickupPoint = _pickupPoint;
    final destinationPoint = _destinationPoint;
    final initialCenter = driverPoint ??
        pickupPoint ??
        destinationPoint ??
        const LatLng(11.5564, 104.9282); // Phnom Penh
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: Text('Ride #${widget.rideId}',
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                    tooltip: 'Refresh tracking',
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh)),
              ]),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Status: ${tracking?['status'] ?? 'loading'}',
                    style: const TextStyle(color: Color(0xFF6B7280))),
              ),
              const SizedBox(height: 12),
              if (_routePoints.isNotEmpty)
                SizedBox(
                  height: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: initialCenter,
                          initialZoom: driverPoint == null ? 14 : 15,
                          onMapReady: () {
                            _mapReady = true;
                            _focusDriverIfAvailable();
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: mapTileUrl,
                            userAgentPackageName: 'com.example.mobile',
                            maxNativeZoom: 19,
                          ),
                          if (_routePoints.length > 1)
                            PolylineLayer(polylines: [
                              Polyline(
                                points: _routePoints,
                                strokeWidth: 8,
                                color: const Color(0xFF1E293B),
                                strokeCap: StrokeCap.round,
                                strokeJoin: StrokeJoin.round,
                              ),
                              Polyline(
                                points: _routePoints,
                                strokeWidth: 5,
                                color: const Color(0xFF0B3ACD),
                                gradientColors: const [
                                  Color(0xFF0B3ACD),
                                  Color(0xFF2563EB),
                                  Color(0xFFDC2626),
                                ],
                                strokeCap: StrokeCap.round,
                                strokeJoin: StrokeJoin.round,
                              ),
                            ]),
                          MarkerLayer(markers: [
                            if (pickupPoint != null)
                              Marker(
                                point: pickupPoint,
                                width: 88,
                                height: 58,
                                alignment: Alignment.topCenter,
                                child: _mapMarker('Pickup', Icons.trip_origin,
                                    const Color(0xFF16A34A)),
                              ),
                            if (destinationPoint != null)
                              Marker(
                                point: destinationPoint,
                                width: 100,
                                height: 58,
                                alignment: Alignment.topCenter,
                                child: _mapMarker('Destination', Icons.flag,
                                    const Color(0xFFDC2626)),
                              ),
                            if (driverPoint != null)
                              Marker(
                                point: driverPoint,
                                width: 82,
                                height: 58,
                                alignment: Alignment.topCenter,
                                child: _mapMarker(
                                    'Driver',
                                    Icons.local_taxi_rounded,
                                    const Color(0xFF2563EB)),
                              ),
                          ]),
                          RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(mapAttribution),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: FloatingActionButton.small(
                          heroTag: 'recenter-ride-${widget.rideId}',
                          tooltip: 'Fit ride locations',
                          onPressed: _recenterMap,
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                    ]),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child:
                      Text('Waiting for the driver to share their location.'),
                ),
              if (location is Map)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Driver location updated ${location['updated_at'] ?? 'just now'}',
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              if (pickup is Map &&
                  (pickup['label'] ?? '').toString().isNotEmpty)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.trip_origin, color: Color(0xFF16A34A)),
                  title: Text(pickup['label'].toString()),
                  subtitle: const Text('Pickup'),
                ),
              if (destination is Map &&
                  (destination['label'] ?? '').toString().isNotEmpty)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag, color: Color(0xFFDC2626)),
                  title: Text(destination['label'].toString()),
                  subtitle: const Text('Destination'),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child:
                        Text(error!, style: const TextStyle(color: Colors.red)),
                  ),
                ),
            ])));
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

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  // Keep the inbox fresh while visible, then resume polling when reopened.
  Timer? refreshTimer;
  List<Map<String, dynamic>> notifications = [];
  bool loading = true;
  bool requestActive = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    _startRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefresh();
      load(showLoading: false);
    } else {
      refreshTimer?.cancel();
      refreshTimer = null;
    }
  }

  void _startRefresh() {
    refreshTimer?.cancel();
    refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      load(showLoading: false);
    });
  }

  Future<void> load({bool showLoading = true}) async {
    if (requestActive) return;
    requestActive = true;
    if (showLoading && mounted) setState(() => loading = true);
    try {
      final token = await Session.token();
      if (token == null) throw Exception('Please sign in again.');
      final data = await Api.request('GET', '/my-notifications', token: token);
      final items = notificationItems(data);
      if (!mounted) return;
      setState(() {
        notifications = items;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      requestActive = false;
      if (mounted && showLoading) setState(() => loading = false);
    }
  }

  Future<void> markRead(Map<String, dynamic> notification) async {
    if (_asBool(notification['is_read'])) return;
    final token = await Session.token();
    if (token == null) return;
    try {
      await Api.request('PUT', '/my-notifications/${notification['id']}/read',
          token: token);
      if (!mounted) return;
      setState(() => notification['is_read'] = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: loading && notifications.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: error != null && notifications.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 150),
                        Center(child: Text(error!)),
                        Center(
                            child: TextButton(
                                onPressed: load,
                                child: const Text('Try again'))),
                      ])
                    : notifications.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 170),
                            Center(
                                child:
                                    Icon(Icons.notifications_none, size: 42)),
                            SizedBox(height: 12),
                            Center(child: Text('You are all caught up')),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: notifications.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = notifications[index];
                              final unread = !_asBool(item['is_read']);
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  side: BorderSide(
                                    color: unread
                                        ? const Color(0xFFBFDBFE)
                                        : const Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: ListTile(
                                  onTap: () => markRead(item),
                                  leading: Icon(
                                    unread
                                        ? Icons.mark_email_unread_outlined
                                        : Icons.drafts_outlined,
                                    color: unread
                                        ? const Color(0xFF2563EB)
                                        : const Color(0xFF6B7280),
                                  ),
                                  title: Text(
                                    item['title']?.toString() ?? 'Ride update',
                                    style: TextStyle(
                                      fontWeight: unread
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  subtitle:
                                      Text(item['message']?.toString() ?? ''),
                                  trailing: unread
                                      ? const Icon(Icons.circle,
                                          size: 10, color: Color(0xFF2563EB))
                                      : null,
                                ),
                              );
                            },
                          ),
              ),
      );
}

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool embedded;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onAuthSuccess;

  const ProfilePage({
    super.key,
    required this.user,
    this.embedded = false,
    this.onLogout,
    this.onAuthSuccess,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<Map<String, dynamic>> profile = _loadProfile();

  bool _isRegister = false;
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();
  final _regName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPhone = TextEditingController();
  final _regPassword = TextEditingController();
  bool _authLoading = false;
  String? _authError;

  // App Settings state (persistent via SharedPreferences)
  String _language = 'English';
  String _currency = 'USD (\$)';
  String _themeMode = 'System Default';
  bool _pushNotifications = true;
  bool _soundVibration = true;
  bool _promoOffers = false;
  String _defaultPayment = 'Cash';
  bool _biometricEnabled = true;
  String _homeAddress = 'Russian Market (Toul Tom Poung)';
  String _workAddress = 'Vattanac Capital Tower, Phnom Penh';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _language = prefs.getString('pref_lang') ?? 'English';
        _currency = prefs.getString('pref_curr') ?? 'USD (\$)';
        _themeMode = prefs.getString('pref_theme') ?? 'System Default';
        _pushNotifications = prefs.getBool('pref_push') ?? true;
        _soundVibration = prefs.getBool('pref_sound') ?? true;
        _promoOffers = prefs.getBool('pref_promos') ?? false;
        _defaultPayment = prefs.getString('pref_payment') ?? 'Cash';
        _biometricEnabled = prefs.getBool('pref_biometric') ?? true;
        _homeAddress =
            prefs.getString('pref_home') ?? 'Russian Market (Toul Tom Poung)';
        _workAddress = prefs.getString('pref_work') ??
            'Vattanac Capital Tower, Phnom Penh';
      });
    }
  }

  Future<void> _setPref<T>(String key, T value, void Function() update) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) await prefs.setString(key, value);
    if (value is bool) await prefs.setBool(key, value);
    if (mounted) setState(update);
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      profile = _loadProfile();
    }
  }

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPassword.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regPhone.dispose();
    _regPassword.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final token = await Session.token();
    if (token == null) return widget.user;
    try {
      final result = await Api.request('GET', '/profile', token: token);
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return widget.user;
    }
  }

  Future<void> _handleLogin() async {
    final emailText = _loginEmail.text.trim();
    final passText = _loginPassword.text;
    if (emailText.isEmpty || passText.isEmpty) {
      setState(() => _authError = 'Please enter both email and password.');
      return;
    }
    setState(() {
      _authLoading = true;
      _authError = null;
    });
    try {
      final result = await Api.request(
        'POST',
        '/login',
        body: {'email': emailText, 'password': passText},
      );
      final user = Map<String, dynamic>.from(result['user']);
      final token = result['token'].toString();
      await Session.save(user, token);
      unawaited(PushNotifications.registerDevice());
      if (!mounted) return;
      if (user['role'] == 'driver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DriverHomePage(user: user, onLogout: _signOut),
          ),
        );
      } else {
        await widget.onAuthSuccess?.call();
        setState(() {
          profile = _loadProfile();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _authError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    final nameText = _regName.text.trim();
    final emailText = _regEmail.text.trim();
    final phoneText = _regPhone.text.trim();
    final passText = _regPassword.text;
    if (nameText.isEmpty || emailText.isEmpty || passText.isEmpty) {
      setState(() => _authError = 'Name, email and password are required.');
      return;
    }
    if (passText.length < 8) {
      setState(
          () => _authError = 'Choose a password with at least 8 characters.');
      return;
    }
    setState(() {
      _authLoading = true;
      _authError = null;
    });
    try {
      final data = await Api.request(
        'POST',
        '/register',
        body: {
          'name': nameText,
          'email': emailText,
          'phone': phoneText,
          'password': passText,
        },
      );
      final user = Map<String, dynamic>.from(data['user']);
      final token = data['token'].toString();
      await Session.save(user, token);
      unawaited(PushNotifications.registerDevice());
      if (!mounted) return;
      await widget.onAuthSuccess?.call();
      setState(() {
        profile = _loadProfile();
      });
    } catch (e) {
      if (mounted) {
        setState(
            () => _authError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  void _fillQuickDemo(String email, String pass) {
    setState(() {
      _isRegister = false;
      _loginEmail.text = email;
      _loginPassword.text = pass;
      _authError = null;
    });
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
    return notificationItems(data).take(5).toList();
  }

  Future<void> _showLanguageDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Select Language'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'English'),
            child: Row(
              children: [
                const Text('🇺🇸', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                const Expanded(
                    child:
                        Text('English (US)', style: TextStyle(fontSize: 16))),
                if (_language == 'English')
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'ភាសាខ្មែរ (Khmer)'),
            child: Row(
              children: [
                const Text('🇰🇭', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('ភាសាខ្មែរ (Khmer)',
                        style: TextStyle(fontSize: 16))),
                if (_language.contains('ខ្មែរ'))
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      await _setPref('pref_lang', selected, () => _language = selected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Language set to $selected')),
        );
      }
    }
  }

  Future<void> _showCurrencyDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Default Currency Display'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'USD (\$)'),
            child: Row(
              children: [
                const Text('\$',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A))),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('US Dollar (USD - \$)',
                        style: TextStyle(fontSize: 15))),
                if (_currency.startsWith('USD'))
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'KHR (៛)'),
            child: Row(
              children: [
                const Text('៛',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0B3ACD))),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Khmer Riel (KHR - ៛)',
                        style: TextStyle(fontSize: 15))),
                if (_currency.startsWith('KHR'))
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      await _setPref('pref_curr', selected, () => _currency = selected);
    }
  }

  Future<void> _showThemeDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('App Appearance'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'System Default'),
            child: Row(
              children: [
                const Icon(Icons.brightness_auto, size: 20),
                const SizedBox(width: 12),
                const Expanded(child: Text('System Default')),
                if (_themeMode == 'System Default')
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'Light Mode'),
            child: Row(
              children: [
                const Icon(Icons.light_mode, size: 20, color: Colors.amber),
                const SizedBox(width: 12),
                const Expanded(child: Text('Light Mode')),
                if (_themeMode == 'Light Mode')
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'Dark Mode'),
            child: Row(
              children: [
                const Icon(Icons.dark_mode, size: 20, color: Colors.indigo),
                const SizedBox(width: 12),
                const Expanded(child: Text('Dark Mode')),
                if (_themeMode == 'Dark Mode')
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      await _setPref('pref_theme', selected, () => _themeMode = selected);
    }
  }

  Future<void> _showPaymentMethodDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Default Payment Method'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'Cash on Arrival'),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, color: Color(0xFF16A34A)),
                const SizedBox(width: 12),
                const Expanded(child: Text('Cash on Arrival')),
                if (_defaultPayment.contains('Cash'))
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogCtx, 'Bakong KHQR (ABA, Wing, etc.)'),
            child: Row(
              children: [
                const Icon(Icons.qr_code_2, color: Color(0xFF0B3ACD)),
                const SizedBox(width: 12),
                const Expanded(child: Text('Bakong KHQR (ABA, Wing, ACLEDA)')),
                if (_defaultPayment.contains('Bakong') ||
                    _defaultPayment.contains('KHQR'))
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, 'Credit / Debit Card'),
            child: Row(
              children: [
                const Icon(Icons.credit_card, color: Color(0xFF264399)),
                const SizedBox(width: 12),
                const Expanded(child: Text('Credit / Debit Card')),
                if (_defaultPayment.contains('Card'))
                  const Icon(Icons.check, color: Color(0xFF0B3ACD)),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      await _setPref(
          'pref_payment', selected, () => _defaultPayment = selected);
    }
  }

  Future<void> _editSavedPlace(String label, String currentVal) async {
    final controller = TextEditingController(text: currentVal);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Edit $label Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: '$label Address or Landmark',
                prefixIcon: Icon(
                    label == 'Home' ? Icons.home_outlined : Icons.work_outline),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Quick Landmark Shortcuts:',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('Central Market',
                      style: TextStyle(fontSize: 11)),
                  onPressed: () =>
                      controller.text = 'Central Market (Phsar Thmey)',
                ),
                ActionChip(
                  label:
                      const Text('Aeon Mall 1', style: TextStyle(fontSize: 11)),
                  onPressed: () =>
                      controller.text = 'Aeon Mall 1 (Samdach Sothearos)',
                ),
                ActionChip(
                  label: const Text('Russian Market',
                      style: TextStyle(fontSize: 11)),
                  onPressed: () =>
                      controller.text = 'Russian Market (Toul Tom Poung)',
                ),
                ActionChip(
                  label: const Text('Vattanac Tower',
                      style: TextStyle(fontSize: 11)),
                  onPressed: () =>
                      controller.text = 'Vattanac Capital Tower, Phnom Penh',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Save Place')),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final newVal = controller.text.trim();
      if (label == 'Home') {
        await _setPref('pref_home', newVal, () => _homeAddress = newVal);
      } else {
        await _setPref('pref_work', newVal, () => _workAddress = newVal);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label location updated to $newVal')),
        );
      }
    }
    controller.dispose();
  }

  Future<void> _showChangePasswordDialog() async {
    final oldPass = TextEditingController();
    final newPass = TextEditingController();
    final confirmPass = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: oldPass,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current Password'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter current password' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: newPass,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'New Password (min 8 chars)'),
                validator: (v) =>
                    (v == null || v.length < 8) ? 'Minimum 8 characters' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: confirmPass,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm New Password'),
                validator: (v) =>
                    v != newPass.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Password updated successfully!')),
                );
              }
            },
            child: const Text('Update Password'),
          ),
        ],
      ),
    );
    oldPass.dispose();
    newPass.dispose();
    confirmPass.dispose();
  }

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Safety & Emergency SOS'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If you feel unsafe or need immediate emergency assistance in Cambodia, dial directly:',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Color(0xFFFEE2E2),
                child: Icon(Icons.local_police, color: Color(0xFFDC2626)),
              ),
              title: Text('National Police Hotlines',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Dial 117 (Toll-Free in Cambodia)'),
              trailing: Chip(label: Text('117')),
            ),
            Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Color(0xFFFEE2E2),
                child: Icon(Icons.medical_services_outlined,
                    color: Color(0xFFDC2626)),
              ),
              title: Text('Emergency Ambulance',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Dial 119 (Medical Emergency)'),
              trailing: Chip(label: Text('119')),
            ),
            Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Color(0xFFE0E7FF),
                child: Icon(Icons.shield_outlined, color: Color(0xFF0B3ACD)),
              ),
              title: Text('RideApp Safety Center',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('24/7 Incident Hotline: +855 23 999 888'),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showHelpCenterDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.headset_mic_outlined, color: Color(0xFF0B3ACD)),
            SizedBox(width: 8),
            Text('24/7 Help & Support'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Need assistance with a past ride, payment, or app feature?',
                style: TextStyle(fontSize: 13)),
            SizedBox(height: 14),
            Text('📞 Hotline: +855 23 999 888 (24/7 Support)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('✉️ Email: support@rideapp.com',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('📍 Office: Vattanac Capital Tower, Level 18, Phnom Penh',
                style: TextStyle(color: Color(0xFF6B7280))),
            SizedBox(height: 14),
            Text('Frequently Asked Questions:',
                style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text(
                '• How does Bakong KHQR work? Scan the QR with any Cambodian banking app (ABA, Wing, ACLEDA) to verify instantly.'),
            SizedBox(height: 4),
            Text(
                '• What if I forget an item? Contact support or message the driver from the trip history receipt.'),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _showLegalDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Terms of Service & Privacy Policy'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Passenger Service Terms',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              SizedBox(height: 6),
              Text(
                'RideApp connects passengers with independent licensed drivers across Phnom Penh. Fares are calculated according to official platform distance and vehicle matrices. Drivers must adhere to standard safety rules.',
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: Color(0xFF4B5563)),
              ),
              SizedBox(height: 14),
              Text('Data Privacy Standard',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              SizedBox(height: 6),
              Text(
                'Your GPS location is only shared during an active trip with the assigned driver. Personal contact details are protected and encrypted. We never sell your personal data.',
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: Color(0xFF4B5563)),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('I Understand')),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.local_taxi, color: Color(0xFF0B3ACD)),
            SizedBox(width: 8),
            Text('About RideApp'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RideApp Cambodia',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('Version 2.4.0 (Build 2026)',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
            SizedBox(height: 12),
            Text(
              'Modern cross-platform ride hailing engine featuring multi-vehicle upfront distance calculations, live admin fleet dispatch, and Bakong KHQR instant payments.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text('© 2026 RideApp Inc. All rights reserved.',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _clearCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 18),
            SizedBox(width: 8),
            Text('Temporary app cache cleared (14.2 MB freed).'),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text(
            'Are you sure you want to sign out of your RideApp account?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && widget.onLogout != null) {
      await widget.onLogout!();
      if (mounted) setState(() => profile = Future.value({}));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Delete Account?'),
          ],
        ),
        content: const Text(
          'This action is irreversible. All your trip history, saved addresses, and payment records will be permanently erased.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete My Account'),
          ),
        ],
      ),
    );
    if (confirmed == true && widget.onLogout != null) {
      await widget.onLogout!();
      if (mounted) {
        setState(() => profile = Future.value({}));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')),
        );
      }
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF0B3ACD)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );

  Widget _buildSettingClickTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDestructive
                  ? const Color(0xFFFCA5A5)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: ListTile(
            onTap: onTap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDestructive
                    ? const Color(0xFFFEE2E2)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 18,
                  color: isDestructive
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF0B3ACD)),
            ),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDestructive
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF1E293B),
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            trailing: const Icon(Icons.chevron_right,
                size: 18, color: Color(0xFF94A3B8)),
          ),
        ),
      );

  Widget _buildSavedPlaceTile(
          String label, String address, IconData icon, VoidCallback onEdit) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF0B3ACD)),
            ),
            title: Text(label,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            subtitle: Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: Color(0xFF0B3ACD)),
              onPressed: onEdit,
              tooltip: 'Edit $label',
            ),
          ),
        ),
      );

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: SwitchListTile(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF0B3ACD),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<Map<String, dynamic>>(
      future: profile,
      builder: (context, snapshot) {
        final user = snapshot.data ?? widget.user;
        final hasSession = user['id'] != null ||
            (user['email'] != null && user['email'].toString().isNotEmpty);

        if (!hasSession) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF212633),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B3ACD),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.person_pin_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome to RideApp',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Sign in or register to book rides and track trips.',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Sign In'),
                    icon: Icon(Icons.login),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Create Account'),
                    icon: Icon(Icons.person_add_outlined),
                  ),
                ],
                selected: {_isRegister},
                onSelectionChanged: (val) {
                  setState(() {
                    _isRegister = val.first;
                    _authError = null;
                  });
                },
              ),
              const SizedBox(height: 18),
              if (_authError != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFB91C1C), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _authError!,
                          style: const TextStyle(
                              color: Color(0xFFB91C1C), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (!_isRegister) ...[
                TextField(
                  controller: _loginEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _loginPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _authLoading ? null : _handleLogin,
                    child: _authLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Quick Test Accounts',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280)),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.person, size: 16),
                      label: const Text('Passenger: rider.chenda@rideapp.com'),
                      onPressed: () => _fillQuickDemo(
                          'rider.chenda@rideapp.com', 'rider123456'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.local_taxi, size: 16),
                      label: const Text('Driver: driver.sokha@rideapp.com'),
                      onPressed: () => _fillQuickDemo(
                          'driver.sokha@rideapp.com', 'driver123456'),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _regName,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _regEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _regPhone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _regPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password (min 8 chars)',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _authLoading ? null : _handleRegister,
                    child: _authLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Account'),
                  ),
                ),
              ],
            ],
          );
        }

        final displayName = user['name']?.toString() ?? 'Passenger';
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            // PROFILE HERO HEADER CARD
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF212633),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0xFF0B3ACD),
                        foregroundColor: Colors.white,
                        child: Text(
                          displayName.isEmpty
                              ? 'R'
                              : displayName[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              user['email']?.toString() ?? '',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF264399),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    user['role']?.toString() == 'driver'
                                        ? 'Driver'
                                        : 'Passenger',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF16A34A)
                                        .withValues(alpha: 0.2),
                                    border: Border.all(
                                        color: const Color(0xFF16A34A),
                                        width: 0.8),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified,
                                          size: 11, color: Color(0xFF4ADE80)),
                                      SizedBox(width: 3),
                                      Text(
                                        'Verified',
                                        style: TextStyle(
                                            color: Color(0xFF4ADE80),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit profile',
                        onPressed:
                            snapshot.connectionState == ConnectionState.waiting
                                ? null
                                : () => _editProfile(user),
                        icon: const Icon(Icons.edit_outlined,
                            color: Colors.white),
                      ),
                    ],
                  ),
                  if (user['phone']?.toString().isNotEmpty == true) ...[
                    const SizedBox(height: 14),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined,
                            size: 14, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text(
                          user['phone'].toString(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // SECTION 1: SAVED PLACES
            _buildSectionHeader('Saved Places', Icons.bookmark_border),
            _buildSavedPlaceTile('Home', _homeAddress, Icons.home_outlined,
                () => _editSavedPlace('Home', _homeAddress)),
            _buildSavedPlaceTile('Work', _workAddress, Icons.work_outline,
                () => _editSavedPlace('Work', _workAddress)),
            const SizedBox(height: 16),

            // SECTION 2: APP PREFERENCES
            _buildSectionHeader('App Preferences', Icons.tune),
            _buildSettingClickTile('Language', _language,
                Icons.language_outlined, _showLanguageDialog),
            _buildSettingClickTile('Currency Display', _currency,
                Icons.attach_money_outlined, _showCurrencyDialog),
            _buildSettingClickTile('App Appearance', _themeMode,
                Icons.dark_mode_outlined, _showThemeDialog),
            const SizedBox(height: 16),

            // SECTION 3: NOTIFICATIONS & SOUNDS
            _buildSectionHeader(
                'Notifications & Sounds', Icons.notifications_none),
            _buildSwitchTile(
                'Push Notifications',
                'Real-time ride status and driver arrival',
                _pushNotifications,
                (v) => _setPref('pref_push', v, () => _pushNotifications = v)),
            _buildSwitchTile(
                'Sound & Vibration Alerts',
                'Chime when driver accepts or arrives',
                _soundVibration,
                (v) => _setPref('pref_sound', v, () => _soundVibration = v)),
            _buildSwitchTile(
                'Promotional Offers & News',
                'Exclusive discount codes and weekend deals',
                _promoOffers,
                (v) => _setPref('pref_promos', v, () => _promoOffers = v)),
            const SizedBox(height: 16),

            // SECTION 4: PAYMENT & SECURITY
            _buildSectionHeader('Payment & Security', Icons.security_outlined),
            _buildSettingClickTile('Default Payment Method', _defaultPayment,
                Icons.credit_card_outlined, _showPaymentMethodDialog),
            _buildSettingClickTile('Change Password', 'Update account password',
                Icons.lock_outline, _showChangePasswordDialog),
            _buildSwitchTile(
                'Biometric / Face ID Login',
                'Fast secure sign in with fingerprint or Face ID',
                _biometricEnabled,
                (v) =>
                    _setPref('pref_biometric', v, () => _biometricEnabled = v)),
            const SizedBox(height: 16),

            // SECTION 5: SAFETY & EMERGENCY
            _buildSectionHeader(
                'Safety & Support', Icons.health_and_safety_outlined),
            _buildSettingClickTile(
                'Emergency SOS Assistance',
                'Police (117) · Ambulance (119)',
                Icons.emergency_outlined,
                _showEmergencyDialog,
                isDestructive: true),
            _buildSettingClickTile(
                '24/7 Help Center & Hotline',
                '+855 23 999 888',
                Icons.headset_mic_outlined,
                _showHelpCenterDialog),
            _buildSettingClickTile(
                'Terms of Service & Privacy',
                'Read passenger rights and policies',
                Icons.description_outlined,
                _showLegalDialog),
            _buildSettingClickTile(
                'About RideApp',
                'Version 2.4.0 (Build 2026)',
                Icons.info_outline,
                _showAboutDialog),
            const SizedBox(height: 16),

            // SECTION 6: RECENT NOTIFICATIONS
            _buildSectionHeader(
                'Recent Notifications', Icons.mark_chat_unread_outlined),
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
                  if (notifications.data == null ||
                      notifications.data!.isEmpty) {
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
            const SizedBox(height: 16),

            // SECTION 7: ACCOUNT ACTIONS
            _buildSectionHeader(
                'Account Actions', Icons.manage_accounts_outlined),
            _buildSettingClickTile(
                'Clear Temporary Cache',
                'Free up cached map tiles (14.2 MB)',
                Icons.cleaning_services_outlined,
                _clearCache),
            const SizedBox(height: 12),
            if (widget.onLogout != null) ...[
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _confirmLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextButton.icon(
              onPressed: _confirmDeleteAccount,
              icon: const Icon(Icons.delete_forever_outlined,
                  color: Color(0xFFDC2626), size: 18),
              label: const Text('Delete Account',
                  style: TextStyle(
                      color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 24),
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
