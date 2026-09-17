import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'prediction_service.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  await notificationsPlugin.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
}

Future<void> showRiskNotification(
    PredictionResult result, double lat, double lon) async {
  if (result.risk == 'LOW') return;

  final androidDetails = AndroidNotificationDetails(
    'hwc_risk_channel',
    'HWC Risk Alerts',
    channelDescription: 'Alerts when you enter a wildlife conflict zone',
    importance: result.risk == 'HIGH' ? Importance.max : Importance.high,
    priority: result.risk == 'HIGH' ? Priority.max : Priority.high,
    color: result.riskColor,
    icon: '@mipmap/ic_launcher',
  );

  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  await notificationsPlugin.show(
    0,
    '${result.riskEmoji} ${result.risk} Risk Area Detected!',
    '${result.probability.toStringAsFixed(1)}% conflict probability near '
        '(${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)})',
    NotificationDetails(android: androidDetails, iOS: iosDetails),
  );
}

Future<bool> requestLocationPermission() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

Future<Position?> getCurrentPosition() async {
  final hasPermission = await requestLocationPermission();
  if (!hasPermission) return null;
  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
}
