import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wraps flutter_local_notifications so the app can push an actual device
/// notification (not just an in-app list row) for high-risk records and
/// overdue-visit alerts. Without this, a BHW with the app closed gets no
/// signal at all, even though the protocol promises alerts "before
/// hypo- or hyperglycemic events."
class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    // Android 13+ requires runtime notification permission.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> showHighRiskAlert({
    required String patientName,
    required String message,
  }) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'diacare_high_risk',
      'High Risk Alerts',
      channelDescription: 'Notifies BHWs when a patient is classified as Highly At Risk',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF0B5357),
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _notificationId(patientName, 'high_risk'),
      'Highly At Risk: $patientName',
      message,
      details,
    );
  }

  Future<void> showNoVisitAlert({
    required String patientName,
    required String message,
  }) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'diacare_no_visit',
      'Overdue Visit Alerts',
      channelDescription: 'Notifies BHWs when a patient has not been visited recently',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF0B5357),
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _notificationId(patientName, 'no_visit'),
      'Visit Overdue: $patientName',
      message,
      details,
    );
  }

  /// Same patient can have both a high-risk AND a no-visit alert active at
  /// once. Using patientName.hashCode alone for both would give them the
  /// same Android notification ID, so the second one silently replaces the
  /// first in the tray instead of showing both. Salting by alert type keeps
  /// them distinct while staying deterministic (same patient+type always
  /// maps to the same ID, so re-showing an alert updates it rather than
  /// stacking duplicates).
  int _notificationId(String patientName, String type) {
    return '$patientName:$type'.hashCode & 0x7FFFFFFF;
  }
}
