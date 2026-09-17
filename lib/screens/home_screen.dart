import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import '../services/prediction_service.dart';
import '../widgets/manual_search_sheet.dart';

@JS('wildoraPrimeRiskAlarm')
external void _primeRiskAlarm();

@JS('wildoraPlayRiskAlarm')
external void _playRiskAlarm(String risk);

@JS('wildoraStopRiskAlarm')
external void _stopRiskAlarmJs();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ReportItem {
  final String title;
  final String description;
  final String location;
  final String imageDataUrl;
  final DateTime time;
  final String author;

  _ReportItem({
    required this.title,
    required this.description,
    required this.location,
    required this.imageDataUrl,
    required this.time,
    required this.author,
  });

  factory _ReportItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final stamp = data['createdAt'];
    DateTime time = DateTime.now();
    if (stamp is Timestamp) time = stamp.toDate().toLocal();
    return _ReportItem(
      title: data['title']?.toString() ?? 'Wildlife report',
      description: data['description']?.toString() ?? '',
      location: data['location']?.toString() ?? 'Unknown location',
      imageDataUrl: data['imageDataUrl']?.toString() ?? '',
      time: time,
      author: data['author']?.toString() ?? 'Community member',
    );
  }
}


class _HomeScreenState extends State<HomeScreen> {
  // Community feed reset: reports created before this date are no longer
  // shown in the app. New reports continue to be saved and displayed.
  static final DateTime _communityFeedReset = DateTime(2026, 9, 17);

  final MapController map = MapController();
  PredictionResult? result;

  double lat = 11.93;
  double lon = 76.13;
  String place = 'Nagarhole';
  bool loading = false;
  bool tracking = false;
  bool locating = false;
  DateTime? _lastGpsPredictionAt;
  int page = 0;
  int? watchId;
  String username = 'User';
  String email = '';
  String? _errorMessage;
  String _liveRiskState = 'LOW';
  bool _highRiskAlertVisible = false;

  final List<_ReportItem> _reports = [];
  String _selectedReportType = 'Animal sighting';
  final TextEditingController _reportTitle = TextEditingController();
  final TextEditingController _reportDescription = TextEditingController();
  final TextEditingController _reportLocation = TextEditingController();
  String _reportImage = '';
  bool _submittingReport = false;

