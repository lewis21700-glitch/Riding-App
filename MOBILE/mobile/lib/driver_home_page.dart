import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'main.dart' show Api, NotificationBell, Session, formatFare;

class DriverHomePage extends StatefulWidget {
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  const DriverHomePage({super.key, required this.user, required this.onLogout});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage>
    with WidgetsBindingObserver {
  String availability = 'offline';
  Map<String, dynamic>? vehicle;
  List<Map<String, dynamic>> rides = [];
  bool loading = true;
  bool updating = false;
  String? error;
  StreamSubscription<Position>? locationSubscription;
  Timer? rideRefreshTimer;
  bool requestActive = false;
  bool locationRequestActive = false;
  bool locationPermissionBlocked = false;
  int? locationRideId;
  int locationGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    availability =
        _normalizeAvailability(widget.user['availability']?.toString());
    load();
    _startRideRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      locationPermissionBlocked = false;
      _startRideRefresh();
      load(showLoading: false);
    } else {
      rideRefreshTimer?.cancel();
      rideRefreshTimer = null;
    }
  }

  void _startRideRefresh() {
    rideRefreshTimer?.cancel();
    rideRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!loading && !requestActive) load(showLoading: false);
    });
  }

  String _normalizeAvailability(String? value) => switch (value) {
        'online' || 'available' => 'available',
        'busy' || 'on_ride' => 'on_ride',
        _ => 'offline',
      };

  Future<String?> get _token => Session.token();

  Future<void> load({bool showLoading = true}) async {
    if (requestActive) return;
    requestActive = true;
    if (showLoading && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final token = await _token;
      if (token == null) throw Exception('Please sign in again.');
      final results = await Future.wait([
        Api.request('GET', '/profile', token: token),
        Api.request('GET', '/my-vehicle', token: token),
        Api.request('GET', '/driver-rides', token: token),
      ]);
      final profile = Map<String, dynamic>.from(results[0] as Map);
      final vehicleData = results[1];
      final rideData = results[2];
      if (!mounted) return;
      setState(() {
        availability =
            _normalizeAvailability(profile['availability']?.toString());
        error = null;
        vehicle =
            vehicleData is Map ? Map<String, dynamic>.from(vehicleData) : null;
        rides = rideData is List
            ? rideData.map((item) => Map<String, dynamic>.from(item)).toList()
            : [];
        if (showLoading) loading = false;
      });
      unawaited(_syncLocationStream());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = _friendly(e);
        if (showLoading) loading = false;
      });
    } finally {
      requestActive = false;
    }
  }

  String _friendly(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> setAvailability(bool online) async {
    if (online && vehicle == null) {
      _message('Register your vehicle before going online.');
      await editVehicle();
      return;
    }
    final token = await _token;
    if (token == null) return;
    setState(() => updating = true);
    try {
      await Api.request('PUT', '/drivers/${widget.user['id']}/availability',
          body: {'availability': online ? 'online' : 'offline'}, token: token);
      if (!mounted) return;
      setState(() => availability = online ? 'available' : 'offline');
      unawaited(_syncLocationStream());
    } catch (e) {
      _message(_friendly(e));
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  Future<void> editVehicle() async {
    final type = TextEditingController(
        text: vehicle?['vehicle_type']?.toString() ?? 'Car');
    final model = TextEditingController(
        text: vehicle?['vehicle_model']?.toString() ?? '');
    final plate =
        TextEditingController(text: vehicle?['plate_number']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(vehicle == null ? 'Register your vehicle' : 'Update vehicle'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: type,
                  decoration: const InputDecoration(labelText: 'Vehicle type'),
                  validator: _required),
              const SizedBox(height: 10),
              TextFormField(
                  controller: model,
                  decoration:
                      const InputDecoration(labelText: 'Make and model'),
                  validator: _required),
              const SizedBox(height: 10),
              TextFormField(
                  controller: plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Plate number'),
                  validator: _required),
            ]),
          ),
        ),
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
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && mounted) {
      final token = await _token;
      if (token == null) return;
      try {
        await Api.request('POST', '/my-vehicle', token: token, body: {
          'vehicle_type': type.text.trim(),
          'vehicle_model': model.text.trim(),
          'plate_number': plate.text.trim().toUpperCase(),
        });
        await load();
        _message('Vehicle information saved.');
      } catch (e) {
        _message(_friendly(e));
      }
    }
    type.dispose();
    model.dispose();
    plate.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  Future<void> updateRide(Map<String, dynamic> ride, String status) async {
    final token = await _token;
    if (!mounted) return;
    if (token == null) return;
    double? finalDistanceKm;
    if (status == 'completed' && (ride['destination'] ?? '').toString().trim().isEmpty) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Record trip distance'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                suffixText: ' km', labelText: 'Completed distance'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Complete ride')),
          ],
        ),
      );
      finalDistanceKm = double.tryParse(controller.text.trim());
      controller.dispose();
      if (confirmed != true || finalDistanceKm == null || finalDistanceKm <= 0) {
        if (confirmed == true) _message('Enter a valid trip distance.');
        return;
      }
    }
    try {
      await Api.request('PUT', '/driver-rides/${ride['id']}',
          token: token,
          body: {
            'status': status,
            if (finalDistanceKm != null) 'final_distance_km': finalDistanceKm
          });
      await load();
    } catch (e) {
      _message(_friendly(e));
    }
  }

  Future<void> collectCash(Map<String, dynamic> ride) async {
    final token = await _token;
    if (!mounted || token == null) return;
    try {
      await Api.request('POST', '/payments',
          token: token,
          body: {
            'ride_id': ride['id'],
            'payment_method': 'cash',
          });
      _message('Cash payment collected & confirmed.');
      await load();
    } catch (e) {
      _message(_friendly(e));
    }
  }

  Future<void> _syncLocationStream() async {
    final activeRides = rides.where((ride) => ['accepted', 'arrived', 'ongoing'].contains(ride['status']));
    final active = activeRides.isEmpty ? null : activeRides.first;
    final sharingTrip = active != null && availability == 'on_ride';
    final sharingAvailability = active == null && availability == 'available';
    if (!sharingTrip && !sharingAvailability) {
      await _stopLocationStream();
      return;
    }
    final int? rideId = sharingTrip ? active['id'] as int : null;
    if (locationRideId == rideId && locationSubscription != null) return;
    if (locationPermissionBlocked) return;

    final generation = ++locationGeneration;
    final previousSubscription = locationSubscription;
    locationSubscription = null;
    locationRideId = rideId;
    await previousSubscription?.cancel();
    if (!await Geolocator.isLocationServiceEnabled()) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted || generation != locationGeneration) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      locationPermissionBlocked = true;
      if (mounted) {
        _message(
            'Allow location access to share your trip with the passenger.');
      }
      return;
    }
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 10),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'RideApp location sharing',
              notificationText: 'Location is shared while you are online or on a trip.',
              notificationChannelName: 'RideApp location sharing',
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            timeLimit: Duration(minutes: 2),
          );
    locationSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) => unawaited(_sendLocation(rideId, position)),
      onError: (Object _) {
        locationSubscription = null;
      },
    );
  }

  Future<void> _stopLocationStream() async {
    locationGeneration++;
    locationRideId = null;
    final subscription = locationSubscription;
    locationSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _sendLocation(int? rideId, Position position) async {
    if (locationRequestActive) return;
    locationRequestActive = true;
    try {
      if (locationRideId != rideId) return;
      final token = await _token;
      if (token == null) return;
      final rideQuery = rideId == null ? '' : '?ride_id=$rideId';
      await Api.request('POST', '/driver-location$rideQuery',
          token: token,
          body: {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'heading': position.heading,
          });
    } catch (_) {
      // Location sharing retries on the next foreground update.
    } finally {
      locationRequestActive = false;
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rideRefreshTimer?.cancel();
    unawaited(_stopLocationStream());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = rides
        .where((ride) =>
            ride['status'] == 'requested' && ride['driver_id'] == null)
        .toList();
    final assigned = rides
        .where((ride) => ['accepted', 'arrived', 'ongoing'].contains(ride['status']))
        .toList();
    final completed = rides
        .where((ride) => ride['status'] == 'completed')
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver center',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          const NotificationBell(),
          IconButton(
              tooltip: 'Refresh',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: 'Sign out',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: const Color(0xFF212633),
                  borderRadius: BorderRadius.circular(22)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DRIVER ACCOUNT',
                        style: TextStyle(
                            color: Colors.white70,
                            letterSpacing: 1.2,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('Hello, ${widget.user['name'] ?? 'Driver'}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Icon(
                          availability == 'available'
                              ? Icons.circle
                              : Icons.circle_outlined,
                          color: availability == 'available'
                              ? const Color(0xFF4ADE80)
                              : Colors.white70,
                          size: 13),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              availability == 'available'
                                  ? 'You are online and can receive rides'
                                  : availability == 'on_ride'
                                      ? 'You are on an active ride'
                                      : 'You are offline',
                              style: const TextStyle(color: Colors.white))),
                      if (availability != 'on_ride')
                        Switch(
                            value: availability == 'available',
                            onChanged: updating ? null : setAvailability,
                            activeThumbColor: const Color(0xFF4ADE80)),
                    ]),
                  ]),
            ),
            const SizedBox(height: 18),
            Row(children: [
              const Expanded(
                  child: Text('Your vehicle',
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800))),
              TextButton.icon(
                  onPressed: editVehicle,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(vehicle == null ? 'Add vehicle' : 'Edit')),
            ]),
            Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                    side: const BorderSide(color: Color(0xFFE5E7EB))),
                child: ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.directions_car_outlined)),
                    title: Text(
                        vehicle == null
                            ? 'No vehicle registered'
                            : '${vehicle!['vehicle_type']} · ${vehicle!['vehicle_model']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(vehicle?['plate_number']?.toString() ??
                        'Add your vehicle details to go online.'))),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(
                  child: Text('Your active rides',
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800))),
              if (assigned.isNotEmpty) _CountPill(count: assigned.length),
            ]),
            if (assigned.isEmpty)
              const _EmptyCard(
                  icon: Icons.route_outlined,
                  title: 'No active rides',
                  text: 'Accepted rides will appear here.'),
            ...assigned.map(
                (ride) => _RideCard(ride: ride, actions: _activeActions(ride))),
            if (completed.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Completed rides',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ...completed.map((ride) {
                final isPaid = ride['paid'] == true ||
                    ride['paid'] == 1 ||
                    ride['payment_status'] == 'paid';
                return _RideCard(
                  ride: ride,
                  actions: [
                    if (!isPaid)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => collectCash(ride),
                        icon: const Icon(Icons.attach_money, size: 18),
                        label: const Text('Collect Cash'),
                      )
                    else
                      const Chip(
                        avatar: Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
                        label: Text('Paid', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                        backgroundColor: Color(0xFFDCFCE7),
                        side: BorderSide.none,
                      ),
                    if (ride['rated'] == true || ride['rated'] == 1)
                      const Chip(label: Text('Passenger rated'))
                    else
                      OutlinedButton.icon(
                        onPressed: () => ratePassenger(ride),
                        icon: const Icon(Icons.star_outline),
                        label: const Text('Rate passenger'),
                      ),
                  ],
                );
              }),
            ],
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(
                  child: Text('Ride requests',
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800))),
              _CountPill(count: pending.length),
            ]),
            if (loading)
              const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator())),
            if (!loading && error != null)
              _EmptyCard(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load rides',
                  text: error!,
                  action: TextButton(
                      onPressed: load, child: const Text('Try again'))),
            if (!loading && error == null && pending.isEmpty)
              const _EmptyCard(
                  icon: Icons.notifications_none,
                  title: 'All caught up',
                  text: 'New ride requests will show up here.'),
            ...pending.map((ride) => _RideCard(ride: ride, actions: [
                  OutlinedButton(
                      onPressed: () => updateRide(ride, 'rejected'),
                      child: const Text('Decline')),
                  FilledButton.icon(
                      onPressed: () => updateRide(ride, 'accepted'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Accept')),
                ])),
          ],
        ),
      ),
    );
  }

  List<Widget> _activeActions(Map<String, dynamic> ride) =>
      switch (ride['status']) {
        'accepted' => [
            if ((ride['rider_phone'] ?? '').toString().isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _message('Passenger phone: ${ride['rider_phone']}'),
                icon: const Icon(Icons.phone, size: 16),
                label: const Text('Call'),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0B3ACD),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => updateRide(ride, 'arrived'),
              icon: const Icon(Icons.pin_drop, size: 18),
              label: const Text('Arrived at Pickup'),
            ),
          ],
        'arrived' => [
            if ((ride['rider_phone'] ?? '').toString().isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _message('Passenger phone: ${ride['rider_phone']}'),
                icon: const Icon(Icons.phone, size: 16),
                label: const Text('Call'),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => updateRide(ride, 'ongoing'),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Start Trip'),
            ),
          ],
        'ongoing' => [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF264399),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => updateRide(ride, 'completed'),
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text('Complete Trip'),
            ),
          ],
        _ => [],
      };

  Future<void> ratePassenger(Map<String, dynamic> ride) async {
    var score = 5;
    final comment = TextEditingController();
    final selectedScore = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setScore) => AlertDialog(
          title: const Text('Rate your passenger'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) => IconButton(
                  onPressed: () => setScore(() => score = index + 1),
                  color: const Color(0xFFF59E0B),
                  icon: Icon(index < score ? Icons.star : Icons.star_border),
                ),
              ),
            ),
            TextField(
              controller: comment,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Comment (optional)'),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, score),
              child: const Text('Submit rating'),
            ),
          ],
        ),
      ),
    );
    if (selectedScore != null) {
      try {
        final token = await _token;
        if (token == null) throw Exception('Please sign in again.');
        await Api.request('POST', '/ratings', token: token, body: {
          'ride_id': ride['id'],
          'score': selectedScore,
          'comment': comment.text.trim(),
        });
        if (mounted) _message('Passenger rating saved.');
        await load(showLoading: false);
      } catch (e) {
        if (mounted) _message(_friendly(e));
      }
    }
    comment.dispose();
  }
}

