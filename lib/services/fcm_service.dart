import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'local_notification_service.dart';
import '../database/database_helper.dart';
import '../firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> handleBhwBackgroundMessage(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  }
  await FCMService.showAssignedMessage(message);
}

/// Handles Firebase Cloud Messaging registration and incoming push
/// notifications from the (future) backend — e.g. a BHN flagging a record
/// from the web dashboard, or a re-classification result from the real
/// Random Forest model once `POST /predict` exists server-side.
///
/// This is a distinct channel from [LocalNotificationService]: local
/// notifications are generated entirely on-device (works fully offline,
/// used today for the rule-based risk classifier and no-visit alerts). FCM
/// is for alerts that originate on the server and need to reach a specific
/// BHW's phone — it cannot function offline or before a backend exists.
///
/// The device token is written to this worker's own `users` document as
/// `fcmToken`, which is what the dashboard's /api/notify-bhw reads to
/// target a push. Registration used to stop at fetching the token and
/// dropping it on the floor behind a TODO, so the permission prompt and
/// the whitelisted rule field made push look wired up when nothing could
/// ever arrive.
///
/// [registerToken] is called again after sign-in: at app start there is
/// usually no session yet, and the write needs one.
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  FirebaseMessaging? _messaging;
  String? _token;
  String? get token => _token;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // main() has already initialised Firebase with the generated
      // options; this is a no-op on a warm app and a safety net if the
      // service is ever constructed first.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(handleBhwBackgroundMessage);
      await _messaging!
          .requestPermission(alert: true, badge: true, sound: true);

      _token = await _messaging!.getToken();
      await registerToken();

      _messaging!.onTokenRefresh.listen((newToken) async {
        _token = newToken;
        await registerToken();
      });

      // Foreground messages: FCM doesn't show a system tray notification
      // automatically while the app is open, so route it through the same
      // local-notification presentation used for on-device alerts, for a
      // consistent look regardless of which channel triggered it.
      FirebaseMessaging.onMessage.listen(showAssignedMessage);
    } catch (_) {
      // Push is a convenience on top of the on-device alerts. If the
      // device refuses permission, or there is no network at start-up,
      // the rest of the app must carry on working exactly as before.
    }
  }

  /// Validate the signed-in worker and current server assignment. A delayed
  /// message for a previous user or previous assignment is silently discarded.
  static Future<void> showAssignedMessage(RemoteMessage message) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final patientId = message.data['patientId'];
      final preferences = await SharedPreferences.getInstance();
      if (uid == null ||
          message.data['bhwId'] != uid ||
          patientId == null ||
          preferences.getString('current_user_id') != uid) {
        return;
      }
      final patient = await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .get(const GetOptions(source: Source.server));
      if (!patient.exists ||
          patient.data()?['assignedBhwId'] != uid ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      final service = LocalNotificationService();
      final alertId = message.data['alertId'];
      if (alertId == null || alertId.isEmpty) return;
      final alert = await FirebaseFirestore.instance
          .collection('alerts')
          .doc(alertId)
          .get(const GetOptions(source: Source.server));
      final data = alert.data();
      if (!alert.exists ||
          data?['patientId'] != patientId ||
          data?['assignedBhwId'] != uid ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      if (data?['acknowledged'] == true || data?['resolved'] == true) {
        await service.cancelAlert(alertId);
        return;
      }
      final raisedAt = data?['raisedAt'];
      final local = await DatabaseHelper().getNotificationById(alertId);
      if (local != null &&
          (local.isRead || local.resolved) &&
          raisedAt is Timestamp &&
          local.createdAt.millisecondsSinceEpoch ==
              raisedAt.millisecondsSinceEpoch) {
        await service.cancelAlert(alertId);
        return;
      }
      final sentAt = message.data['alertRaisedAt'];
      if (sentAt != null &&
          sentAt.isNotEmpty &&
          raisedAt is Timestamp &&
          sentAt != raisedAt.millisecondsSinceEpoch.toString()) {
        return;
      }
      final name = message.data['patientName'] ?? '';
      final body = message.data['body'] ?? message.notification?.body ?? '';
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;
      if (message.data['type'] == 'no_visit') {
        await service.showNoVisitAlert(
            patientName: name, message: body, alertId: alertId);
      } else {
        await service.showHighRiskAlert(
            patientName: name, message: body, alertId: alertId);
      }
    } catch (_) {
      // The durable alert remains available on the next successful sync.
    }
  }

  /// Writes the device token to this worker's own user document.
  ///
  /// Safe to call repeatedly — on sign-in, on token refresh, and at
  /// start-up. Without a signed-in user there is nowhere to write it, so
  /// it simply returns and the next call after sign-in does the work.
  Future<void> registerToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = _token;
    if (uid == null || token == null || token.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Offline, or the document is not writable right now. The next
      // sign-in or token refresh tries again.
    }
  }

  /// Clears the token on sign-out so a push meant for this worker does
  /// not arrive on a handset someone else has signed into.
  Future<void> clearToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': '',
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
