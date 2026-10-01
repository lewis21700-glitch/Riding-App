import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'main.dart' show Api, NotificationsPage, Session;

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
  Timer? locationTimer;
  Timer? rideRefreshTimer;
  bool requestActive = false;
  bool locationRequestActive = false;
  int? locationRideId;

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
      _startRideRefresh();
      load(showLoading: false);
    } else {
      rideRefreshTimer?.cancel();
      rideRefreshTimer = null;
      locationTimer?.cancel();
      locationTimer = null;
      locationRideId = null;
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
      _syncLocationTimer();
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
      _syncLocationTimer();
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
    double? finalFare;
    if (status == 'completed' && ride['ride_type'] == 'Direct Ride') {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Set final fare'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                prefixText: '\$', labelText: 'Fare in USD'),
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
      finalFare = double.tryParse(controller.text.trim());
      controller.dispose();
      if (confirmed != true || finalFare == null || finalFare < 0) {
        if (confirmed == true) _message('Enter a valid fare.');
        return;
      }
    }
    try {
      await Api.request('PUT', '/driver-rides/${ride['id']}',
          token: token,
          body: {
            'status': status,
            if (finalFare != null) 'final_fare': finalFare
          });
      await load();
    } catch (e) {
      _message(_friendly(e));
    }
  }

  void _syncLocationTimer() {
    final activeRides = rides.where((ride) => ride['status'] == 'ongoing');
    final active = activeRides.isEmpty ? null : activeRides.first;
    if (active == null || availability != 'on_ride') {
      locationTimer?.cancel();
      locationTimer = null;
      locationRideId = null;
      return;
    }
    final rideId = active['id'] as int;
    if (locationRideId == rideId && locationTimer != null) return;
    locationTimer?.cancel();
    locationRideId = rideId;
    locationTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _sendLocation(rideId));
    _sendLocation(rideId);
  }

  Future<void> _sendLocation(int rideId) async {
    if (locationRequestActive) return;
    locationRequestActive = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final token = await _token;
      if (token == null) return;
      await Api.request('POST', '/driver-location?ride_id=$rideId',
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
    locationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = rides
        .where((ride) =>
            ride['status'] == 'requested' && ride['driver_id'] == null)
        .toList();
    final assigned = rides
        .where((ride) => ['accepted', 'ongoing'].contains(ride['status']))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver center',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Notifications',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage())),
              icon: const Icon(Icons.notifications_outlined)),
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
                  color: const Color(0xFF111827),
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
            FilledButton.icon(
                onPressed: () => updateRide(ride, 'ongoing'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start ride'))
          ],
        'ongoing' => [
            FilledButton.icon(
                onPressed: () => updateRide(ride, 'completed'),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Complete ride'))
          ],
        _ => [],
      };
}

class _RideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final List<Widget> actions;
  const _RideCard({required this.ride, required this.actions});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(top: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: const BorderSide(color: Color(0xFFE5E7EB))),
        child: Padding(
            padding: const EdgeInsets.all(15),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Ride #${ride['id']}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text((ride['ride_type'] ?? 'Car').toString(),
                    style: const TextStyle(color: Color(0xFF6B7280)))
              ]),
              const SizedBox(height: 12),
              _RouteLine(
                  icon: Icons.trip_origin,
                  text: (ride['pickup_location'] ?? 'Pickup unavailable')
                      .toString()),
              if ((ride['destination'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                _RouteLine(
                    icon: Icons.location_on_outlined,
                    text: ride['destination'].toString()),
              ],
              const SizedBox(height: 8),
              Text('Passenger: ${ride['rider_name'] ?? 'RideApp passenger'}',
                  style: const TextStyle(color: Color(0xFF6B7280))),
              if (ride['fare'] != null || ride['estimated_fare'] != null) ...[
                const SizedBox(height: 7),
                Text(
                    'Fare ${ride['fare'] != null ? '· ' : 'estimate · '}\$${double.tryParse((ride['fare'] ?? ride['estimated_fare']).toString())?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions
                        .map((action) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: action))
                        .toList()),
              ],
            ])),
      );
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