class _RideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final List<Widget> actions;
  const _RideCard({required this.ride, required this.actions});

  Widget _buildStepIndicator(String status) {
    final steps = [
      {'key': 'accepted', 'label': 'On the Way'},
      {'key': 'arrived', 'label': 'Arrived'},
      {'key': 'ongoing', 'label': 'In Trip'},
      {'key': 'completed', 'label': 'Finished'},
    ];
    final int currentStep = switch (status) {
      'accepted' => 0,
      'arrived' => 1,
      'ongoing' => 2,
      'completed' => 3,
      _ => -1,
    };
    if (currentStep == -1) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(steps.length, (idx) {
          final isPastOrCurrent = idx <= currentStep;
          final isCurrent = idx == currentStep;
          final label = steps[idx]['label']!;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isPastOrCurrent
                              ? (isCurrent ? const Color(0xFF0B3ACD) : const Color(0xFF16A34A))
                              : const Color(0xFFD1D5DB),
                        ),
                        child: Center(
                          child: isPastOrCurrent && !isCurrent
                              ? const Icon(Icons.check, size: 12, color: Colors.white)
                              : Text(
                                  '${idx + 1}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: isCurrent ? const Color(0xFF0B3ACD) : const Color(0xFF6B7280),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                if (idx < steps.length - 1)
                  Container(
                    width: 12,
                    height: 2,
                    color: idx < currentStep ? const Color(0xFF16A34A) : const Color(0xFFD1D5DB),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final (label, color, bg) = switch (status) {
      'requested' => ('New Request', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
      'accepted' => ('Going to Pickup', const Color(0xFF0B3ACD), const Color(0xFFE0E7FF)),
      'arrived' => ('Waiting at Pickup', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      'ongoing' => ('Trip in Progress', const Color(0xFF264399), const Color(0xFFEDE9FE)),
      'completed' => ('Completed', const Color(0xFF4B5563), const Color(0xFFF3F4F6)),
      'cancelled' => ('Cancelled', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
      _ => (status, const Color(0xFF4B5563), const Color(0xFFF3F4F6)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = (ride['status'] ?? '').toString();
    final isNewRequest = status == 'requested';

    return Card(
      elevation: isNewRequest ? 3 : 0,
      margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isNewRequest ? const Color(0xFF0B3ACD) : const Color(0xFFE5E7EB),
          width: isNewRequest ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Ride #${ride['id']}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(status),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (ride['ride_type'] ?? 'Car').toString(),
                    style: const TextStyle(color: Color(0xFF374151), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (!isNewRequest) _buildStepIndicator(status),
            const SizedBox(height: 10),
            _RouteLine(
              icon: Icons.trip_origin,
              text: (ride['pickup_location'] ?? 'Pickup unavailable').toString(),
            ),
            if ((ride['destination'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              _RouteLine(
                icon: Icons.location_on,
                text: ride['destination'].toString(),
              ),
            ],
            const Divider(height: 18),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Passenger: ${ride['rider_name'] ?? 'RideApp passenger'}${(ride['rider_phone'] ?? '').toString().isNotEmpty ? ' (${ride['rider_phone']})' : ''}',
                    style: const TextStyle(color: Color(0xFF374151), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                if (ride['fare'] != null || ride['estimated_fare'] != null)
                  Text(
                    formatFare(ride['fare'] ?? ride['estimated_fare'], ride['currency'] ?? 'KHR'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0B3ACD)),
                  ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions
                    .map((action) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: action,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _RouteLine({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text))
      ]);
}

class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill({required this.count});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(30)),
      child:
          Text('$count', style: const TextStyle(fontWeight: FontWeight.w800)));
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  const _EmptyCard(
      {required this.icon,
      required this.title,
      required this.text,
      this.action});
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(top: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 30, color: const Color(0xFF6B7280)),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6B7280))),
              if (action != null) action!,
            ],
          ),
        ),
      );
}
