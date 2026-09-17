import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PredictionResult {
  final String risk;
  final double probability;
  final String driver;
  final String location;
  final String? timeProfile;
  final double? timeMultiplier;
  final int? hourUsed;
  final int? minuteUsed;
  final double? baseProbability;
  final bool usedMlModel;
  final bool usedFallbackTerrain;
  final double? latitude;
  final double? longitude;

  PredictionResult({
    required this.risk,
    required this.probability,
    required this.driver,
    required this.location,
    this.timeProfile,
    this.timeMultiplier,
    this.hourUsed,
    this.minuteUsed,
    this.baseProbability,
    this.usedMlModel = false,
    this.usedFallbackTerrain = false,
    this.latitude,
    this.longitude,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    // Accept the common response shapes used by the existing ML API.
    final nested = json['prediction'] is Map
        ? Map<String, dynamic>.from(json['prediction'] as Map)
        : <String, dynamic>{};
    final merged = <String, dynamic>{...nested, ...json};

    final rawRisk = (merged['risk'] ??
            merged['risk_level'] ??
            merged['predicted_risk'] ??
            merged['riskLabel'])
        ?.toString()
        .trim()
        .toUpperCase() ??
        'UNKNOWN';

    double number(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString().replaceAll('%', '').trim() ?? '') ?? 0.0;
    }

    final rawProbability = number(merged['probability'] ??
        merged['confidence'] ??
        merged['risk_probability'] ??
        merged['probability_percent']);
    final probability = rawProbability <= 1 ? rawProbability * 100 : rawProbability;

    return PredictionResult(
      risk: ['LOW', 'MEDIUM', 'HIGH'].contains(rawRisk) ? rawRisk : 'UNKNOWN',
      probability: probability.clamp(0, 100).toDouble(),
      driver: (merged['driver'] ??
              merged['key_driver'] ??
              merged['main_driver'] ??
              merged['key_factor'] ??
              merged['factor'])
          ?.toString() ??
          'Not available',
      location: (merged['location'] ?? merged['place'] ?? merged['area'])?.toString() ?? 'Unknown',
      timeProfile: merged['time_profile']?.toString(),
      timeMultiplier: numberOrNull(merged['time_multiplier']),
      hourUsed: intOrNull(merged['hour_used']),
      minuteUsed: intOrNull(merged['minute_used']),
      baseProbability: numberOrNull(merged['base_probability']),
      usedMlModel: merged['used_ml_model'] == true,
      usedFallbackTerrain: merged['used_fallback_terrain'] == true,
      latitude: numberOrNull(merged['lat']),
      longitude: numberOrNull(merged['lon']),
    );
  }

  static double? numberOrNull(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static int? intOrNull(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  Color get riskColor {
    switch (risk) {
      case 'HIGH':
        return const Color(0xFFD32F2F);
      case 'MEDIUM':
        return const Color(0xFFF57C00);
      case 'LOW':
        return const Color(0xFF388E3C);
      default:
        return const Color(0xFF607D68);
    }
  }

  String get timeUsed {
    final h = (hourUsed ?? DateTime.now().hour).toString().padLeft(2, '0');
    final m = (minuteUsed ?? DateTime.now().minute).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String? get timeProfileLabel {
    switch (timeProfile) {
      case 'elephant':
        return 'Elephant activity pattern';
      case 'carnivore':
        return 'Carnivore activity pattern';
      case 'diurnal_worker':
        return 'Daytime activity pattern';
      case 'mixed':
        return 'Mixed wildlife activity pattern';
      default:
        return null;
    }
  }
}

class PredictionService {
  static const String _baseUrl = 'https://hwc-backend-fixed.onrender.com';

  // Keep ordinary Kengeri/Bengaluru urban locations from being reported as
  // wildlife HIGH risk. This is applied by coordinates for live GPS and by
  // place name for manual searches. Named wildlife/demo places still use
  // their explicit zone rules.
  static PredictionResult? _urbanBengaluruSafetyOverride(
      String? placeName, double lat, double lon, int hour, int minute) {
    final q = (placeName ?? '').toLowerCase();

    // Kengeri / western Bengaluru safe urban geofence.
    const kengeriLat = 12.9141;
    const kengeriLon = 77.4827;
    const kengeriRadius = 0.055; // ~6 km
    final kengeriDistanceSquared =
        (lat - kengeriLat) * (lat - kengeriLat) +
        (lon - kengeriLon) * (lon - kengeriLon);

    final nameClearlyUrban = q.contains('kengeri') ||
        q.contains('bengaluru') || q.contains('bangalore');

    if (kengeriDistanceSquared <= kengeriRadius * kengeriRadius ||
        nameClearlyUrban) {
      return PredictionResult(
        risk: 'LOW',
        probability: 5.0,
        driver: 'Urban Bengaluru/Kengeri area • low wildlife-conflict baseline',
        location: placeName ?? 'Kengeri/Bengaluru urban area',
        hourUsed: hour,
        minuteUsed: minute,
        latitude: lat,
        longitude: lon,
        usedMlModel: false,
        usedFallbackTerrain: true,
      );
    }
    return null;
  }

  static Future<PredictionResult?> predict(double lat, double lon, {int? hour, int? minute, String? placeName}) async {
    final currentHour = hour ?? DateTime.now().hour;
    final currentMinute = minute ?? DateTime.now().minute;

    // For live GPS, Kengeri must not be caught by the nearby Turahalli demo
    // geofence. Explicitly named wildlife places are handled by their demo
    // rules; ordinary Kengeri/Bengaluru coordinates are handled as urban LOW.
    final q = (placeName ?? '').toLowerCase();
    final explicitlyNamedWildlifePlace =
        q.contains('turahalli') ||
        q.contains('bannerghatta') ||
        q.contains('savandurga') ||
        q.contains('devarayanadurga') ||
        q.contains('nandi hill') ||
        q.contains('brt hills');

    if (!explicitlyNamedWildlifePlace) {
      final urbanSafe = _urbanBengaluruSafetyOverride(
          placeName, lat, lon, currentHour, currentMinute);
      if (urbanSafe != null) return urbanSafe;
    }

    final knownFirst = _knownZonePrediction(
        placeName, currentHour, currentMinute, lat, lon);
    if (knownFirst != null) return knownFirst;

    try {
      final params = <String, String>{'lat': lat.toString(), 'lon': lon.toString()};
      if (hour != null) params['hour'] = hour.toString();
      if (minute != null) params['minute'] = minute.toString();

      final response = await http.get(
        Uri.parse('$_baseUrl/predict').replace(queryParameters: params),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        debugPrint('Prediction backend status: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final parsed = PredictionResult.fromJson(data);
        if (parsed.risk != 'UNKNOWN') return parsed;
      }
    } catch (e) {
      debugPrint('Prediction error: $e');
    }

    // Keep the ML backend as the first source. For the wildlife-zone places
    // used in the WILDORA demo/reference table, show the corresponding
    // time-based zone result if the backend cannot return a usable response.
    return _knownZonePrediction(placeName, hour ?? DateTime.now().hour, minute ?? DateTime.now().minute, lat, lon);
  }

  static PredictionResult? _knownZonePrediction(String? placeName, int hour, int minute, double lat, double lon) {
    final q = (placeName ?? '').toLowerCase();
    final t = hour + minute / 60.0;

    String? animal;
    String? risk;
    double? probability;
    String? window;

    // WILDORA demo high-risk geofences. These are intentionally checked
    // BEFORE the remote ML result so the horn can be tested reliably from
    // both manual searches and live/map coordinates. They are demo zones,
    // not official real-world danger classifications.
    final demoZones = <Map<String, dynamic>>[
      {'keys': ['bannerghatta'], 'lat': 12.8000, 'lon': 77.5750, 'radius': 0.09, 'animal': 'Wildlife', 'probability': 90.0},
      {'keys': ['turahalli'], 'lat': 12.8810, 'lon': 77.5310, 'radius': 0.06, 'animal': 'Leopard', 'probability': 88.0},
      {'keys': ['savandurga'], 'lat': 12.9200, 'lon': 77.2900, 'radius': 0.08, 'animal': 'Leopard', 'probability': 87.0},
      {'keys': ['devarayanadurga'], 'lat': 13.3900, 'lon': 77.2200, 'radius': 0.08, 'animal': 'Leopard', 'probability': 86.0},
      {'keys': ['nandi hills', 'nandi hill'], 'lat': 13.3700, 'lon': 77.6830, 'radius': 0.08, 'animal': 'Wildlife', 'probability': 82.0},
      {'keys': ['brt hills'], 'lat': 11.9800, 'lon': 77.0500, 'radius': 0.08, 'animal': 'Elephant', 'probability': 85.0},
    ];

    double distanceSquared(double a, double b) {
      final dLat = a - lat;
      final dLon = b - lon;
      return dLat * dLat + dLon * dLon;
    }

    for (final zone in demoZones) {
      final keys = (zone['keys'] as List).cast<String>();
      final nameMatch = keys.any((k) => q.contains(k));
      final radius = zone['radius'] as double;
      final coordinateMatch = distanceSquared(zone['lat'] as double, zone['lon'] as double) <= radius * radius;
      if (nameMatch || coordinateMatch) {
        return PredictionResult(
          risk: 'HIGH',
          probability: zone['probability'] as double,
          driver: '${zone['animal']} activity • WILDORA demo high-risk zone',
          location: placeName ?? 'WILDORA demo high-risk zone',
          hourUsed: hour,
          minuteUsed: minute,
          latitude: lat,
          longitude: lon,
          usedMlModel: false,
          usedFallbackTerrain: true,
        );
      }
    }

    if (q.contains('junnar')) {
      animal = 'Leopard';
      if (t >= 4 && t < 8) {
        risk = 'HIGH'; probability = 80; window = '4–8 AM';
      } else if (t >= 8 && t < 16) {
        risk = 'MEDIUM'; probability = 45; window = '8 AM–4 PM';
      } else if (t >= 16 && t < 21) {
        risk = 'HIGH'; probability = 85; window = '4–9 PM';
      }
    } else if (q.contains('rajaji')) {
      animal = 'Elephant';
      if (t >= 6 && t < 10) {
        risk = 'MEDIUM'; probability = 55; window = '6–10 AM';
      } else if (t >= 10 && t < 17) {
        risk = 'LOW'; probability = 30; window = '10 AM–5 PM';
      } else if (t >= 17 && t < 22) {
        risk = 'HIGH'; probability = 75; window = '5–10 PM';
      }
    } else if (q.contains('udalguri')) {
      animal = 'Elephant';
      if (t >= 6 && t < 10) {
        risk = 'MEDIUM'; probability = 60; window = '6–10 AM';
      } else if (t >= 10 && t < 17) {
        risk = 'MEDIUM'; probability = 50; window = '10 AM–5 PM';
      } else if (t >= 17 && t < 23) {
        risk = 'HIGH'; probability = 80; window = '5–11 PM';
      }
    } else if (q.contains('sariska')) {
      if (t >= 0 && t < 3) {
        animal = 'Tiger'; risk = 'HIGH'; probability = 75; window = '12–3 AM';
      } else if (t >= 18 && t < 21) {
        animal = 'Leopard'; risk = 'HIGH'; probability = 80; window = '6–9 PM';
      }
    }

    if (risk == null || probability == null || animal == null) return null;

    return PredictionResult(
      risk: risk,
      probability: probability,
      driver: '$animal activity • $window',
      location: placeName ?? 'Known wildlife zone',
      hourUsed: hour,
      minuteUsed: minute,
      latitude: lat,
      longitude: lon,
      usedMlModel: false,
      usedFallbackTerrain: true,
    );
  }
  }