  final List<Map<String, dynamic>> spots = const [
    {'name': 'Nagarhole', 'lat': 11.93, 'lon': 76.13},
    {'name': 'Bandipur', 'lat': 11.67, 'lon': 76.63},
    {'name': 'Wayanad', 'lat': 11.61, 'lon': 76.13},
    {'name': 'Mudumalai', 'lat': 11.56, 'lon': 76.52},
    {'name': 'Kudremukh', 'lat': 13.15, 'lon': 75.25},
    {'name': 'Kodagu', 'lat': 12.42, 'lon': 75.74},
    {'name': 'BRT Hills', 'lat': 11.98, 'lon': 77.05},
    {'name': 'Anamalai', 'lat': 10.57, 'lon': 76.93},
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadCommunityReports();

    // Start downloading the exact wildlife photos in parallel as soon as
    // the home screen opens. The image proxy returns a small WebP version
    // of the same original photo, avoiding the very large original files.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadWildlifeImages();
    });
  }

  @override
  void dispose() {
    _stopTracking();
    _reportTitle.dispose();
    _reportDescription.dispose();
    _reportLocation.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      username = p.getString('wildora_username') ?? 'User';
      email = p.getString('wildora_email') ?? '';
    });
  }

  Future<void> _checkRisk(
    double a,
    double b,
    String name, {
    int? hour,
    int? minute,
    bool liveTrackingCheck = false,
  }) async {
    if (mounted) {
      setState(() {
        loading = true;
        _errorMessage = null;
        lat = a;
        lon = b;
        place = name;
      });
    }

    final now = DateTime.now();
    final r = await PredictionService.predict(
      a,
      b,
      hour: hour ?? now.hour,
      minute: minute ?? now.minute,
      placeName: name,
    );

    if (!mounted) return;
    setState(() {
      result = r;
      loading = false;
      if (r == null) {
        _errorMessage = 'Prediction could not be loaded. Please try again.';
      }
    });

    if (r == null) return;

    final currentRisk = r.risk.toUpperCase();
    if (currentRisk == 'HIGH' || currentRisk == 'MEDIUM') {
      // Alert whenever the user enters a non-low risk state. During live
      // tracking, do not replay the sound on every 15-second refresh while
      // the risk level remains unchanged. A change LOW->MEDIUM, MEDIUM->HIGH,
      // HIGH->MEDIUM, or LOW->HIGH is a new alert.
      final shouldAlert = !liveTrackingCheck || _liveRiskState != currentRisk;
      if (liveTrackingCheck) _liveRiskState = currentRisk;
      if (shouldAlert) {
        _triggerRiskAlert(name, r);
      }
    } else {
      if (liveTrackingCheck) _liveRiskState = 'LOW';
      _stopRiskAlarm();
    }
  }

  void _stopRiskAlarm() {
    try {
      _stopRiskAlarmJs();
    } catch (_) {
      // The web alarm bridge is best-effort on unsupported platforms.
    }
  }

  Future<void> _triggerRiskAlert(String name, PredictionResult r) async {
    try {
      _playRiskAlarm(r.risk.toUpperCase());
    } catch (_) {
      // The visual warning still works if audio is unavailable.
    }

    if (!mounted || _highRiskAlertVisible) return;
    _highRiskAlertVisible = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: r.riskColor, size: 54),
        title: Text(
          '${r.risk.toUpperCase()}-RISK AREA WARNING',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900, color: r.riskColor),
        ),
        content: Text(
          '$name is currently predicted as ${r.risk.toUpperCase()} risk (${r.probability.toStringAsFixed(0)}%). '
          'Stay alert, avoid approaching wildlife, and move toward a safer area if possible.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.icon(
            onPressed: () {
              _stopRiskAlarm();
              Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.volume_off_rounded),
            label: const Text('I understand — stop horn'),
            style: FilledButton.styleFrom(backgroundColor: r.riskColor),
          ),
        ],
      ),
    );

    _highRiskAlertVisible = false;
  }

  Future<void> _clickMap(TapPosition _, LatLng p) async {
    if (tracking) _stopTracking();
    final a = p.latitude;
    final b = p.longitude;
    setState(() {
      lat = a;
      lon = b;
      place = 'Selected location';
      page = 1;
    });
    await _checkRisk(a, b, 'Selected location');
    if (mounted) map.move(LatLng(a, b), 14);
  }

  void _startTracking() {
    if (tracking) {
      _stopTracking();
      return;
    }

    // Unlock browser audio while this user gesture is active. This lets the
    // horn play later when an asynchronous GPS prediction becomes HIGH.
    try {
      _primeRiskAlarm();
    } catch (_) {}

    setState(() => locating = true);

    void ok(web.GeolocationPosition p) {
      final a = p.coords.latitude.toDouble();
      final b = p.coords.longitude.toDouble();
      if (!mounted) return;
      setState(() {
        lat = a;
        lon = b;
        place = 'My Live Location';
        tracking = true;
        locating = false;
      });
      map.move(LatLng(a, b), 15);

      // Keep the blue marker live, but do not send a prediction request for
      // every tiny GPS movement. A fresh ML prediction is requested at most
      // once every 15 seconds while tracking.
      final now = DateTime.now();
      if (_lastGpsPredictionAt == null || now.difference(_lastGpsPredictionAt!).inSeconds >= 15) {
        _lastGpsPredictionAt = now;
        _checkRisk(a, b, 'My Live Location', liveTrackingCheck: true);
      }
    }

    void err(web.GeolocationPositionError _) {
      if (!mounted) return;
      setState(() {
        locating = false;
        tracking = false;
      });
      _snack('Location access was denied. Allow GPS in Chrome and try again.');
    }

    final options = web.PositionOptions(
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0,
    );

    watchId = web.window.navigator.geolocation.watchPosition(
      ok.toJS,
      err.toJS,
      options,
    );
    setState(() => tracking = true);
  }

  void _stopTracking() {
    if (watchId != null) {
      web.window.navigator.geolocation.clearWatch(watchId!);
      watchId = null;
    }
    _lastGpsPredictionAt = null;
    _liveRiskState = 'LOW';
    _stopRiskAlarm();
    if (mounted) {
      setState(() {
        tracking = false;
        locating = false;
      });
    }
  }

  void _openManualSearch() {
    // Unlock browser audio from the user's tap so a later manual prediction
    // can sound immediately when its result is HIGH risk.
    try {
      _primeRiskAlarm();
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualSearchSheet(
        onSearch: (a, b, name, hour, minute) {
          Navigator.of(context).pop();
          setState(() {
            lat = a;
            lon = b;
            place = name;
            page = 2;
          });
          map.move(LatLng(a, b), 14);
          _checkRisk(a, b, name, hour: hour, minute: minute);
        },
      ),
    );
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s), behavior: SnackBarBehavior.floating),
      );

  Color riskColor(String r) {
    switch (r.toUpperCase()) {
      case 'HIGH':
        return const Color(0xFFC62828);
      case 'MEDIUM':
        return const Color(0xFFEF6C00);
      case 'LOW':
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF607D68);
    }
  }

  String _riskText() => result?.risk.toUpperCase() ?? 'NO RESULT';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      drawer: wide ? null : _drawer(),
      body: Row(
        children: [
          if (wide) _side(),
          Expanded(
            child: Column(
              children: [
                _top(),
                Expanded(child: _content()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _side() => Container(
        width: 250,
        color: const Color(0xFF0B2417),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.forest_rounded, color: Colors.white, size: 32),
                SizedBox(width: 10),
                Text(
                  'WILDORA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 38),
            ...[
              'Dashboard',
              'Wildlife Risk Map',
              'Predict Risk',
              'Reports',
              'Wildlife',
              'Community Reports',
              'Guidelines',
              'Settings',
            ].asMap().entries.map((e) => _nav(e.key, e.value)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Live map • ML risk prediction\nYour selected place is checked by the model.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout, color: Colors.white70),
              label: const Text('Sign out', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );

  Widget _drawer() => Drawer(child: _side());

  Widget _nav(int i, String t) {
    final icons = [
      Icons.dashboard_rounded,
      Icons.map_rounded,
      Icons.analytics_rounded,
      Icons.description_outlined,
      Icons.pets_rounded,
      Icons.groups_outlined,
      Icons.menu_book_outlined,
      Icons.settings_outlined,
    ];
    return ListTile(
      selected: page == i,
      onTap: () {
        Navigator.of(context).maybePop();
        setState(() => page = i);
      },
      selectedTileColor: Colors.white12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icons[i], color: page == i ? Colors.white : Colors.white60),
      title: Text(
        t,
        style: TextStyle(
          color: page == i ? Colors.white : Colors.white70,
          fontWeight: page == i ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _top() => Container(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5EAE4))),
        ),
        child: Row(
          children: [
            if (MediaQuery.sizeOf(context).width < 1000)
              Builder(
                builder: (ctx) => IconButton(
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              ),
            const Text(
              'WILDORA',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E5631),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 12),
            Text(_title(), style: TextStyle(color: Colors.grey.shade600)),
            const Spacer(),
            IconButton(
              tooltip: 'Alerts',
              onPressed: _showAlerts,
              icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF1E5631)),
            ),
            const SizedBox(width: 8),
            _profile(),
          ],
        ),
      );

  String _title() => [
        'Dashboard',
        'Wildlife Risk Map',
        'Predict Risk',
        'Reports',
        'Wildlife',
        'Community Reports',
        'Guidelines',
        'Settings',
      ][page];

  Widget _profile() => PopupMenuButton<String>(
        tooltip: 'Profile',
        onSelected: (v) async {
          if (v == 'logout') await FirebaseAuth.instance.signOut();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(email, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'logout', child: Text('Sign out')),
        ],
        child: CircleAvatar(
          backgroundColor: const Color(0xFF1E5631),
          child: Text(
            username.isEmpty ? 'U' : username[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );

  Widget _content() {
    switch (page) {
      case 1:
        return _mapPage();
      case 2:
        return _predictPage();
      case 3:
        return _reportsPage();
      case 4:
        return _wildlifePage();
      case 5:
        return _communityPage();
      case 6:
        return _guidelinesPage();
      case 7:
        return _settingsPage();
      default:
        return _dashboard();
    }
  }

  Widget _dashboard() => ListView(
        padding: const EdgeInsets.all(26),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0E3B25), Color(0xFF2E6B3D)],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 700;
                final intro = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.10),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'WILDORA • SMART WILDLIFE SAFETY',
                        style: TextStyle(color: Color(0xFFDCEFC1), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'From Forest\n'
                      'to Forecast.',
                      style: TextStyle(color: Colors.white, fontSize: compact ? 30 : 42, fontWeight: FontWeight.w900, height: 1.02),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'WILDORA combines location intelligence, machine-learning risk prediction and community reports to help people understand wildlife conflict before it becomes a problem.',
                      style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.55),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(onPressed: () => setState(() => page = 1), icon: const Icon(Icons.map_outlined), label: const Text('Explore live map')),
                        OutlinedButton.icon(onPressed: () => setState(() => page = 2), icon: const Icon(Icons.radar), label: const Text('Predict risk'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54))),
                      ],
                    ),
                  ],
                );
                return compact ? intro : Row(children: [Expanded(child: intro), const SizedBox(width: 30), _dashboardOrb()]);
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text('What WILDORA does', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final count = c.maxWidth > 1000 ? 4 : c.maxWidth > 650 ? 2 : 1;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: count,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.45,
              children: [
                _imageFeatureCard('https://images.unsplash.com/photo-1473448912268-2022ce9509d8?auto=format&fit=crop&w=900&q=80', Icons.touch_app_rounded, 'Explore the map', 'Tap any exact point and send that location to the ML risk model.'),
                _imageFeatureCard('https://images.unsplash.com/photo-1511497584788-876760111969?auto=format&fit=crop&w=900&q=80', Icons.schedule_rounded, 'Test a time', 'Choose a place and manually set the hour and minute you want to check.'),
                _imageFeatureCard('https://images.unsplash.com/photo-1549366021-9f761d450615?auto=format&fit=crop&w=900&q=80', Icons.analytics_outlined, 'Understand risk', 'See the prediction probability and the main factor returned by the model.'),
                _imageFeatureCard('https://images.unsplash.com/photo-1557050543-4d5f4e07ef46?auto=format&fit=crop&w=900&q=80', Icons.groups_rounded, 'Share locally', 'Community reports add real-world context for other WILDORA users.'),
              ],
            );
          }),
          const SizedBox(height: 24),
          const Text('How one check works', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          _how('01', 'Choose a place', 'Search a place manually or tap an exact point on the Wildlife Risk Map.'),
          _how('02', 'Set the time', 'Use the manual time selector when you want to test a particular time of day.'),
          _how('03', 'Get a model result', 'The selected coordinates and time are sent to the existing ML prediction service.'),
          _how('04', 'Act safely', 'Use the result as an awareness tool and check community reports for local context.'),
          const SizedBox(height: 14),
          _panel(
            'Latest activity',
            Row(children: [
              const CircleAvatar(backgroundColor: Color(0xFFEAF4EC), child: Icon(Icons.insights_outlined, color: Color(0xFF2E6B3D))),
              const SizedBox(width: 12),
              Expanded(child: Text(
                result == null ? 'Run a prediction to see your latest model result here.' : 'Latest check: $place • ${result!.risk} risk • ${result!.probability.toStringAsFixed(1)}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )),
              TextButton(onPressed: () => setState(() => page = 3), child: const Text('View reports')),
            ]),
          ),
        ],
      );

  Widget _how(String number, String title, String body) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E8E1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4EC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                number,
                style: const TextStyle(
                  color: Color(0xFF2E6B3D),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _dashboardOrb() => Container(
        width: 210,
        height: 210,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(.08),
          border: Border.all(color: Colors.white.withOpacity(.12), width: 1.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forest_rounded, color: Color(0xFFDCEFC1), size: 58),
            SizedBox(height: 12),
            Text('FOREST + DATA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
            SizedBox(height: 4),
            Text('Smarter coexistence', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      );

  Widget _imageFeatureCard(String imageUrl, IconData icon, String title, String body) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E8E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 112,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFDDE9DD))),
                  Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(.45)]))),
                  Positioned(left: 14, bottom: 12, child: CircleAvatar(backgroundColor: Colors.white, child: Icon(icon, color: const Color(0xFF2E6B3D)))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(body, style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.35)),
              ]),
            ),
          ],
        ),
      );

  Widget _featureCard(IconData icon, String title, String body) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1E8E1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(backgroundColor: const Color(0xFFEAF4EC), child: Icon(icon, color: const Color(0xFF2E6B3D))),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(body, style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.35)),
        ]),
      );

  Widget _mapPage() => Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: map,
                  options: MapOptions(
                    initialCenter: LatLng(lat, lon),
                    initialZoom: 7.8,
                    onTap: _clickMap,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.wildora.app',
                    ),
                    MarkerLayer(
                      markers: [
                        ...spots.map(
                          (s) => Marker(
                            point: LatLng((s['lat'] as num).toDouble(), (s['lon'] as num).toDouble()),
                            width: 42,
                            height: 42,
                            child: GestureDetector(
                              onTap: () => _checkRisk((s['lat'] as num).toDouble(), (s['lon'] as num).toDouble(), s['name'] as String),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E6B3D),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                ),
                                child: const Icon(Icons.pets, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                        Marker(
                          point: LatLng(lat, lon),
                          width: 48,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: const Icon(Icons.my_location, color: Colors.white, size: 21),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(top: 18, left: 18, right: 18, child: _mapBanner()),
                if (result != null && !loading)
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: _mapPredictionCard(),
                  ),
                Positioned(
                  top: 78,
                  right: 18,
                  child: _liveLocationButton(),
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: _mapButton(Icons.my_location, () => map.move(LatLng(lat, lon), 15)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.pets, color: Color(0xFF2E6B3D)),
                const SizedBox(width: 8),
                const Expanded(child: Text('Known wildlife areas are reference markers. Click anywhere on the map for a fresh ML prediction.', style: TextStyle(color: Colors.grey, fontSize: 12))),
                if (locating) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
        ],
      );

  Widget _mapBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.95), borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black12)]),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF1E5631)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loading
                    ? 'Checking selected coordinates…'
                    : (_errorMessage != null
                        ? _errorMessage!
                        : '${place} • ${result?.risk ?? 'No prediction'} • ${result == null ? '' : result!.probability.toStringAsFixed(1) + '%'}'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  Widget _mapPredictionCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.97),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(blurRadius: 14, color: Colors.black26)],
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: result!.riskColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${result!.risk} RISK • ${result!.probability.toStringAsFixed(1)}%', style: TextStyle(color: result!.riskColor, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('$place • ${result!.timeUsed}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Key driver: ${result!.driver}', style: const TextStyle(fontSize: 11, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open prediction details',
              onPressed: () => setState(() => page = 2),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          ],
        ),
      );

  Widget _liveLocationButton() => Material(
        color: tracking ? const Color(0xFF1E5631) : Colors.white,
        elevation: 5,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: locating ? null : _startTracking,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locating)
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: tracking ? Colors.white : const Color(0xFF1E5631)))
                else
                  Icon(tracking ? Icons.stop_circle_outlined : Icons.gps_fixed, color: tracking ? Colors.white : const Color(0xFF1E5631), size: 19),
                const SizedBox(width: 8),
                Text(
                  locating ? 'Getting location…' : tracking ? 'LIVE • TRACKING' : 'USE LIVE LOCATION',
                  style: TextStyle(color: tracking ? Colors.white : const Color(0xFF1E5631), fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _mapButton(IconData i, VoidCallback f) => FloatingActionButton.small(
        heroTag: Object(),
        onPressed: f,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E5631),
        child: Icon(i),
      );

  Widget _predictPage() => ListView(
        padding: const EdgeInsets.all(26),
        children: [
          const Text('Predict Risk', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Enter a place manually, choose the time, or pick a point on the live map.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 22),
          _manualPredictCard(),
          const SizedBox(height: 18),
          _currentPredictionCard(),
          if (result != null) ...[
            const SizedBox(height: 22),
            Row(children: [
              const Expanded(child: Text('Recent community reports', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              TextButton(onPressed: () => setState(() => page = 5), child: const Text('Open all')),
            ]),
            const SizedBox(height: 8),
            if (_reports.isEmpty)
              _panel('Community feed', const Text('No shared reports yet.', style: TextStyle(color: Colors.grey)))
            else
              ..._reports.take(3).map(_reportPreview),
          ],
        ],
      );

  Widget _manualPredictCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.edit_location_alt_outlined, color: Color(0xFF2E6B3D)), SizedBox(width: 10), Text('Manual place & time', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))]),
            const SizedBox(height: 7),
            const Text('Use the manual search to enter a place and the exact time you want the model to check.', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: loading ? null : _openManualSearch,
                icon: const Icon(Icons.search),
                label: const Text('Enter Place & Manual Time', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => page = 1), icon: const Icon(Icons.map_outlined), label: const Text('Pick on Map'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: _startTracking, icon: const Icon(Icons.my_location), label: const Text('Use My Location'))),
              ],
            ),
          ],
        ),
      );

  Widget _currentPredictionCard() {
    if (loading) {
      return _panel('Current prediction', const Center(child: Padding(padding: EdgeInsets.all(35), child: CircularProgressIndicator())));
    }
    if (result == null) {
      return _panel(
        'Current prediction',
        Text(_errorMessage ?? 'No prediction is available yet. Choose a place and run a prediction.', style: const TextStyle(color: Colors.grey)),
      );
    }
    return _panel(
      'Current prediction',
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: result!.riskColor.withOpacity(.07), borderRadius: BorderRadius.circular(15), border: Border.all(color: result!.riskColor.withOpacity(.35))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Text(result!.risk, style: TextStyle(color: result!.riskColor, fontSize: 22, fontWeight: FontWeight.w900)), const Spacer(), Text('${result!.probability.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))]),
            const SizedBox(height: 12),
            Text('Location: $place'),
            const SizedBox(height: 6),
            Text('Key driver: ${result!.driver}'),
            const SizedBox(height: 6),
            Text('Model time: ${result!.timeUsed}', style: const TextStyle(color: Colors.grey)),
            if (result!.timeProfileLabel != null) ...[const SizedBox(height: 6), Text(result!.timeProfileLabel!, style: const TextStyle(color: Colors.grey))],
          ],
        ),
      ),
    );
  }

  Widget _panel(String title, Widget child) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 14), child]),
      );

  Widget _reportsPage() => ListView(
        padding: const EdgeInsets.all(26),
        children: [
          const Text('Reports', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Review prediction results and your community submissions.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 22),
          _reportSummaryCard(),
          const SizedBox(height: 18),
          _panel(
            'Latest prediction',
            result == null
                ? const Text('No prediction yet.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(place, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('${result!.risk} risk • ${result!.probability.toStringAsFixed(1)}% probability'),
                    const SizedBox(height: 6),
                    Text('Key driver: ${result!.driver}'),
                    const SizedBox(height: 6),
                    Text('Checked at ${result!.timeUsed}'),
                  ]),
          ),
          const SizedBox(height: 18),
          _panel(
            'Community report activity',
            _reports.isEmpty
                ? const Text('No community reports submitted yet.', style: TextStyle(color: Colors.grey))
                : Column(children: _reports.map(_reportPreview).toList()),
          ),
        ],
      );

  Widget _reportSummaryCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFFEAF4EC), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const CircleAvatar(radius: 26, backgroundColor: Colors.white, child: Icon(Icons.description_outlined, color: Color(0xFF2E6B3D))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${_reports.length} community report${_reports.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 4), const Text('Submitted reports appear here with their submission time.', style: TextStyle(color: Colors.black54))])),
        ]),
      );

  Widget _wildlifePage() => ListView(
        padding: const EdgeInsets.all(26),
        children: [
          const Text('Wildlife', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Meet the wildlife species commonly associated with human-wildlife conflict in the region.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 22),
          LayoutBuilder(builder: (c, con) {
            final count = con.maxWidth > 1050 ? 3 : con.maxWidth > 650 ? 2 : 1;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: count,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.18,
              children: _animals.map(_animalCard).toList(),
            );
          }),
        ],
      );

  final List<Map<String, String>> _animals = const [
    {
      'name': 'Bengal Tiger',
      'scientific': 'Panthera tigris tigris',
      'habitat': 'Forests, grasslands & mangroves',
      'description': 'India’s iconic striped big cat and a major species in wildlife corridors.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/7/7c/A_Bengal_tiger%2C_Karnataka%2C_India_%28464044679%29.jpg',
    },
    {
      'name': 'Indian Leopard',
      'scientific': 'Panthera pardus fusca',
      'habitat': 'Forests, hills & scrublands',
      'description': 'An adaptable spotted cat found across many Indian landscapes.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/2/28/Indian_leopard_%28Panthera_pardus_fusca%29.jpg',
    },
    {
      'name': 'Asian Elephant',
      'scientific': 'Elephas maximus',
      'habitat': 'Forests & forest edges',
      'description': 'India’s native elephant species, moving through forests and traditional corridors.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/c/cb/Asian_Elephant_%28Elephas_maximus%29.jpg',
    },
    {
      'name': 'Chital (Spotted Deer)',
      'scientific': 'Axis axis',
      'habitat': 'Woodlands & grasslands',
      'description': 'A familiar spotted deer and an important prey species in Indian forests.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/2/29/Spotted_Deer_or_the_Chital.jpg',
    },
    {
      'name': 'Indian Peafowl',
      'scientific': 'Pavo cristatus',
      'habitat': 'Open forest, scrub & farmland edges',
      'description': 'India’s national bird, recognised by the male’s brilliant blue plumage.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/8/84/Indian_Peafowl_%28Pavo_cristatus%29.jpg',
    },
    {
      'name': 'Sloth Bear',
      'scientific': 'Melursus ursinus',
      'habitat': 'Dry forests, scrub & rocky areas',
      'description': 'A shaggy-coated bear native to the Indian subcontinent and often active at night.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/8/8e/SlothBear1.jpg',
    },
    {
      'name': 'Indian Rhinoceros',
      'scientific': 'Rhinoceros unicornis',
      'habitat': 'Alluvial grasslands & riverine forests',
      'description': 'The greater one-horned rhinoceros, native to the Indian subcontinent.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/5/52/An_Indian_rhinoceros_%28Rhinoceros_unicornis%29%2C_also_known_as_the_greater_one-horned_rhinoceros%2C_at_Kaziranga_National_Park%2C_Assam%2C_India.jpg',
    },
    {
      'name': 'Wild Boar',
      'scientific': 'Sus scrofa',
      'habitat': 'Forests, scrub & crop edges',
      'description': 'A strong and adaptable wild pig that commonly uses forest-edge habitats.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/6/6b/Indian_Wild_Boar.jpg',
    },
    {
      'name': 'Northern Plains Gray Langur',
      'scientific': 'Semnopithecus entellus',
      'habitat': 'Forests, hills & human-used landscapes',
      'description': 'A gray langur commonly seen across northern and central parts of India.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/a/a5/Northern_plains_gray_langur_in_Bandhavgarh_National_Park_02.jpg',
    },
    {
      'name': 'Asiatic Lion',
      'scientific': 'Panthera leo persica',
      'habitat': 'Dry deciduous forest & scrub',
      'description': 'India’s wild lion population is centred on the Gir landscape in Gujarat.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/e/ed/Asiatic_Lion_at_Gir_National_Park%2C_Gujrat%2C_India_01.jpg',
    },
    {
      'name': 'Common Kingfisher',
      'scientific': 'Alcedo atthis',
      'habitat': 'Streams, ponds & wetlands',
      'description': 'A small blue-and-orange kingfisher usually found close to freshwater.',
      'image': 'https://upload.wikimedia.org/wikipedia/commons/b/bc/Common_Kingfisher%2C_Bharatpur%2C_India.jpeg',
    },
  ];

  String _fastWildlifeImageUrl(String originalUrl) {
    // Keep the original Wikimedia URL as the source of truth, but fetch it
    // through a lightweight image proxy at a web-friendly size/format.
    return 'https://images.weserv.nl/?url=${Uri.encodeComponent(originalUrl)}&w=640&h=420&fit=cover&output=webp&q=82';
  }

  Future<void> _preloadWildlifeImages() async {
    // All 11 images start together. This is intentionally parallel so one
    // slow photo cannot hold up the other wildlife cards.
    await Future.wait(_animals.map((animal) async {
      final original = animal['image'];
      if (original == null || !mounted) return;
      try {
        await precacheImage(
          NetworkImage(_fastWildlifeImageUrl(original)),
          context,
        );
      } catch (_) {
        // The card itself has a direct Wikimedia fallback.
      }
    }));
  }

  Widget _animalCard(Map<String, String> a) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE1E8E1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              Image.network(
                _fastWildlifeImageUrl(a['image']!),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                cacheWidth: 640,
                errorBuilder: (_, __, ___) => Image.network(
                  a['image']!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFDDE9DD),
                    alignment: Alignment.center,
                    child: const Icon(Icons.pets_rounded, size: 55, color: Color(0xFF2E6B3D)),
                  ),
                ),
              ),
              Positioned(left: 12, top: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)), child: Text(a['habitat']!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['name']!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(a['scientific']!, style: const TextStyle(color: Color(0xFF2E6B3D), fontSize: 11, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(a['description']!, style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.4)),
          ])),
        ]),
      );

  Widget _communityPage() => ListView(
        padding: const EdgeInsets.all(26),
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Community Reports', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              SizedBox(height: 8),
              Text('Share a wildlife sighting or conflict report. Submitted reports are shared with the WILDORA community.', style: TextStyle(color: Colors.grey)),
            ])),
            IconButton(onPressed: _loadCommunityReports, tooltip: 'Refresh reports', icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 22),
          _communityForm(),
          const SizedBox(height: 24),
          const Text('Community feed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (_reports.isEmpty)
            _panel('No reports yet', const Text('Be the first to submit a wildlife report. It will appear here for other WILDORA users too.', style: TextStyle(color: Colors.grey)))
          else
            ..._reports.map(_reportPreview),
        ],
      );

  Widget _communityForm() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1E8E1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Submit a report', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          const Text('Add a clear description, location and an image when possible.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedReportType,
            decoration: _input('Report type'),
            items: const ['Animal sighting', 'Crop damage', 'Animal near road', 'Other'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
            onChanged: (v) => setState(() => _selectedReportType = v ?? 'Animal sighting'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _reportTitle, decoration: _input('Title', hint: 'Example: Elephant sighting near village')),
          const SizedBox(height: 12),
          TextField(controller: _reportLocation, decoration: _input('Location', hint: 'Village / town / area')),
          const SizedBox(height: 12),
          TextField(controller: _reportDescription, maxLines: 4, decoration: _input('Description', hint: 'Tell the community what happened...')),
          const SizedBox(height: 14),
          Row(children: [
            OutlinedButton.icon(onPressed: _pickReportImage, icon: const Icon(Icons.image_outlined), label: const Text('Upload image')),
            const SizedBox(width: 12),
            if (_reportImage.isNotEmpty) const Expanded(child: Text('Image selected ✓', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w700))),
          ]),
          if (_reportImage.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(base64Decode(_reportImage.split(',').last), height: 190, width: double.infinity, fit: BoxFit.cover)),
          ],
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: _submittingReport ? null : _submitReport, icon: const Icon(Icons.send_rounded), label: Text(_submittingReport ? 'Submitting...' : 'Submit Report'))),
        ]),
      );

  InputDecoration _input(String label, {String? hint}) => InputDecoration(
        labelText: label, hintText: hint, filled: true, fillColor: const Color(0xFFF4F7F2),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  Future<void> _pickReportImage() async {
    final input = web.HTMLInputElement()..type = 'file'..accept = 'image/*';
    input.click();
    final completer = Completer<void>();
    late StreamSubscription<web.Event> sub;
    sub = input.onChange.listen((_) async {
      final files = input.files;
      final file = (files != null && files.length > 0) ? files.item(0) : null;
      if (file == null) { await sub.cancel(); if (!completer.isCompleted) completer.complete(); return; }
      if (file.size > 650000) {
        _snack('Please choose an image smaller than 650 KB.');
        await sub.cancel(); if (!completer.isCompleted) completer.complete(); return;
      }
      final reader = web.FileReader();
      final done = Completer<void>();
      reader.onLoadEnd.listen((_) {
        final data = reader.result;
        if (data != null && mounted) setState(() => _reportImage = data.toString());
        if (!done.isCompleted) done.complete();
      });
      reader.readAsDataURL(file);
      await done.future;
      await sub.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  Future<void> _loadCommunityReports() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('community_reports')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 12));
      // Start the feed fresh: hide all reports that existed before the
      // reset date while keeping the Firestore submission feature intact.
      final loaded = snapshot.docs
          .where((doc) {
            final stamp = doc.data()['createdAt'];
            return stamp is Timestamp &&
                !stamp.toDate().toLocal().isBefore(_communityFeedReset);
          })
          .map(_ReportItem.fromFirestore)
          .toList();
      if (!mounted) return;
      setState(() { _reports..clear()..addAll(loaded); });
    } catch (_) {
      // The form remains usable; a later refresh can load the community feed.
    }
  }

  Future<void> _submitReport() async {
    final title = _reportTitle.text.trim();
    final description = _reportDescription.text.trim();
    final location = _reportLocation.text.trim();

    if (title.isEmpty || description.isEmpty || location.isEmpty) {
      _snack('Please fill title, location and description.');
      return;
    }

    if (_submittingReport) return;
    setState(() => _submittingReport = true);

    final reportData = <String, dynamic>{
      'type': _selectedReportType,
      'title': '${_selectedReportType}: $title',
      'description': description,
      'location': location,
      'imageDataUrl': _reportImage,
      'author': username.isEmpty ? 'Community member' : username,
      'authorUid': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      // Wait for the real Firestore write. This is what makes the report
      // available to other logged-in WILDORA users.
      final doc = await FirebaseFirestore.instance
          .collection('community_reports')
          .add(reportData)
          .timeout(const Duration(seconds: 15));

      // Put the successfully saved report at the bottom of the form/feed
      // immediately instead of waiting for another read to finish.
      final localReport = _ReportItem(
        title: '${_selectedReportType}: $title',
        description: description,
        location: location,
        imageDataUrl: _reportImage,
        time: DateTime.now(),
        author: username.isEmpty ? 'Community member' : username,
      );

      _reportTitle.clear();
      _reportDescription.clear();
      _reportLocation.clear();
      if (!mounted) return;
      setState(() {
        _reportImage = '';
        _submittingReport = false;
        _reports.insert(0, localReport);
      });

      _snack('Report submitted successfully. Others can now read it.');

      // Refresh from Firestore in the background so the feed is synchronized
      // with the server and other users' reports.
      _loadCommunityReports();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _submittingReport = false);
      final reason = e.code == 'permission-denied'
          ? 'Firestore rules are blocking this submission.'
          : e.code == 'failed-precondition'
              ? 'Firestore is not fully configured for this Firebase project.'
              : 'Firebase error: ${e.code}';
      _snack(reason);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _submittingReport = false);
      _snack('Submission timed out. Check your Firebase Firestore connection.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingReport = false);
      _snack('Could not submit the report. Please try again.');
    }
  }

  Widget _reportPreview(_ReportItem r) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8E1))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (r.imageDataUrl.isNotEmpty)
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(r.imageDataUrl.split(',').last), width: 105, height: 105, fit: BoxFit.cover))
          else
            Container(width: 105, height: 105, decoration: BoxDecoration(color: const Color(0xFFEAF4EC), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.image_not_supported_outlined, color: Color(0xFF2E6B3D), size: 32)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(r.description, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 7),
            Text('📍 ${r.location}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text('By ${r.author} • ${_formatDateTime(r.time)}', style: const TextStyle(color: Color(0xFF2E6B3D), fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
        ]),
      );

  String _formatDateTime(DateTime d) {
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm $ap';
  }

  Widget _guidelinesPage() => ListView(
        padding: const EdgeInsets.all(26),
        children: [
          const Text('Guidelines', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Practical guidelines for safer wildlife coexistence.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 22),
          _resource('Before travelling', Icons.route_outlined, 'Check the risk of your route or destination before entering a wildlife-sensitive area.'),
          _resource('If you see wildlife', Icons.visibility_outlined, 'Keep a safe distance, do not chase or feed animals, and avoid sudden movements.'),
          _resource('If there is conflict', Icons.warning_amber_rounded, 'Move to a safe place first and report the incident with the location and an image when possible.'),
          _resource('Using the map', Icons.map_outlined, 'Tap any point on the map. WILDORA sends that exact coordinate to the prediction service.'),
        ],
      );

  Widget _resource(String title, IconData icon, String body) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [CircleAvatar(backgroundColor: const Color(0xFFEAF4EC), child: Icon(icon, color: const Color(0xFF2E6B3D))), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 5), Text(body, style: const TextStyle(color: Colors.black54, height: 1.45))]))]),
      );

  Widget _settingsPage() => ListView(
        padding: const EdgeInsets.all(26),
        children: [
          const Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Manage your WILDORA profile and app assistance.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 22),
          _settingsTile(Icons.person_outline, 'Profile', username, _showProfile),
          _settingsTile(Icons.location_on_outlined, 'Location', 'Use your current browser location for map predictions', _showLocationHelp),
          _settingsTile(Icons.help_outline, 'Help & Support', 'Get help using the map, predictions and reports', _showHelp),
          _settingsTile(Icons.logout, 'Sign out', 'Sign out of this account', () => FirebaseAuth.instance.signOut()),
        ],
      );

  Widget _settingsTile(IconData icon, String title, String subtitle, VoidCallback onTap) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: ListTile(leading: CircleAvatar(backgroundColor: const Color(0xFFEAF4EC), child: Icon(icon, color: const Color(0xFF2E6B3D))), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap),
      );

  void _showAlerts() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [Icon(Icons.notifications_active_outlined, color: Color(0xFF2E6B3D)), SizedBox(width: 8), Text('Alerts')]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Latest activity', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(result == null ? 'No prediction alert available.' : 'Latest risk check for $place: ${result!.risk} (${result!.probability.toStringAsFixed(1)}%).'),
          const SizedBox(height: 10),
          Text(_reports.isEmpty ? 'No community reports submitted.' : '${_reports.length} community report${_reports.length == 1 ? '' : 's'} submitted.'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showProfile() {
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Profile'), content: Text('$username\n$email'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
  }

  void _showLocationHelp() {
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Location'), content: const Text('Use My Location asks Chrome for your current GPS position. The position is then used to request a prediction from the existing model backend.'), actions: [TextButton(onPressed: () { Navigator.pop(context); _startTracking(); }, child: const Text('Use My Location'))]));
  }

  void _showHelp() {
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Help & Support'), content: const Text('• Wildlife Risk Map: tap anywhere to check that exact point.\n\n• Predict Risk: search for a place and choose a manual time.\n\n• Community Reports: upload an image and submit a sighting or conflict report.\n\n• Settings → Location: allow GPS when using your current location.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))]));
  }
}
